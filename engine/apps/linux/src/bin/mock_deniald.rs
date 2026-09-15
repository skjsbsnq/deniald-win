//! mock 宿主开发工具：在 seqpacket socket 上扮演宿主守护进程回放
//! input-engine-v1，验证引擎服务的「按键 → 帧 → 上屏」链路与畸形包容错。
//!
//! 用法：`cargo run -p qingjian-linux --bin mock_deniald -- --spawn
//! target/debug/qingjian-linux`。`--spawn` 缺省时只监听，等外部引擎来连。
//! 只用于本机联调，不是产品件。

use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use clap::Parser;
use flatbuffers::FlatBufferBuilder;
use qingjian_linux::ime::message::{CloudOverride, EditorState, Endpoint, InputMode, Outbound};
use qingjian_linux::ime::wire::{decode_outbound, encode_inbound};
use qingjian_linux::ime::{Inbound, Link, Listener, PACKET_BUF};

/// 单步等待引擎回包的上限。
const STEP_TIMEOUT: Duration = Duration::from_secs(3);

/// 「不指望有回包」的静默观察窗口。
const SILENCE: Duration = Duration::from_millis(400);

/// 引擎断线后按退避重连，等它回来的上限。
const RECONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// input-engine-v1 回放的 mock 宿主。
#[derive(Parser)]
#[command(about)]
struct Args {
    /// 监听的 socket 路径；缺省 `$TMPDIR/qingjian-mock-deniald/ime.sock`。
    #[arg(long)]
    socket: Option<PathBuf>,

    /// 引擎二进制；给了就由本工具拉起，注入隔离的 XDG 目录与 US 布局。
    #[arg(long)]
    spawn: Option<PathBuf>,

    /// 传给引擎的 `--dict`；缺省仓库自带的手写样例词库。
    #[arg(long)]
    dict: Option<PathBuf>,
}

/// 汇总判定：每步打 PASS/FAIL，最后按失败数定退出码。
struct Report {
    /// 累计失败数。
    failures: usize,
}

impl Report {
    fn check(&mut self, name: &str, ok: bool, detail: impl std::fmt::Display) {
        if ok {
            println!("PASS  {name}: {detail}");
        } else {
            self.failures += 1;
            println!("FAIL  {name}: {detail}");
        }
    }
}

/// 拉起的引擎进程，工具退出时收掉。
struct Engine(Child);

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// 收一个包并解码成出站载荷；超时 / 断线 / 解码失败都是 `Err`。
fn recv_outbound(link: &Link, buf: &mut [u8]) -> io::Result<Outbound> {
    let len = link.recv(buf)?;
    if len == 0 {
        return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "对端关连接"));
    }
    decode_outbound(&buf[..len])
        .map(|decoded| decoded.outbound)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))
}

/// 收包直到 `stop` 命中或超时，返回这一段收到的全部载荷。
fn collect_until(
    link: &Link,
    timeout: Duration,
    stop: impl Fn(&Outbound) -> bool,
) -> Vec<Outbound> {
    let deadline = Instant::now() + timeout;
    let mut buf = vec![0u8; PACKET_BUF];
    let mut out = Vec::new();
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return out;
        }
        if link.set_read_timeout(left).is_err() {
            return out;
        }
        match recv_outbound(link, &mut buf) {
            Ok(message) => {
                let done = stop(&message);
                out.push(message);
                if done {
                    return out;
                }
            }
            Err(_) => return out,
        }
    }
}

/// 发一条宿主 → 引擎载荷，序号单调递增。
fn send(state: &mut MockState, message: Inbound) -> io::Result<()> {
    let packet = encode_inbound(&mut state.builder, &message, state.sequence);
    let packet = packet.to_vec();
    state.sequence += 1;
    state.link.send(&packet)
}

/// 一条连接上的回放状态。
struct MockState {
    /// 收包缓冲。
    link: Link,

    /// 复用的编码器。
    builder: FlatBufferBuilder<'static>,

    /// 出站（宿主方向）序号，从 1 起。
    sequence: u64,
}

