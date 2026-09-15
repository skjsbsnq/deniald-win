//! 入站包的解码：先 `Verifier` 结构校验，再按规范逐项做语义校验，最后读成
//! [`Inbound`]。对端同样不可信：任何一步不过都是 [`WireError`]，上层关掉连接。
//!
//! 读完结构校验后走 `Table::get` 是安全的：每个被读的字段都已经被对应
//! [`Verifiable`] 访问过。

use flatbuffers::{
    ForwardsUOffset, Table, Vector, Verifier, VerifierOptions, buffer_has_identifier,
};

use crate::ime::message::{
    CandidateRow, CloudOverride, ConfigEntry, EditorState, Endpoint, Frame, Inbound, InputMode,
    Outbound, PreeditSpan, PreeditStyle, Rect, Surrounding,
};

use super::encode::{
    MAGIC, MAX_CANDIDATES, MAX_PACKET, MAX_PREEDIT_SPANS, MAX_STRING, PROTOCOL_VERSION,
};
use super::{tag, verify};

/// surrounding_text 的规范上限（text-input-v3 界）。
const MAX_SURROUNDING: usize = 4000;

/// 配置快照条目数上限。
const MAX_CONFIG_ENTRIES: usize = 64;

/// 配置键 / 值上限。
const MAX_CONFIG_KEY: usize = 128;
const MAX_CONFIG_VALUE: usize = 1024;

/// evdev 键码上限（`KEY_MAX`）。
const MAX_KEYCODE: u32 = 767;

/// 修饰键掩码的已定义位：bit0 Shift / bit1 Ctrl / bit2 Alt / bit3 Super。
const KNOWN_MODIFIERS: u32 = 0x0F;

/// 一个解码好的入站包。
pub struct Decoded {
    /// 对端方向的序号（只做日志与丢包检测）。
    pub sequence: u64,

    /// 载荷。
    pub inbound: Inbound,
}

/// 一个解码好的出站（引擎 → 宿主）包：`mock_deniald` 开发工具与线格式测试用。
pub struct DecodedOut {
    /// 引擎方向的序号。
    pub sequence: u64,

    /// 载荷。
    pub outbound: Outbound,
}

