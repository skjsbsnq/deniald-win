//! 线格式测试：双向编解码往返 + 畸形包逐项判错。

use flatbuffers::FlatBufferBuilder;

use super::super::message::{
    CandidateRow, CloudOverride, ConfigEntry, EditorState, Endpoint, EngineStatus, Frame, Inbound,
    InputMode, Outbound, PreeditSpan, PreeditStyle, Rect, Surrounding,
};
use super::{MAX_PACKET, decode_message, decode_outbound, encode_inbound, encode_message};
use crate::ime::wire::WireError;

fn inbound_packet(message: &Inbound) -> Vec<u8> {
    let mut builder = FlatBufferBuilder::new();
    encode_inbound(&mut builder, message, 1).to_vec()
}

fn outbound_packet(message: &Outbound) -> Vec<u8> {
    let mut builder = FlatBufferBuilder::new();
    encode_message(&mut builder, message, 1).to_vec()
}

fn roundtrip_inbound(message: Inbound) {
    let decoded = decode_message(&inbound_packet(&message)).unwrap();
    assert_eq!(decoded.inbound, message);
}

fn roundtrip_outbound(message: Outbound) {
    let decoded = decode_outbound(&outbound_packet(&message)).unwrap();
    assert_eq!(decoded.outbound, message);
}

fn editor() -> EditorState {
    EditorState {
        app_id: "org.test".to_owned(),
        content_hint: 3,
        content_purpose: 0,
        cursor_rectangle: Some(Rect {
            x: 1,
            y: 2,
            width: 3,
            height: 4,
        }),
        surrounding: Some(Surrounding {
            text: "前文后文".to_owned(),
            cursor: 6,
            anchor: 6,
        }),
    }
}

#[test]
fn inbound_roundtrip() {
    for message in [
        Inbound::Activate {
            serial: 1,
            endpoint: Endpoint::WaylandTextInput,
            editor: editor(),
            config: vec![
                ConfigEntry {
                    key: "page_size".to_owned(),
                    value: "7".to_owned(),
                },
                ConfigEntry {
                    key: "legacy_direct".to_owned(),
                    value: "off".to_owned(),
                },
            ],
        },
        Inbound::Activate {
            serial: 2,
            endpoint: Endpoint::Legacy,
            editor: EditorState::default(),
            config: Vec::new(),
        },
        Inbound::EditorUpdate {
            serial: 1,
            editor: editor(),
        },
        Inbound::Deactivate { serial: 1 },
        Inbound::Done { serial: 1 },
        Inbound::KeyEvent {
            serial: 1,
            keycode: 30,
            modifiers: 0b0101,
            pressed: true,
            key_id: 7,
        },
        Inbound::SelectCandidate {
            serial: 1,
            index: 3,
        },
        Inbound::PageCandidates {
            serial: 1,
            delta: -1,
        },
        Inbound::SetInputMode {
            serial: 1,
            mode: InputMode::Chinese,
            cloud: CloudOverride::Disable,
        },
        Inbound::ReloadConfiguration {
            serial: 1,
            config: vec![ConfigEntry {
                key: "k".to_owned(),
                value: "v".to_owned(),
            }],
        },
    ] {
        roundtrip_inbound(message);
    }
}

#[test]
fn outbound_roundtrip() {
    for message in [
        Outbound::Hello {
            name: "qingjian".to_owned(),
            version: "0.1.0-dev".to_owned(),
        },
        Outbound::KeyResult {
            serial: 1,
            key_id: 9,
            handled: true,
        },
        Outbound::CommitText {
            serial: 1,
            text: "你好".to_owned(),
        },
        Outbound::InlinePreedit {
            serial: 1,
            text: Some("ni'hao".to_owned()),
            cursor_begin: 2,
            cursor_end: 2,
        },
        Outbound::InlinePreedit {
            serial: 1,
            text: None,
            cursor_begin: -1,
            cursor_end: -1,
        },
        Outbound::DeleteSurrounding {
            serial: 1,
            before_bytes: 3,
            after_bytes: 0,
        },
        Outbound::ModeState {
            serial: 1,
            mode: InputMode::Chinese,
            cloud_enabled: true,
        },
        Outbound::Status {
            status: EngineStatus::Ready,
            error: None,
        },
        Outbound::Frame {
            serial: 1,
            frame: Frame {
                preedit: vec![
                    PreeditSpan {
                        text: "你".to_owned(),
                        style: PreeditStyle::Plain,
                    },
                    PreeditSpan {
                        text: "hao".to_owned(),
                        style: PreeditStyle::Underline,
                    },
                ],
                preedit_cursor: 3,
                candidates: vec![CandidateRow {
                    text: "你好".to_owned(),
                    annotation: "ni hao".to_owned(),
                    from_cloud: false,
                    tone_mark: true,
                }],
                highlighted: 0,
                page_index: 0,
                page_count: 1,
                completion: Some("你好吗".to_owned()),
                notice: None,
            },
        },
        Outbound::Frame {
            serial: 1,
            frame: Frame::default(),
        },
    ] {
        roundtrip_outbound(message);
    }
}