impl MockState {
    fn new(link: Link) -> Self {
        Self {
            link,
            builder: FlatBufferBuilder::new(),
            sequence: 1,
        }
    }
}

/// 等引擎的 `ImeHello` + `ImeStatus(Ready)`；按序应连到。
fn expect_handshake(report: &mut Report, state: &mut MockState) -> bool {
    let buf_deadline = Instant::now() + STEP_TIMEOUT;
    let mut buf = vec![0u8; PACKET_BUF];
    let mut hello = false;
    let mut ready = false;
    while Instant::now() < buf_deadline && !(hello && ready) {
        if state
            .link
            .set_read_timeout(buf_deadline.saturating_duration_since(Instant::now()))
            .is_err()
        {
            break;
        }
        match recv_outbound(&state.link, &mut buf) {
            Ok(Outbound::Hello { name, version }) => {
                println!("      hello: {name} {version}");
                hello = true;
            }
            Ok(Outbound::Status { status, error }) => {
                ready = matches!(status, qingjian_linux::ime::message::EngineStatus::Ready);
                if let Some(error) = error {
                    println!("      status error: {error}");
                }
            }
            Ok(other) => println!("      握手期收到意外载荷：{other:?}"),
            Err(_) => break,
        }
    }
    report.check(
        "握手 Hello+Ready",
        hello && ready,
        format!("hello={hello} ready={ready}"),
    );
    hello && ready
}

/// 开激活：Activate + Done，等到 `ImeModeState`。
fn activate(report: &mut Report, state: &mut MockState, serial: u64, endpoint: Endpoint) {
    let editor = EditorState {
        app_id: "mock.editor".to_owned(),
        ..EditorState::default()
    };
    let activate = Inbound::Activate {
        serial,
        endpoint,
        editor,
        config: Vec::new(),
    };
    if send(state, activate).is_err() || send(state, Inbound::Done { serial }).is_err() {
        report.check("激活", false, "发送失败");
        return;
    }
    let out = collect_until(&state.link, STEP_TIMEOUT, |m| {
        matches!(m, Outbound::ModeState { .. })
    });
    let mode = out.iter().find_map(|m| match m {
        Outbound::ModeState {
            serial: s,
            mode,
            cloud_enabled,
        } => Some((*s, *mode, *cloud_enabled)),
        _ => None,
    });
    report.check(
        "激活回 ModeState",
        mode.is_some_and(|(s, _, _)| s == serial),
        format!("{mode:?}"),
    );
}

/// 敲一个键（按下 + 抬起，各自一个 key_id），收引出的全部载荷直到看见
/// 抬起那包的 `ImeKeyResult`（按下组的帧先发完）或超时。
fn key(
    report: &mut Report,
    state: &mut MockState,
    serial: u64,
    keycode: u32,
    press_id: u32,
    release_id: u32,
) -> Vec<Outbound> {
    for (pressed, key_id) in [(true, press_id), (false, release_id)] {
        let event = Inbound::KeyEvent {
            serial,
            keycode,
            modifiers: 0,
            pressed,
            key_id,
        };
        if send(state, event).is_err() {
            report.check("发按键", false, format!("key_id {key_id}"));
            return Vec::new();
        }
    }
    let out = collect_until(
        &state.link,
        STEP_TIMEOUT,
        |m| matches!(m, Outbound::KeyResult { key_id, .. } if *key_id == release_id),
    );
    // 按下要回 handled=true 且回显 key_id；抬起放行（handled=false）。
    let verdict = |key_id| {
        out.iter().find_map(|m| match m {
            Outbound::KeyResult {
                serial: s,
                key_id: k,
                handled,
            } if *k == key_id => Some((*s, *handled)),
            _ => None,
        })
    };
    report.check(
        "按键应答",
        verdict(press_id) == Some((serial, true)) && verdict(release_id) == Some((serial, false)),
        format!(
            "press {press_id} → {:?}，release {release_id} → {:?}",
            verdict(press_id),
            verdict(release_id)
        ),
    );
    out
}

