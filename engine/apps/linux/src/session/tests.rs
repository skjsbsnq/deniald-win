//! 会话分派测试：不连 socket，直接喂 `Inbound` 看出站序列。
//! 覆盖激活分组、按键应答语义、serial 失配丢弃、Legacy 降级与上屏全链路。

use qingjian_core::Engine;
use qingjian_dictionary::Dictionary;

use super::{Session, SessionConfig};
use crate::ime::message::{EditorState, Endpoint, Inbound, InputMode, Outbound};

/// US 布局键码。
const N: u32 = 49;
const I: u32 = 23;
const H: u32 = 35;
const A: u32 = 30;
const O: u32 = 24;
const SPACE: u32 = 57;
const LEFT_CTRL: u32 = 29;
const C: u32 = 46;
const CAPS_LOCK: u32 = 58;

fn session() -> Session {
    let dict = concat!(env!("CARGO_MANIFEST_DIR"), "/../../assets/sample/dict.tsv");
    let engine = Engine::new(Dictionary::from_path(dict).unwrap());
    Session::new(engine, SessionConfig::default())
}

fn activate(session: &mut Session, serial: u64, endpoint: Endpoint) -> Vec<Outbound> {
    let mut out = session.handle(Inbound::Activate {
        serial,
        endpoint,
        editor: EditorState {
            app_id: "test.editor".to_owned(),
            ..EditorState::default()
        },
        config: Vec::new(),
    });
    // 组没关之前不应有任何出站。
    assert!(out.is_empty());
    out.extend(session.handle(Inbound::Done { serial }));
    out
}

fn press(session: &mut Session, serial: u64, keycode: u32, key_id: u32) -> Vec<Outbound> {
    session.handle(Inbound::KeyEvent {
        serial,
        keycode,
        modifiers: 0,
        pressed: true,
        key_id,
    })
}

/// 出站序列里的按键应答。
fn verdict(out: &[Outbound], key_id: u32) -> Option<bool> {
    out.iter().find_map(|m| match m {
        Outbound::KeyResult {
            key_id: k, handled, ..
        } if *k == key_id => Some(*handled),
        _ => None,
    })
}

fn commits(out: &[Outbound]) -> Vec<String> {
    out.iter()
        .filter_map(|m| match m {
            Outbound::CommitText { text, .. } => Some(text.clone()),
            _ => None,
        })
        .collect()
}

fn frames(out: &[Outbound]) -> usize {
    out.iter()
        .filter(|m| matches!(m, Outbound::Frame { .. }))
        .count()
}

#[test]
fn key_to_frame_to_commit() {
    let mut session = session();
    let out = activate(&mut session, 1, Endpoint::WaylandTextInput);
    assert!(
        matches!(out.as_slice(), [Outbound::ModeState { .. }]),
        "激活应回 ModeState：{out:?}"
    );
    for (index, keycode) in [N, I, H, A, O].iter().enumerate() {
        let out = press(&mut session, 1, *keycode, (index + 1) as u32);
        assert_eq!(verdict(&out, index as u32 + 1), Some(true), "字母应被消费");
        assert!(frames(&out) > 0, "组句中每键都该有帧");
        // 有能力的端点 + 默认 Both：行内 preedit 该下发。
        assert!(
            out.iter()
                .any(|m| matches!(m, Outbound::InlinePreedit { .. })),
            "缺行内 preedit：{out:?}"
        );
    }
    let out = press(&mut session, 1, SPACE, 6);
    assert_eq!(verdict(&out, 6), Some(true));
    assert_eq!(commits(&out), vec!["你好".to_owned()], "上屏文本");
    assert!(session.engine().composition().is_empty(), "上屏后组句清空");
}

#[test]
fn stale_serial_and_release() {
    let mut session = session();
    activate(&mut session, 1, Endpoint::WaylandTextInput);
    // 别的 serial 的按键整个丢，连应答都不发。
    let out = press(&mut session, 9, N, 1);
    assert!(out.is_empty());
    // 抬起放行。
    let out = session.handle(Inbound::KeyEvent {
        serial: 1,
        keycode: N,
        modifiers: 0,
        pressed: false,
        key_id: 2,
    });
    assert_eq!(verdict(&out, 2), Some(false));
    // 修饰键本体永远放行。
    let out = press(&mut session, 1, LEFT_CTRL, 3);
    assert_eq!(verdict(&out, 3), Some(false));
    // 组句中带 Ctrl 的键交还宿主（快捷键没配到的话）。
    press(&mut session, 1, N, 4);
    let out = session.handle(Inbound::KeyEvent {
        serial: 1,
        keycode: C,
        modifiers: 0b0010,
        pressed: true,
        key_id: 5,
    });
    assert_eq!(verdict(&out, 5), Some(false));
}

