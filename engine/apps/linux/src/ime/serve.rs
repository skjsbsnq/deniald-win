//! 服务循环：连 `ime.sock` → `ImeHello` → 收包分派 / 空转节拍 → 断线退避重连。
//!
//! 宿主不可信：畸形包 / 截断包 / 方向错误都按协议错误处理——关掉连接、
//! 等一拍重连，让宿主看到一个干净的断线而不是僵住的引擎。

use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use flatbuffers::FlatBufferBuilder;

use super::link::{Link, PACKET_BUF};
use super::message::{EngineStatus, Outbound};
use super::wire;
use crate::session::Session;

/// 重连退避的起始 / 上限。
const BACKOFF_MIN: Duration = Duration::from_millis(200);
const BACKOFF_MAX: Duration = Duration::from_secs(5);

/// 连接要活过这个时长才算「稳定」：稳定过的连接断开后退避才重置；
/// accept 后立刻被丢（或协议不兼容秒断）的连接继续翻倍——否则会变成
/// 5 Hz 的「连接→Hello→断开→断连落盘 flush」永久扑腾。
const STABLE_AFTER: Duration = Duration::from_secs(1);

/// 宿主 socket 的规范路径：`$XDG_RUNTIME_DIR/denial/ime.sock`，
/// 缺省回落 `/run/user/<uid>/denial/ime.sock`。
pub fn socket_path() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|dir| dir.is_absolute())
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })))
        .join("denial/ime.sock")
}

/// 常驻服务：持会话状态与编码器，断线重连由它管。
pub struct Service {
    /// 输入会话。
    session: Session,

    /// 复用的 FlatBuffers 编码器（每包一次 reset）。
    builder: FlatBufferBuilder<'static>,

    /// 出站序号：从 1 起、每包递增。
    sequence: u64,

    /// 宿主 socket 路径。
    socket: PathBuf,
}

impl Service {
    pub fn new(session: Session, socket: PathBuf) -> Self {
        Self {
            session,
            builder: FlatBufferBuilder::new(),
            sequence: 0,
            socket,
        }
    }

    /// 永久服务：连接 → 对话 → 断了退避重连。
    pub fn run(&mut self) -> ! {
        let mut backoff = BACKOFF_MIN;
        loop {
            match Link::connect(&self.socket) {
                Ok(link) => {
                    let connected = Instant::now();
                    match self.converse(&link) {
                        Ok(()) => tracing::info!("宿主关闭了连接"),
                        Err(error) => tracing::warn!(%error, "连接中断"),
                    }
                    self.session.connection_lost();
                    // 只有稳定过的连接才把退避归零；秒断的保持翻倍。
                    if connected.elapsed() >= STABLE_AFTER {
                        backoff = BACKOFF_MIN;
                    }
                }
                Err(error) => {
                    tracing::debug!(
                        path = %self.socket.display(),
                        %error,
                        "连不上宿主 socket，退避重试"
                    );
                }
            }
            std::thread::sleep(backoff);
            backoff = (backoff * 2).min(BACKOFF_MAX);
        }
    }

    /// 一次连接的对话：先发 `ImeHello` 与就绪状态，然后收包分派 / 空转 tick。
    /// `Ok(())` 是对端正常关闭；协议错误与 IO 错误都往上传、由重连兜底。
    fn converse(&mut self, link: &Link) -> io::Result<()> {
        self.sequence = 1;
        self.send_all_guarded(
            link,
            [
                Outbound::Hello {
                    name: "qingjian".to_owned(),
                    version: env!("CARGO_PKG_VERSION").to_owned(),
                },
                Outbound::Status {
                    status: EngineStatus::Ready,
                    error: None,
                },
            ],
        )?;
        let mut buf = vec![0u8; PACKET_BUF];
        loop {
            link.set_read_timeout(self.session.next_tick())?;
            match link.recv(&mut buf) {
                Ok(0) => return Ok(()),
                Ok(len) if len > buf.len() => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!("包被截断：{len} 字节超过 {PACKET_BUF} 缓冲"),
                    ));
                }
                Ok(len) => match wire::decode_message(&buf[..len]) {
                    Ok(decoded) => {
                        let out = self.session.handle(decoded.inbound);
                        // 应答先行：周期落盘（fsync 级 IO）排在 send 之后，
                        // 不在「收键→应答」之间。
                        self.send_all_guarded(link, out)?;
                        self.session.flush_due();
                    }
                    Err(error) => {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            format!("协议错误：{error}"),
                        ));
                    }
                },
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    let out = self.session.tick();
                    self.send_all_guarded(link, out)?;
                    self.session.flush_due();
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => return Err(error),
            }
        }
    }

    /// `send_all` 的 panic 边界：编码 / 发送里 panic 按连接中断处理
    /// （由重连兜底），不让 unwind 出 `run` 杀死整个服务。
    fn send_all_guarded(
        &mut self,
        link: &Link,
        messages: impl IntoIterator<Item = Outbound>,
    ) -> io::Result<()> {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.send_all(link, messages)
        }))
        .unwrap_or_else(|_| {
            tracing::error!("出站编码 / 发送 panic，按连接中断处理");
            Err(io::Error::other("出站编码 panic"))
        })
    }

    /// 按序发一组出站载荷，各自带递增序号。
    fn send_all(
        &mut self,
        link: &Link,
        messages: impl IntoIterator<Item = Outbound>,
    ) -> io::Result<()> {
        for message in messages {
            let packet = wire::encode_message(&mut self.builder, &message, self.sequence);
            link.send(packet)?;
            self.sequence += 1;
        }
        Ok(())
    }
}