/// 一次完整会话：激活 → 敲拼音 → 空格上屏 → 去激活；返回上屏文本。
fn session_round(report: &mut Report, state: &mut MockState, serial: u64) -> Option<String> {
    activate(report, state, serial, Endpoint::WaylandTextInput);
    // US 布局下 "nihao" 的 evdev 键码：n=49 i=23 h=35 a=30 o=24。
    let keys = [("n", 49), ("i", 23), ("h", 35), ("a", 30), ("o", 24)];
    let mut frames = 0usize;
    for (index, (_, keycode)) in keys.iter().enumerate() {
        let press_id = (index * 2 + 1) as u32;
        let out = key(report, state, serial, *keycode, press_id, press_id + 1);
        frames += out
            .iter()
            .filter(|m| matches!(m, Outbound::Frame { .. }))
            .count();
        for message in &out {
            if let Outbound::Frame { frame, .. } = message
                && !frame.candidates.is_empty()
            {
                println!(
                    "      候选：{}",
                    frame
                        .candidates
                        .iter()
                        .map(|c| c.text.as_str())
                        .collect::<Vec<_>>()
                        .join(" ")
                );
            }
        }
    }
    report.check(
        "组句期间有候选帧",
        frames >= keys.len(),
        format!("{frames} 帧"),
    );
    // 空格上屏高亮候选。
    let space = (keys.len() * 2 + 1) as u32;
    let out = key(report, state, serial, 57, space, space + 1);
    let committed = out.iter().find_map(|m| match m {
        Outbound::CommitText { serial: s, text } if *s == serial => Some(text.clone()),
        _ => None,
    });
    report.check(
        "空格上屏",
        committed.as_deref() == Some("你好"),
        format!("commit = {committed:?}"),
    );
    // 抬起空格的那包应答也该放行；然后 Deactivate 收尾。
    if send(state, Inbound::Deactivate { serial }).is_err() {
        report.check("去激活", false, "发送失败");
        return committed;
    }
    // 失配 serial 的按键必须被丢：收静默窗口，期望没回包。
    let event = Inbound::KeyEvent {
        serial,
        keycode: 49,
        modifiers: 0,
        pressed: true,
        key_id: 99,
    };
    let _ = send(state, event);
    let stray = collect_until(&state.link, SILENCE, |_| false);
    report.check(
        "去激活后静默",
        stray.is_empty(),
        format!("{} 包", stray.len()),
    );
    committed
}

/// EditorUpdate 分组回放：组内合并、陌生 serial 整条丢、不毁开着的组。
fn grouping_round(report: &mut Report, state: &mut MockState, serial: u64) {
    activate(report, state, serial, Endpoint::WaylandTextInput);
    let next = serial + 1;
    // 下一个激活的组开着时，混一条陌生 serial 的 EditorUpdate：
    // 它必须整条被丢，不能冲掉 pending 组。
    let editor = |app: &str| EditorState {
        app_id: app.to_owned(),
        ..EditorState::default()
    };
    let ok = send(
        state,
        Inbound::Activate {
            serial: next,
            endpoint: Endpoint::WaylandTextInput,
            editor: editor("mock.editor"),
            config: Vec::new(),
        },
    )
    .is_ok()
        && send(
            state,
            Inbound::EditorUpdate {
                serial: next + 500,
                editor: editor("stale.app"),
            },
        )
        .is_ok()
        && send(state, Inbound::Done { serial: next }).is_ok();
    if !ok {
        report.check("分组回放", false, "发送失败");
        return;
    }
    let out = collect_until(
        &state.link,
        STEP_TIMEOUT,
        |m| matches!(m, Outbound::ModeState { serial: s, .. } if *s == next),
    );
    report.check(
        "stale EditorUpdate 不毁 pending 组",
        out.iter()
            .any(|m| matches!(m, Outbound::ModeState { serial: s, .. } if *s == next)),
        format!("{} 包", out.len()),
    );
    // 激活外的陌生 serial 更新 + Done：全部静默。
    let _ = send(
        state,
        Inbound::EditorUpdate {
            serial: next + 500,
            editor: editor("stale.app"),
        },
    );
    let _ = send(state, Inbound::Done { serial: next + 500 });
    let stray = collect_until(&state.link, SILENCE, |_| false);
    report.check(
        "陌生 serial 的更新被丢",
        stray.is_empty(),
        format!("{} 包", stray.len()),
    );
    // 当前激活还活着：按一键有应答。
    let _ = key(report, state, next, 49, 1, 2);
    let _ = send(state, Inbound::Deactivate { serial: next });
}