#[test]
fn deactivate_boundaries() {
    let mut session = session();
    activate(&mut session, 1, Endpoint::WaylandTextInput);
    press(&mut session, 1, N, 1);
    // 去激活自洽：吃组、清面板、不发任何载荷。
    let out = session.handle(Inbound::Deactivate { serial: 1 });
    assert!(out.is_empty());
    // 之后这个 serial 的按键全丢。
    assert!(press(&mut session, 1, N, 2).is_empty());
    // 新激活是新世代；旧 serial 的 Deactivate 也丢。
    activate(&mut session, 2, Endpoint::WaylandTextInput);
    assert!(session.handle(Inbound::Deactivate { serial: 1 }).is_empty());
    let out = press(&mut session, 2, N, 3);
    assert_eq!(verdict(&out, 3), Some(true));
}

#[test]
fn pending_group_is_atomic() {
    let mut session = session();
    // Activate 落地前编辑器状态不进 Engine；Done 错了 serial 整组丢。
    session.handle(Inbound::Activate {
        serial: 1,
        endpoint: Endpoint::WaylandTextInput,
        editor: EditorState::default(),
        config: Vec::new(),
    });
    session.handle(Inbound::EditorUpdate {
        serial: 1,
        editor: EditorState {
            app_id: "late.app".to_owned(),
            ..EditorState::default()
        },
    });
    // 组还没关：按键（serial 对不上当前激活，因为激活还没生效）丢掉。
    assert!(press(&mut session, 1, N, 1).is_empty());
    let out = session.handle(Inbound::Done { serial: 1 });
    assert!(matches!(out.as_slice(), [Outbound::ModeState { .. }]));
    let out = press(&mut session, 1, N, 2);
    assert_eq!(verdict(&out, 2), Some(true));
}

#[test]
fn legacy_endpoint_degrades() {
    let mut session = session();
    let out = activate(&mut session, 1, Endpoint::Legacy);
    // Legacy 直通策略：默认英文模式（ModeState 报 Latin）。
    assert!(matches!(
        out.as_slice(),
        [Outbound::ModeState {
            mode: InputMode::Latin,
            ..
        }]
    ));
    // 切成中文组句；切模式应回 ModeState + 一帧现状帧（不挂着旧模式的候选）。
    let out = session.handle(Inbound::SetInputMode {
        serial: 1,
        mode: InputMode::Chinese,
        cloud: crate::ime::message::CloudOverride::Unchanged,
    });
    assert!(
        matches!(
            out.as_slice(),
            [
                Outbound::ModeState {
                    mode: InputMode::Chinese,
                    ..
                },
                Outbound::Frame { .. }
            ]
        ),
        "切模式应回 ModeState + Frame：{out:?}"
    );
    let out = press(&mut session, 1, N, 1);
    assert_eq!(verdict(&out, 1), Some(true));
    assert!(frames(&out) > 0);
    // Legacy 端点永远不发 InlinePreedit。
    assert!(
        !out.iter()
            .any(|m| matches!(m, Outbound::InlinePreedit { .. })),
        "Legacy 不应发行内 preedit：{out:?}"
    );
}

#[test]
fn select_candidate_commits() {
    let mut session = session();
    activate(&mut session, 1, Endpoint::WaylandTextInput);
    press(&mut session, 1, N, 1);
    press(&mut session, 1, I, 2);
    // 点选最新帧第 0 个候选。
    let out = session.handle(Inbound::SelectCandidate {
        serial: 1,
        index: 0,
    });
    assert_eq!(commits(&out).len(), 1, "点选应上屏：{out:?}");
    // 下标越界的点选丢。
    press(&mut session, 1, N, 3);
    let out = session.handle(Inbound::SelectCandidate {
        serial: 1,
        index: 99,
    });
    assert!(out.is_empty());
}

#[test]
fn private_purposes_suppress_engine() {
    // text-input-v3 content_purpose：8 = password、9 = pin 进私密；
    // 7 = name 没有保密语义，不进。
    for (purpose, expected) in [(8u32, true), (9, true), (7, false), (0, false)] {
        let mut session = session();
        activate_editor(
            &mut session,
            1,
            EditorState {
                content_purpose: purpose,
                ..EditorState::default()
            },
        );
        assert_eq!(
            session.engine().is_private(),
            expected,
            "content_purpose {purpose}"
        );
    }
    // content_hint 的 sensitive_data 位（0x80）同样进私密。
    let mut session = session();
    activate_editor(
        &mut session,
        1,
        EditorState {
            content_hint: 0x80,
            ..EditorState::default()
        },
    );
    assert!(session.engine().is_private());
}