/// 解码失败的原因；协议错误按规范关连接。
#[derive(Debug, thiserror::Error)]
pub enum WireError {
    /// 结构不合法（偏移越界、vtable 坏、字符串不是 UTF-8 / 缺 NUL 结尾等）。
    #[error("FlatBuffers 结构校验失败：{0}")]
    Structure(#[from] flatbuffers::InvalidFlatbuffer),

    /// 包超 1 MiB 上限或太小装不下信封。
    #[error("包大小越界：{0} 字节")]
    BadSize(usize),

    /// magic 不是 `IEMG`。
    #[error("magic 不匹配")]
    BadMagic,

    /// 信封协议版本不是 1。
    #[error("协议版本 {0} 不受支持")]
    BadVersion(u16),

    /// 收到了引擎 → 宿主方向的载荷类型。
    #[error("方向错误的载荷：tag {0}")]
    BadDirection(u8),

    /// 未知的 union 判别值。
    #[error("未知载荷：tag {0}")]
    UnknownPayload(u8),

    /// serial 为 0（0 是「无激活」哨兵）。
    #[error("serial 为 0")]
    BadSerial,

    /// 字段语义越界。
    #[error("字段越界：{0}")]
    OutOfBounds(&'static str),
}

/// 解码一个完整入站包。
pub(crate) fn decode(packet: &[u8]) -> Result<Decoded, WireError> {
    let (sequence, kind, payload) = envelope(packet)?;
    let inbound = parse_payload(kind, &payload)?;
    Ok(Decoded { sequence, inbound })
}

/// 解码一个完整出站包；收到宿主 → 引擎方向的类型判协议错误。
pub fn decode_outbound(packet: &[u8]) -> Result<DecodedOut, WireError> {
    let (sequence, kind, payload) = envelope(packet)?;
    let outbound = parse_outbound(kind, &payload)?;
    Ok(DecodedOut { sequence, outbound })
}

/// 信封部分：大小、magic、结构校验、版本，返回（序号, union 判别值, 载荷表）。
fn envelope(packet: &[u8]) -> Result<(u64, u8, Table<'_>), WireError> {
    if packet.len() > MAX_PACKET || packet.len() < 8 {
        return Err(WireError::BadSize(packet.len()));
    }
    if !buffer_has_identifier(packet, MAGIC, false) {
        return Err(WireError::BadMagic);
    }
    let options = VerifierOptions {
        max_depth: 8,
        max_tables: 512,
        max_apparent_size: MAX_PACKET,
        ignore_missing_null_terminator: false,
    };
    let mut verifier = Verifier::new(&options, packet);
    let root = verify::verify_envelope(&mut verifier)?;
    // 结构已过：下面的 Table::new / get 只读校验过的字段。
    let envelope = unsafe { Table::new(packet, root) };
    // schema `protocol_version:ushort = 1`：字段缺席按缺省值 1 读。
    let version = get::<u16>(&envelope, 4, PROTOCOL_VERSION);
    if version != PROTOCOL_VERSION {
        return Err(WireError::BadVersion(version));
    }
    let sequence = get::<u64>(&envelope, 6, 0);
    let kind = get::<u8>(&envelope, 8, 0);
    let Some(payload) = get_table(&envelope, 10) else {
        return Err(WireError::UnknownPayload(kind));
    };
    Ok((sequence, kind, payload))
}

fn parse_payload(kind: u8, t: &Table) -> Result<Inbound, WireError> {
    match kind {
        tag::ACTIVATE => {
            let serial = serial(t)?;
            let endpoint = endpoint(get::<u8>(t, 6, 0))?;
            if endpoint == Endpoint::None {
                return Err(WireError::OutOfBounds("activate.endpoint"));
            }
            let editor = editor_state(t, 8)?;
            let config = config_entries(t, 22)?;
            Ok(Inbound::Activate {
                serial,
                endpoint,
                editor,
                config,
            })
        }
        tag::DEACTIVATE => Ok(Inbound::Deactivate { serial: serial(t)? }),
        tag::EDITOR_UPDATE => Ok(Inbound::EditorUpdate {
            serial: serial(t)?,
            editor: editor_state(t, 6)?,
        }),
        tag::DONE => Ok(Inbound::Done { serial: serial(t)? }),
        tag::KEY_EVENT => {
            let keycode = get::<u32>(t, 6, 0);
            if keycode > MAX_KEYCODE {
                return Err(WireError::OutOfBounds("key_event.keycode"));
            }
            let modifiers = get::<u32>(t, 8, 0);
            if modifiers & !KNOWN_MODIFIERS != 0 {
                return Err(WireError::OutOfBounds("key_event.modifiers"));
            }
            let key_id = get::<u32>(t, 12, 0);
            if key_id == 0 {
                return Err(WireError::OutOfBounds("key_event.key_id"));
            }
            Ok(Inbound::KeyEvent {
                serial: serial(t)?,
                keycode,
                modifiers,
                pressed: get::<bool>(t, 10, false),
                key_id,
            })
        }
        tag::SELECT_CANDIDATE => Ok(Inbound::SelectCandidate {
            serial: serial(t)?,
            index: get::<u32>(t, 6, 0),
        }),
        tag::PAGE_CANDIDATES => Ok(Inbound::PageCandidates {
            serial: serial(t)?,
            delta: get::<i32>(t, 6, 0),
        }),
        tag::SET_INPUT_MODE => {
            let mode = match get::<u8>(t, 6, 0) {
                0 => InputMode::Latin,
                1 => InputMode::Chinese,
                _ => return Err(WireError::OutOfBounds("set_input_mode.mode")),
            };
            let cloud = match get::<u8>(t, 8, 0) {
                0 => CloudOverride::Unchanged,
                1 => CloudOverride::Enable,
                2 => CloudOverride::Disable,
                _ => return Err(WireError::OutOfBounds("set_input_mode.cloud")),
            };
            Ok(Inbound::SetInputMode {
                serial: serial(t)?,
                mode,
                cloud,
            })
        }
        tag::RELOAD_CONFIGURATION => Ok(Inbound::ReloadConfiguration {
            serial: serial(t)?,
            config: config_entries(t, 6)?,
        }),
        // 引擎 → 宿主方向的类型：出现在入站包里就是协议错误。
        tag::HELLO
        | tag::FRAME
        | tag::COMMIT_TEXT
        | tag::INLINE_PREEDIT
        | tag::DELETE_SURROUNDING
        | tag::MODE_STATE
        | tag::STATUS
        | tag::KEY_RESULT => Err(WireError::BadDirection(kind)),
        other => Err(WireError::UnknownPayload(other)),
    }
}

/// 引擎 → 宿主方向的载荷解析；宿主 → 引擎方向出现在这里是协议错误。
fn parse_outbound(kind: u8, t: &Table) -> Result<Outbound, WireError> {
    match kind {
        tag::HELLO => {
            let version = get::<u16>(t, 4, PROTOCOL_VERSION);
            if version != PROTOCOL_VERSION {
                return Err(WireError::BadVersion(version));
            }
            Ok(Outbound::Hello {
                name: bounded(get_str(t, 6).unwrap_or_default(), MAX_STRING, "hello.name")?
                    .to_owned(),
                version: bounded(
                    get_str(t, 8).unwrap_or_default(),
                    MAX_STRING,
                    "hello.version",
                )?
                .to_owned(),
            })
        }
        tag::KEY_RESULT => Ok(Outbound::KeyResult {
            serial: serial(t)?,
            key_id: get::<u32>(t, 6, 0),
            handled: get::<bool>(t, 8, false),
        }),
        tag::COMMIT_TEXT => Ok(Outbound::CommitText {
            serial: serial(t)?,
            text: bounded(get_str(t, 6).unwrap_or_default(), MAX_STRING, "commit.text")?.to_owned(),
        }),
        tag::INLINE_PREEDIT => {
            let text = get_str(t, 6)
                .map(|s| bounded(s, MAX_STRING, "inline_preedit.text").map(str::to_owned))
                .transpose()?;
            let cursor_begin = get::<i32>(t, 8, -1);
            let cursor_end = get::<i32>(t, 10, -1);
            check_cursor(
                cursor_begin,
                cursor_end,
                text.as_deref().unwrap_or_default(),
            )?;
            Ok(Outbound::InlinePreedit {
                serial: serial(t)?,
                text,
                cursor_begin,
                cursor_end,
            })
        }
        tag::DELETE_SURROUNDING => {
            let before = get::<u32>(t, 6, 0);
            let after = get::<u32>(t, 8, 0);
            if before as usize > MAX_SURROUNDING || after as usize > MAX_SURROUNDING {
                return Err(WireError::OutOfBounds("delete_surrounding"));
            }
            Ok(Outbound::DeleteSurrounding {
                serial: serial(t)?,
                before_bytes: before,
                after_bytes: after,
            })
        }
        tag::MODE_STATE => Ok(Outbound::ModeState {
            serial: serial(t)?,
            mode: match get::<u8>(t, 6, 0) {
                0 => InputMode::Latin,
                1 => InputMode::Chinese,
                _ => return Err(WireError::OutOfBounds("mode_state.mode")),
            },
            cloud_enabled: get::<bool>(t, 8, false),
        }),
        tag::STATUS => {
            let status = match get::<u8>(t, 4, 1) {
                // Offline 保留给宿主侧状态，引擎发出即协议错误。
                0 => return Err(WireError::OutOfBounds("status.offline")),
                1 => crate::ime::message::EngineStatus::Starting,
                2 => crate::ime::message::EngineStatus::Ready,
                3 => crate::ime::message::EngineStatus::Error,
                _ => return Err(WireError::OutOfBounds("status")),
            };
            let error = get_str(t, 6)
                .map(|s| bounded(s, MAX_STRING, "status.error").map(str::to_owned))
                .transpose()?;
            Ok(Outbound::Status { status, error })
        }
        tag::FRAME => frame(t),
        // 宿主 → 引擎方向的类型：出现在出站包里就是协议错误。
        tag::ACTIVATE
        | tag::DEACTIVATE
        | tag::EDITOR_UPDATE
        | tag::DONE
        | tag::KEY_EVENT
        | tag::SELECT_CANDIDATE
        | tag::PAGE_CANDIDATES
        | tag::SET_INPUT_MODE
        | tag::RELOAD_CONFIGURATION => Err(WireError::BadDirection(kind)),
        other => Err(WireError::UnknownPayload(other)),
    }
}

/// `ImeFrame` 的字段与跨字段不变量（规范「Frame semantics / Bounds」两节）。
fn frame(t: &Table) -> Result<Outbound, WireError> {
    let serial = serial(t)?;
    let preedit = match get_table_vec(t, 6) {
        Some(spans) => {
            if spans.len() > MAX_PREEDIT_SPANS {
                return Err(WireError::OutOfBounds("frame.preedit.len"));
            }
            spans
                .iter()
                .map(|span| {
                    let style = match get::<u8>(&span, 6, 0) {
                        0 => PreeditStyle::Plain,
                        1 => PreeditStyle::Underline,
                        2 => PreeditStyle::Highlight,
                        3 => PreeditStyle::Prediction,
                        _ => return Err(WireError::OutOfBounds("preedit.style")),
                    };
                    Ok(PreeditSpan {
                        text: bounded(
                            get_str(&span, 4).unwrap_or_default(),
                            MAX_STRING,
                            "preedit.text",
                        )?
                        .to_owned(),
                        style,
                    })
                })
                .collect::<Result<Vec<PreeditSpan>, WireError>>()?
        }
        None => Vec::new(),
    };
    let preedit_cursor = get::<i32>(t, 8, -1);
    // preedit_cursor 是拼接串里的字节偏移：-1 或落在码点边界内。
    if preedit_cursor < -1 {
        return Err(WireError::OutOfBounds("frame.preedit_cursor"));
    }
    if preedit_cursor >= 0 {
        let offset = preedit_cursor as usize;
        let text: String = preedit.iter().map(|span| span.text.as_str()).collect();
        if offset > text.len() || !text.is_char_boundary(offset) {
            return Err(WireError::OutOfBounds("frame.preedit_cursor"));
        }
    }
    let candidates = match get_table_vec(t, 10) {
        Some(rows) => {
            if rows.len() > MAX_CANDIDATES {
                return Err(WireError::OutOfBounds("frame.candidates.len"));
            }
            rows.iter()
                .map(|row| {
                    Ok(CandidateRow {
                        text: bounded(
                            get_str(&row, 4).unwrap_or_default(),
                            MAX_STRING,
                            "candidate.text",
                        )?
                        .to_owned(),
                        annotation: bounded(
                            get_str(&row, 6).unwrap_or_default(),
                            MAX_STRING,
                            "candidate.annotation",
                        )?
                        .to_owned(),
                        from_cloud: get::<bool>(&row, 8, false),
                        tone_mark: get::<bool>(&row, 10, false),
                    })
                })
                .collect::<Result<Vec<CandidateRow>, WireError>>()?
        }
        None => Vec::new(),
    };
    let highlighted = get::<i32>(t, 12, -1);
    let page_index = get::<u32>(t, 14, 0);
    let page_count = get::<u32>(t, 16, 0);
    if page_count == 0 {
        if page_index != 0 || !candidates.is_empty() || highlighted != -1 {
            return Err(WireError::OutOfBounds("frame.page_count"));
        }
    } else if page_index >= page_count {
        return Err(WireError::OutOfBounds("frame.page_index"));
    }
    if highlighted >= candidates.len() as i32 || highlighted < -1 {
        return Err(WireError::OutOfBounds("frame.highlighted"));
    }
    let completion = get_str(t, 18)
        .map(|s| bounded(s, MAX_STRING, "frame.completion").map(str::to_owned))
        .transpose()?;
    let notice = get_str(t, 20)
        .map(|s| bounded(s, MAX_STRING, "frame.notice").map(str::to_owned))
        .transpose()?;
    Ok(Outbound::Frame {
        serial,
        frame: Frame {
            preedit,
            preedit_cursor,
            candidates,
            highlighted,
            page_index,
            page_count,
            completion,
            notice,
        },
    })
}

/// `cursor_begin` / `cursor_end` / `preedit_cursor` 的不变量：都 -1 或都在文本
/// 长度的码点边界内，且 begin ≤ end。
fn check_cursor(begin: i32, end: i32, text: &str) -> Result<(), WireError> {
    if begin < -1 || end < -1 || begin > end {
        return Err(WireError::OutOfBounds("cursor"));
    }
    for offset in [begin, end] {
        if offset >= 0 && (offset as usize > text.len() || !text.is_char_boundary(offset as usize))
        {
            return Err(WireError::OutOfBounds("cursor"));
        }
    }
    Ok(())
}

/// 激活级载荷的 serial：必须非零。
fn serial(t: &Table) -> Result<u64, WireError> {
    let serial = get::<u64>(t, 4, 0);
    if serial == 0 {
        return Err(WireError::BadSerial);
    }
    Ok(serial)
}

fn endpoint(value: u8) -> Result<Endpoint, WireError> {
    match value {
        0 => Ok(Endpoint::None),
        1 => Ok(Endpoint::WaylandTextInput),
        2 => Ok(Endpoint::Flutter),
        3 => Ok(Endpoint::Legacy),
        _ => Err(WireError::OutOfBounds("endpoint")),
    }
}

/// `ImeActivate` / `ImeEditorUpdate` 的公共字段，`base` 是 `app_id` 的 voffset。
fn editor_state(t: &Table, base: u16) -> Result<EditorState, WireError> {
    let app_id = bounded(get_str(t, base).unwrap_or_default(), MAX_STRING, "app_id")?;
    let cursor_rectangle = get_table(t, base + 6).map(|r| Rect {
        x: get::<i32>(&r, 4, 0),
        y: get::<i32>(&r, 6, 0),
        width: get::<i32>(&r, 8, 0),
        height: get::<i32>(&r, 10, 0),
    });
    let surrounding = match get_str(t, base + 8) {
        Some(text) => {
            let text = bounded(text, MAX_SURROUNDING, "surrounding_text")?;
            let cursor = get::<u32>(t, base + 10, 0) as usize;
            let anchor = get::<u32>(t, base + 12, 0) as usize;
            for (offset, name) in [
                (cursor, "surrounding_cursor"),
                (anchor, "surrounding_anchor"),
            ] {
                if offset > text.len() || !text.is_char_boundary(offset) {
                    return Err(WireError::OutOfBounds(name));
                }
            }
            Some(Surrounding {
                text: text.to_owned(),
                cursor: cursor as u32,
                anchor: anchor as u32,
            })
        }
        None => None,
    };
    Ok(EditorState {
        app_id: app_id.to_owned(),
        content_hint: get::<u32>(t, base + 2, 0),
        content_purpose: get::<u32>(t, base + 4, 0),
        cursor_rectangle,
        surrounding,
    })
}

fn config_entries(t: &Table, offset: u16) -> Result<Vec<ConfigEntry>, WireError> {
    let Some(entries) = get_table_vec(t, offset) else {
        return Ok(Vec::new());
    };
    if entries.len() > MAX_CONFIG_ENTRIES {
        return Err(WireError::OutOfBounds("config.len"));
    }
    entries
        .iter()
        .map(|entry| {
            let key = bounded(
                get_str(&entry, 4).unwrap_or_default(),
                MAX_CONFIG_KEY,
                "config.key",
            )?;
            let value = bounded(
                get_str(&entry, 6).unwrap_or_default(),
                MAX_CONFIG_VALUE,
                "config.value",
            )?;
            Ok(ConfigEntry {
                key: key.to_owned(),
                value: value.to_owned(),
            })
        })
        .collect()
}

/// 字符串语义校验：长度上限 + 不含 NUL（结构层已保证 UTF-8 与结尾 NUL）。
fn bounded<'a>(text: &'a str, limit: usize, name: &'static str) -> Result<&'a str, WireError> {
    if text.len() > limit || text.contains('\0') {
        return Err(WireError::OutOfBounds(name));
    }
    Ok(text)
}

// 以下读函数全部要求结构校验已通过（`decode` 的顺序保证）。

fn get<'a, T>(t: &Table<'a>, offset: u16, default: T::Inner) -> T::Inner
where
    T: flatbuffers::Follow<'a> + 'a,
{
    unsafe { t.get::<T>(offset, None) }.unwrap_or(default)
}

fn get_str<'a>(t: &Table<'a>, offset: u16) -> Option<&'a str> {
    unsafe { t.get::<ForwardsUOffset<&str>>(offset, None) }
}

fn get_table<'a>(t: &Table<'a>, offset: u16) -> Option<Table<'a>> {
    unsafe { t.get::<ForwardsUOffset<Table>>(offset, None) }
}

fn get_table_vec<'a>(t: &Table<'a>, offset: u16) -> Option<Vector<'a, ForwardsUOffset<Table<'a>>>> {
    unsafe { t.get::<ForwardsUOffset<Vector<ForwardsUOffset<Table>>>>(offset, None) }
}