/// Legacy 端点回放：激活默认英文直通，壳切中文后正常组句上屏，
/// 全程不出 InlinePreedit。
fn legacy_round(report: &mut Report, state: &mut MockState, serial: u64) {
    let editor = EditorState {
        app_id: "mock.x11".to_owned(),
        ..EditorState::default()
    };
    let ok = send(
        state,
        Inbound::Activate {
            serial,
            endpoint: Endpoint::Legacy,
            editor,
            config: Vec::new(),
        },
    )
    .is_ok()
        && send(state, Inbound::Done { serial }).is_ok();
    if !ok {
        report.check("Legacy 激活", false, "发送失败");
        return;
    }
    let out = collect_until(&state.link, STEP_TIMEOUT, |m| {
        matches!(m, Outbound::ModeState { .. })
    });
    let mode = out.iter().find_map(|m| match m {
        Outbound::ModeState {
            serial: s, mode, ..
        } if *s == serial => Some(*mode),
        _ => None,
    });
    report.check(
        "Legacy 激活默认英文直通",
        mode == Some(InputMode::Latin),
        format!("{mode:?}"),
    );
    // 壳切中文：应回 ModeState(Chinese)（外加一帧现状帧）。
    if send(
        state,
        Inbound::SetInputMode {
            serial,
            mode: InputMode::Chinese,
            cloud: CloudOverride::Unchanged,
        },
    )
    .is_err()
    {
        report.check("Legacy 切模式", false, "发送失败");
        return;
    }
    let out = collect_until(&state.link, STEP_TIMEOUT, |m| {
        matches!(m, Outbound::ModeState { .. })
    });
    let mode = out.iter().find_map(|m| match m {
        Outbound::ModeState {
            serial: s, mode, ..
        } if *s == serial => Some(*mode),
        _ => None,
    });
    report.check(
        "Legacy 切中文",
        mode == Some(InputMode::Chinese),
        format!("{mode:?}"),
    );
    // 打 nihao 上屏；Legacy 全程不该有 InlinePreedit。
    let keys = [49u32, 23, 35, 30, 24];
    let mut inline = 0usize;
    let mut committed = None;
    for (index, keycode) in keys.iter().enumerate() {
        let press_id = (index * 2 + 1) as u32;
        for message in key(report, state, serial, *keycode, press_id, press_id + 1) {
            if matches!(message, Outbound::InlinePreedit { .. }) {
                inline += 1;
            }
        }
    }
    let space = (keys.len() * 2 + 1) as u32;
    for message in key(report, state, serial, 57, space, space + 1) {
        match message {
            Outbound::InlinePreedit { .. } => inline += 1,
            Outbound::CommitText { serial: s, text } if s == serial => {
                committed = Some(text);
            }
            _ => {}
        }
    }
    report.check(
        "Legacy 上屏",
        committed.as_deref() == Some("你好"),
        format!("commit = {committed:?}"),
    );
    report.check(
        "Legacy 不发 InlinePreedit",
        inline == 0,
        format!("{inline} 条"),
    );
    let _ = send(state, Inbound::Deactivate { serial });
}

/// 等引擎断线重连：accept 新连接并握手。
fn expect_reconnect(report: &mut Report, listener: &Listener) -> Option<MockState> {
    match listener.accept_timeout(RECONNECT_TIMEOUT) {
        Ok(Some(link)) => {
            let mut state = MockState::new(link);
            expect_handshake(report, &mut state).then_some(state)
        }
        Ok(None) => {
            report.check("重连", false, "超时没等到新连接");
            None
        }
        Err(error) => {
            report.check("重连", false, error.to_string());
            None
        }
    }
}