/// 带指定编辑器状态完成一次激活。
fn activate_editor(session: &mut Session, serial: u64, editor: EditorState) -> Vec<Outbound> {
    session.handle(Inbound::Activate {
        serial,
        endpoint: Endpoint::WaylandTextInput,
        editor,
        config: Vec::new(),
    });
    session.handle(Inbound::Done { serial })
}

#[test]
fn stale_serial_update_does_not_break_pending() {
    let mut session = session();
    session.handle(Inbound::Activate {
        serial: 5,
        endpoint: Endpoint::WaylandTextInput,
        editor: EditorState::default(),
        config: Vec::new(),
    });
    // pending Activate{5} 开着时来一条别的 serial 的 EditorUpdate：
    // 按规范整条丢，不能冲掉开着的组。
    session.handle(Inbound::EditorUpdate {
        serial: 7,
        editor: EditorState {
            app_id: "stale.app".to_owned(),
            ..EditorState::default()
        },
    });
    let out = session.handle(Inbound::Done { serial: 5 });
    assert!(
        matches!(out.as_slice(), [Outbound::ModeState { serial: 5, .. }]),
        "激活应照常落地：{out:?}"
    );
    let out = press(&mut session, 5, N, 1);
    assert_eq!(verdict(&out, 1), Some(true));
}

#[test]
fn done_and_deactivate_serial_mismatch() {
    let mut session = session();
    activate(&mut session, 1, Endpoint::WaylandTextInput);
    // 开下一个激活组；serial 不符的 Done 只丢自己，组还在。
    session.handle(Inbound::Activate {
        serial: 2,
        endpoint: Endpoint::WaylandTextInput,
        editor: EditorState::default(),
        config: Vec::new(),
    });
    assert!(session.handle(Inbound::Done { serial: 9 }).is_empty());
    let out = session.handle(Inbound::Done { serial: 2 });
    assert!(matches!(
        out.as_slice(),
        [Outbound::ModeState { serial: 2, .. }]
    ));
    // 暂存组被同 serial 的 Deactivate 吃掉时，存活激活不动。
    session.handle(Inbound::Activate {
        serial: 3,
        endpoint: Endpoint::WaylandTextInput,
        editor: EditorState::default(),
        config: Vec::new(),
    });
    assert!(session.handle(Inbound::Deactivate { serial: 3 }).is_empty());
    let out = press(&mut session, 2, N, 1);
    assert_eq!(verdict(&out, 1), Some(true), "serial 2 的激活应还活着");
    // 组已被吃掉：晚到的 Done 无对象。
    assert!(session.handle(Inbound::Done { serial: 3 }).is_empty());
    // 激活中的 EditorUpdate 成组、Done 落地生效（无回包）。
    session.handle(Inbound::EditorUpdate {
        serial: 2,
        editor: EditorState {
            app_id: "moved.app".to_owned(),
            ..EditorState::default()
        },
    });
    assert!(session.handle(Inbound::Done { serial: 2 }).is_empty());
    let out = press(&mut session, 2, N, 2);
    assert_eq!(verdict(&out, 2), Some(true));
}

#[test]
fn caps_state_resets_across_activations() {
    let mut session = session();
    activate(&mut session, 1, Endpoint::WaylandTextInput);
    // Caps 按下：放行 + ModeState 报 Latin。
    let out = press(&mut session, 1, CAPS_LOCK, 1);
    assert_eq!(verdict(&out, 1), Some(false));
    assert!(out.iter().any(|m| matches!(
        m,
        Outbound::ModeState {
            mode: InputMode::Latin,
            ..
        }
    )));
    session.handle(Inbound::Deactivate { serial: 1 });
    // 锁键只在激活期内被转发：新激活回到已知基线，ModeState 报 Chinese。
    let out = activate(&mut session, 2, Endpoint::WaylandTextInput);
    assert!(
        matches!(
            out.as_slice(),
            [Outbound::ModeState {
                mode: InputMode::Chinese,
                ..
            }]
        ),
        "Caps 观察态不应跨激活留：{out:?}"
    );
}

#[test]
fn legacy_passthrough_does_not_leak() {
    let mut session = session();
    // Legacy 端点默认英文直通。
    let out = activate(&mut session, 1, Endpoint::Legacy);
    assert!(matches!(
        out.as_slice(),
        [Outbound::ModeState {
            mode: InputMode::Latin,
            ..
        }]
    ));
    session.handle(Inbound::Deactivate { serial: 1 });
    // 下一个普通端点激活不继承直通。
    let out = activate(&mut session, 2, Endpoint::WaylandTextInput);
    assert!(
        matches!(
            out.as_slice(),
            [Outbound::ModeState {
                mode: InputMode::Chinese,
                ..
            }]
        ),
        "Legacy 直通不应漏进下一激活：{out:?}"
    );
}