#[test]
fn malformed_packets() {
    // 太小 / 全零 / 乱码。
    assert!(matches!(decode_message(b""), Err(WireError::BadSize(0))));
    assert!(matches!(
        decode_message(&[0u8; 32]),
        Err(WireError::BadMagic)
    ));
    assert!(matches!(
        decode_message(b"\xde\xad\xbe\xef not a packet"),
        Err(WireError::BadMagic) | Err(WireError::BadSize(_))
    ));
    // 截断的包：合法前缀拦腰砍。
    let good = inbound_packet(&Inbound::Done { serial: 1 });
    let half = &good[..good.len() / 2];
    assert!(decode_message(half).is_err());
    // 引擎 → 宿主方向的载荷从入站口进来：方向错误。
    let wrong_way = outbound_packet(&Outbound::Status {
        status: EngineStatus::Ready,
        error: None,
    });
    assert!(matches!(
        decode_message(&wrong_way),
        Err(WireError::BadDirection(_))
    ));
    // 反方向同理。
    let wrong_way = inbound_packet(&Inbound::Done { serial: 1 });
    assert!(matches!(
        decode_outbound(&wrong_way),
        Err(WireError::BadDirection(_))
    ));
}

#[test]
fn semantic_bounds() {
    // serial 0 是「无激活」哨兵：编码器把 0 省成缺省字段，结构校验先拦下
    // （MissingRequiredField），就算真写出来语义校验也会拦。
    assert!(decode_message(&inbound_packet(&Inbound::Deactivate { serial: 0 })).is_err());
    // keycode 超 KEY_MAX。
    assert!(matches!(
        decode_message(&inbound_packet(&Inbound::KeyEvent {
            serial: 1,
            keycode: 768,
            modifiers: 0,
            pressed: true,
            key_id: 1,
        })),
        Err(WireError::OutOfBounds("key_event.keycode"))
    ));
    // 修饰掩码的保留位必须发零。
    assert!(matches!(
        decode_message(&inbound_packet(&Inbound::KeyEvent {
            serial: 1,
            keycode: 30,
            modifiers: 0x10,
            pressed: true,
            key_id: 1,
        })),
        Err(WireError::OutOfBounds("key_event.modifiers"))
    ));
    // key_id 从 1 起；0 省成缺省字段，结构层先拦。
    assert!(
        decode_message(&inbound_packet(&Inbound::KeyEvent {
            serial: 1,
            keycode: 30,
            modifiers: 0,
            pressed: true,
            key_id: 0,
        }))
        .is_err()
    );
    // Activate 不能带 None 端点。
    assert!(matches!(
        decode_message(&inbound_packet(&Inbound::Activate {
            serial: 1,
            endpoint: Endpoint::None,
            editor: EditorState::default(),
            config: Vec::new(),
        })),
        Err(WireError::OutOfBounds("activate.endpoint"))
    ));
    // surrounding 光标落在半个 UTF-8 字符里是错的。
    let mut editor = editor();
    editor.surrounding.as_mut().unwrap().cursor = 7;
    assert!(matches!(
        decode_message(&inbound_packet(&Inbound::EditorUpdate {
            serial: 1,
            editor,
        })),
        Err(WireError::OutOfBounds("surrounding_cursor"))
    ));
    // 帧不变量：page_count = 0 时不能有候选；highlighted 越界。
    for frame in [
        Frame {
            candidates: vec![CandidateRow {
                text: "x".to_owned(),
                annotation: String::new(),
                from_cloud: false,
                tone_mark: false,
            }],
            highlighted: 0,
            page_index: 0,
            page_count: 0,
            ..Frame::default()
        },
        Frame {
            candidates: vec![CandidateRow {
                text: "x".to_owned(),
                annotation: String::new(),
                from_cloud: false,
                tone_mark: false,
            }],
            highlighted: 5,
            page_index: 0,
            page_count: 1,
            ..Frame::default()
        },
        Frame {
            candidates: vec![CandidateRow {
                text: "x".to_owned(),
                annotation: String::new(),
                from_cloud: false,
                tone_mark: false,
            }],
            highlighted: 0,
            page_index: 1,
            page_count: 1,
            ..Frame::default()
        },
    ] {
        assert!(matches!(
            decode_outbound(&outbound_packet(&Outbound::Frame { serial: 1, frame })),
            Err(WireError::OutOfBounds(_))
        ));
    }
    // Error 状态合法（Offline=0 才会被拒；这里顺带验 Error 能过）。
    assert!(
        decode_outbound(&outbound_packet(&Outbound::Status {
            status: EngineStatus::Error,
            error: None,
        }))
        .is_ok()
    );
}

#[test]
fn interior_nul_in_string_rejected() {
    // 结构校验只保证 UTF-8 + 结尾 NUL；串内 NUL 由语义层拦。编一个合法
    // 包再把它app_id 内容里的一个字节改写成 NUL。
    let mut packet = inbound_packet(&Inbound::Activate {
        serial: 1,
        endpoint: Endpoint::WaylandTextInput,
        editor: EditorState {
            app_id: "nul-check".to_owned(),
            ..EditorState::default()
        },
        config: Vec::new(),
    });
    let pos = packet
        .windows(9)
        .position(|w| w == b"nul-check")
        .expect("app_id 内容应出现在包里");
    packet[pos] = 0;
    assert!(matches!(
        decode_message(&packet),
        Err(WireError::OutOfBounds("app_id"))
    ));
}

#[test]
fn packet_size_boundary() {
    // 上限是「超过 1 MiB」才拒：正好 1 MiB 的包照常解（seqpacket 一帧
    // 一整包，合法前缀后面的填充字节不参与校验）。
    let mut packet = inbound_packet(&Inbound::Done { serial: 1 });
    packet.resize(MAX_PACKET, 0);
    assert!(decode_message(&packet).is_ok());
    packet.push(0);
    assert!(matches!(
        decode_message(&packet),
        Err(WireError::BadSize(_))
    ));
}