/// 退出码走 `ExitCode` 而不是 `std::process::exit`：后者跳过局部变量的
/// Drop，会把拉起的引擎进程与 socket 文件留成孤儿。
fn main() -> std::process::ExitCode {
    let args = Args::parse();
    let socket = args
        .socket
        .clone()
        .unwrap_or_else(|| std::env::temp_dir().join("qingjian-mock-deniald/ime.sock"));
    if let Some(dir) = socket.parent() {
        std::fs::create_dir_all(dir).expect("建 socket 目录");
        // 与宿主策略一致：运行时目录 same-user only（0700），socket 0600 由 Listener::bind 设。
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
            .expect("设 socket 目录权限");
    }
    let listener = Listener::bind(&socket).expect("监听 socket");
    println!("mock 宿主监听 {}", socket.display());

    // 拉起引擎：隔离 XDG 目录、钉 US 布局保证键码→字符确定。
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let root = manifest.join("../..");
    let work = std::env::temp_dir().join("qingjian-mock-deniald");
    let _engine = args.spawn.as_ref().map(|bin| {
        let dict = args
            .dict
            .clone()
            .unwrap_or_else(|| root.join("assets/sample/dict.tsv"));
        let child = Command::new(bin)
            .arg("--socket")
            .arg(&socket)
            .arg("--dict")
            .arg(&dict)
            .arg("--data-dir")
            .arg(&root)
            .env("XDG_CONFIG_HOME", work.join("config"))
            .env("XDG_DATA_HOME", work.join("data"))
            .env("XDG_STATE_HOME", work.join("state"))
            .env("XDG_RUNTIME_DIR", work.join("run"))
            .env("XKB_DEFAULT_LAYOUT", "us")
            .env("RUST_LOG", "qingjian_linux=debug,info")
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("拉起引擎进程");
        println!("已拉起引擎 {}", bin.display());
        Engine(child)
    });

    let mut report = Report { failures: 0 };
    let link = listener.accept().expect("等引擎连接");
    let mut state = MockState::new(link);

    if expect_handshake(&mut report, &mut state) {
        session_round(&mut report, &mut state, 1);
        // 畸形包：引擎必须当协议错误关连接，随后退避重连。
        state
            .link
            .send(b"\xde\xad\xbe\xef not a packet")
            .expect("发畸形包");
        let mut buf = vec![0u8; PACKET_BUF];
        let _ = state.link.set_read_timeout(STEP_TIMEOUT);
        let closed = matches!(state.link.recv(&mut buf), Ok(0) | Err(_));
        report.check("畸形包后连接被关", closed, "");
        drop(state);
        if let Some(mut again) = expect_reconnect(&mut report, &listener) {
            // 反方向载荷（引擎 → 宿主类型从宿主方向来）：同样协议错误。
            let wrong_way = {
                let packet = qingjian_linux::ime::wire::encode_message(
                    &mut again.builder,
                    &Outbound::Status {
                        status: qingjian_linux::ime::message::EngineStatus::Ready,
                        error: None,
                    },
                    1,
                );
                packet.to_vec()
            };
            again.link.send(&wrong_way).expect("发反方向包");
            let closed = matches!(again.link.recv(&mut buf), Ok(0) | Err(_));
            report.check("反方向包后连接被关", closed, "");
            drop(again);
            // 第三次连接：跑一整轮确认服务还活着，再补 EditorUpdate
            // 分组与 Legacy 端点两轮回放。
            if let Some(mut third) = expect_reconnect(&mut report, &listener) {
                let _ = session_round(&mut report, &mut third, 1);
                grouping_round(&mut report, &mut third, 2);
                legacy_round(&mut report, &mut third, 10);
            }
        }
    }

    println!("——— 共 {} 项失败 ———", report.failures);
    if report.failures == 0 {
        std::process::ExitCode::SUCCESS
    } else {
        std::process::ExitCode::FAILURE
    }
}
