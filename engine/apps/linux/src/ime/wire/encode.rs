//! 出站载荷的 FlatBuffers 编码：手写在 `flatbuffers` 运行时的 builder 上，
//! 字段编号即 `ime.fbs` 里的声明顺序（voffset = 4 + 2 * 序号）。
//!
//! 编码侧同样守规范上限：字符串超界在字符边界上截断，超长了就丢掉，
//! 不让引擎把违规帧发出去。

use flatbuffers::{FlatBufferBuilder, ForwardsUOffset, UnionWIPOffset, WIPOffset};

use crate::ime::message::{
    CandidateRow, CloudOverride, ConfigEntry, EditorState, Endpoint, EngineStatus, Frame, Inbound,
    InputMode, Outbound, PreeditSpan, PreeditStyle, Rect,
};

/// 协议版本（`ImeEnvelope.protocol_version` 与 `ImeHello.client_version`）。
pub(crate) const PROTOCOL_VERSION: u16 = 1;

/// 包级上限：一个包 ≤ 1 MiB。
pub(crate) const MAX_PACKET: usize = 1 << 20;

/// 字符串字段上限（字节）。
pub(crate) const MAX_STRING: usize = 4096;

/// 每帧候选条数上限。
pub(crate) const MAX_CANDIDATES: usize = 64;

/// 每帧 preedit 段数上限。
pub(crate) const MAX_PREEDIT_SPANS: usize = 64;

/// 包体 magic（`file_identifier`）。
pub(crate) const MAGIC: &str = "IEMG";

// `ImeEnvelope` 各字段的 voffset。
const V_PROTOCOL_VERSION: u16 = 4;
const V_SEQUENCE: u16 = 6;
const V_PAYLOAD_TYPE: u16 = 8;
const V_PAYLOAD: u16 = 10;

// union 成员标签：按 `ime.fbs` 的声明顺序，1 起。
pub(crate) mod tag {
    pub(crate) const HELLO: u8 = 1;
    pub(crate) const ACTIVATE: u8 = 2;
    pub(crate) const DEACTIVATE: u8 = 3;
    pub(crate) const EDITOR_UPDATE: u8 = 4;
    pub(crate) const DONE: u8 = 5;
    pub(crate) const KEY_EVENT: u8 = 6;
    pub(crate) const SELECT_CANDIDATE: u8 = 7;
    pub(crate) const PAGE_CANDIDATES: u8 = 8;
    pub(crate) const SET_INPUT_MODE: u8 = 9;
    pub(crate) const RELOAD_CONFIGURATION: u8 = 10;
    pub(crate) const FRAME: u8 = 11;
    pub(crate) const COMMIT_TEXT: u8 = 12;
    pub(crate) const INLINE_PREEDIT: u8 = 13;
    pub(crate) const DELETE_SURROUNDING: u8 = 14;
    pub(crate) const MODE_STATE: u8 = 15;
    pub(crate) const STATUS: u8 = 16;
    pub(crate) const KEY_RESULT: u8 = 17;
}

type Table<'b> = WIPOffset<flatbuffers::TableFinishedWIPOffset>;
type Union<'b> = WIPOffset<UnionWIPOffset>;
type Offsets<'b> = Vec<Table<'b>>;

/// 编码一条出站消息为一个完整包（含 magic 与信封）。
pub(crate) fn encode<'a>(
    builder: &'a mut FlatBufferBuilder,
    message: &Outbound,
    sequence: u64,
) -> &'a [u8] {
    builder.reset();
    let (tag, payload) = build_payload(builder, message);
    let envelope = {
        let t = builder.start_table();
        // 协议版本总是显式写，不省成缺省字段。
        builder.push_slot_always::<u16>(V_PROTOCOL_VERSION, PROTOCOL_VERSION);
        builder.push_slot::<u64>(V_SEQUENCE, sequence, 0);
        builder.push_slot::<u8>(V_PAYLOAD_TYPE, tag, 0);
        builder.push_slot_always::<Union>(V_PAYLOAD, payload);
        builder.end_table(t)
    };
    builder.finish(envelope, Some(MAGIC));
    builder.finished_data()
}

fn build_payload<'b>(b: &mut FlatBufferBuilder<'b>, message: &Outbound) -> (u8, Union<'b>) {
    match message {
        Outbound::Hello { name, version } => {
            let name = bounded(b, name);
            let version = bounded(b, version);
            let t = b.start_table();
            b.push_slot_always::<u16>(4, PROTOCOL_VERSION);
            if let Some(s) = name {
                b.push_slot_always::<WIPOffset<_>>(6, s);
            }
            if let Some(s) = version {
                b.push_slot_always::<WIPOffset<_>>(8, s);
            }
            (tag::HELLO, b.end_table(t).as_union_value())
        }
        Outbound::KeyResult {
            serial,
            key_id,
            handled,
        } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u32>(6, *key_id, 0);
            b.push_slot::<bool>(8, *handled, false);
            (tag::KEY_RESULT, b.end_table(t).as_union_value())
        }
        Outbound::CommitText { serial, text } => {
            let text = bounded(b, text);
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            if let Some(s) = text {
                b.push_slot_always::<WIPOffset<_>>(6, s);
            }
            (tag::COMMIT_TEXT, b.end_table(t).as_union_value())
        }
        Outbound::InlinePreedit {
            serial,
            text,
            cursor_begin,
            cursor_end,
        } => {
            let text = text.as_deref().and_then(|s| bounded(b, s));
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            if let Some(s) = text {
                b.push_slot_always::<WIPOffset<_>>(6, s);
            }
            b.push_slot::<i32>(8, *cursor_begin, -1);
            b.push_slot::<i32>(10, *cursor_end, -1);
            (tag::INLINE_PREEDIT, b.end_table(t).as_union_value())
        }
        Outbound::DeleteSurrounding {
            serial,
            before_bytes,
            after_bytes,
        } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u32>(6, *before_bytes, 0);
            b.push_slot::<u32>(8, *after_bytes, 0);
            (tag::DELETE_SURROUNDING, b.end_table(t).as_union_value())
        }
        Outbound::ModeState {
            serial,
            mode,
            cloud_enabled,
        } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u8>(6, input_mode(*mode), 0);
            b.push_slot::<bool>(8, *cloud_enabled, false);
            (tag::MODE_STATE, b.end_table(t).as_union_value())
        }
        Outbound::Status { status, error } => {
            let error = error.as_deref().and_then(|s| bounded(b, s));
            let t = b.start_table();
            b.push_slot::<u8>(4, engine_status(*status), 1);
            if let Some(s) = error {
                b.push_slot_always::<WIPOffset<_>>(6, s);
            }
            (tag::STATUS, b.end_table(t).as_union_value())
        }
        Outbound::Frame { serial, frame } => (tag::FRAME, build_frame(b, *serial, frame)),
    }
}

fn build_frame<'b>(b: &mut FlatBufferBuilder<'b>, serial: u64, frame: &Frame) -> Union<'b> {
    let spans: Offsets = frame
        .preedit
        .iter()
        .take(MAX_PREEDIT_SPANS)
        .map(|span| preedit_span(b, span))
        .collect();
    let preedit = (!spans.is_empty()).then(|| b.create_vector(&spans));
    let rows: Offsets = frame
        .candidates
        .iter()
        .take(MAX_CANDIDATES)
        .map(|row| candidate_row(b, row))
        .collect();
    let candidates = (!rows.is_empty()).then(|| b.create_vector(&rows));
    let completion = frame.completion.as_deref().and_then(|s| bounded(b, s));
    let notice = frame.notice.as_deref().and_then(|s| bounded(b, s));
    let t = b.start_table();
    b.push_slot::<u64>(4, serial, 0);
    if let Some(v) = preedit {
        b.push_slot_always::<WIPOffset<_>>(6, v);
    }
    b.push_slot::<i32>(8, frame.preedit_cursor, -1);
    if let Some(v) = candidates {
        b.push_slot_always::<WIPOffset<_>>(10, v);
    }
    b.push_slot::<i32>(12, frame.highlighted, -1);
    b.push_slot::<u32>(14, frame.page_index, 0);
    b.push_slot::<u32>(16, frame.page_count, 0);
    if let Some(s) = completion {
        b.push_slot_always::<WIPOffset<_>>(18, s);
    }
    if let Some(s) = notice {
        b.push_slot_always::<WIPOffset<_>>(20, s);
    }
    b.end_table(t).as_union_value()
}

fn preedit_span<'b>(b: &mut FlatBufferBuilder<'b>, span: &PreeditSpan) -> Table<'b> {
    let text = bounded(b, &span.text);
    let t = b.start_table();
    if let Some(s) = text {
        b.push_slot_always::<WIPOffset<_>>(4, s);
    }
    b.push_slot::<u8>(6, preedit_style(span.style), 0);
    b.end_table(t)
}

fn candidate_row<'b>(b: &mut FlatBufferBuilder<'b>, row: &CandidateRow) -> Table<'b> {
    let text = bounded(b, &row.text);
    let annotation = bounded(b, &row.annotation);
    let t = b.start_table();
    if let Some(s) = text {
        b.push_slot_always::<WIPOffset<_>>(4, s);
    }
    if let Some(s) = annotation {
        b.push_slot_always::<WIPOffset<_>>(6, s);
    }
    b.push_slot::<bool>(8, row.from_cloud, false);
    b.push_slot::<bool>(10, row.tone_mark, false);
    b.end_table(t)
}

/// 建一个字符串值：按规范上限截断（字符边界、不含 NUL）；空串省略字段。
fn bounded<'b>(b: &mut FlatBufferBuilder<'b>, text: &str) -> Option<WIPOffset<&'b str>> {
    let text = crate::ime::wire::bounded_str(text);
    if text.is_empty() {
        return None;
    }
    Some(b.create_string(text))
}

fn input_mode(mode: InputMode) -> u8 {
    match mode {
        InputMode::Latin => 0,
        InputMode::Chinese => 1,
    }
}

/// 编码一条宿主 → 引擎方向的包：给 `mock_deniald` 开发工具与线格式测试用，
/// 服务进程自己不调它。
pub fn encode_inbound<'a>(
    builder: &'a mut FlatBufferBuilder,
    message: &Inbound,
    sequence: u64,
) -> &'a [u8] {
    builder.reset();
    let (tag, payload) = build_inbound(builder, message);
    let envelope = {
        let t = builder.start_table();
        builder.push_slot_always::<u16>(V_PROTOCOL_VERSION, PROTOCOL_VERSION);
        builder.push_slot::<u64>(V_SEQUENCE, sequence, 0);
        builder.push_slot::<u8>(V_PAYLOAD_TYPE, tag, 0);
        builder.push_slot_always::<Union>(V_PAYLOAD, payload);
        builder.end_table(t)
    };
    builder.finish(envelope, Some(MAGIC));
    builder.finished_data()
}

fn build_inbound<'b>(b: &mut FlatBufferBuilder<'b>, message: &Inbound) -> (u8, Union<'b>) {
    match message {
        Inbound::Activate {
            serial,
            endpoint,
            editor,
            config,
        } => {
            let payload = {
                let rect = editor.cursor_rectangle.map(|rect| build_rect(b, rect));
                let surrounding = editor
                    .surrounding
                    .as_ref()
                    .and_then(|s| bounded(b, &s.text));
                let app_id = bounded(b, &editor.app_id);
                let entries = config_entries(b, config);
                let t = b.start_table();
                b.push_slot::<u64>(4, *serial, 0);
                b.push_slot::<u8>(6, endpoint_kind(*endpoint), 0);
                if let Some(s) = app_id {
                    b.push_slot_always::<WIPOffset<_>>(8, s);
                }
                b.push_slot::<u32>(10, editor.content_hint, 0);
                b.push_slot::<u32>(12, editor.content_purpose, 0);
                if let Some(r) = rect {
                    b.push_slot_always::<WIPOffset<_>>(14, r);
                }
                if let Some(s) = surrounding {
                    b.push_slot_always::<WIPOffset<_>>(16, s);
                    let cursor = editor.surrounding.as_ref().map(|s| s.cursor).unwrap_or(0);
                    let anchor = editor.surrounding.as_ref().map(|s| s.anchor).unwrap_or(0);
                    b.push_slot::<u32>(18, cursor, 0);
                    b.push_slot::<u32>(20, anchor, 0);
                }
                if let Some(v) = entries {
                    b.push_slot_always::<WIPOffset<_>>(22, v);
                }
                b.end_table(t)
            };
            (tag::ACTIVATE, payload.as_union_value())
        }
        Inbound::EditorUpdate { serial, editor } => {
            let payload = build_editor_update(b, *serial, editor);
            (tag::EDITOR_UPDATE, payload.as_union_value())
        }
        Inbound::Deactivate { serial } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            (tag::DEACTIVATE, b.end_table(t).as_union_value())
        }
        Inbound::Done { serial } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            (tag::DONE, b.end_table(t).as_union_value())
        }
        Inbound::KeyEvent {
            serial,
            keycode,
            modifiers,
            pressed,
            key_id,
        } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u32>(6, *keycode, 0);
            b.push_slot::<u32>(8, *modifiers, 0);
            b.push_slot::<bool>(10, *pressed, false);
            b.push_slot::<u32>(12, *key_id, 0);
            (tag::KEY_EVENT, b.end_table(t).as_union_value())
        }
        Inbound::SelectCandidate { serial, index } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u32>(6, *index, 0);
            (tag::SELECT_CANDIDATE, b.end_table(t).as_union_value())
        }
        Inbound::PageCandidates { serial, delta } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<i32>(6, *delta, 0);
            (tag::PAGE_CANDIDATES, b.end_table(t).as_union_value())
        }
        Inbound::SetInputMode {
            serial,
            mode,
            cloud,
        } => {
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            b.push_slot::<u8>(6, input_mode(*mode), 0);
            b.push_slot::<u8>(8, cloud_override(*cloud), 0);
            (tag::SET_INPUT_MODE, b.end_table(t).as_union_value())
        }
        Inbound::ReloadConfiguration { serial, config } => {
            let entries = config_entries(b, config);
            let t = b.start_table();
            b.push_slot::<u64>(4, *serial, 0);
            if let Some(v) = entries {
                b.push_slot_always::<WIPOffset<_>>(6, v);
            }
            (tag::RELOAD_CONFIGURATION, b.end_table(t).as_union_value())
        }
    }
}

fn build_editor_update<'b>(
    b: &mut FlatBufferBuilder<'b>,
    serial: u64,
    editor: &EditorState,
) -> WIPOffset<flatbuffers::TableFinishedWIPOffset> {
    let rect = editor.cursor_rectangle.map(|rect| build_rect(b, rect));
    let surrounding_text = editor
        .surrounding
        .as_ref()
        .and_then(|s| bounded(b, &s.text));
    let app_id = bounded(b, &editor.app_id);
    let t = b.start_table();
    b.push_slot::<u64>(4, serial, 0);
    if let Some(s) = app_id {
        b.push_slot_always::<WIPOffset<_>>(6, s);
    }
    b.push_slot::<u32>(8, editor.content_hint, 0);
    b.push_slot::<u32>(10, editor.content_purpose, 0);
    if let Some(r) = rect {
        b.push_slot_always::<WIPOffset<_>>(12, r);
    }
    if let Some(s) = surrounding_text {
        b.push_slot_always::<WIPOffset<_>>(14, s);
        let (cursor, anchor) = editor
            .surrounding
            .as_ref()
            .map(|s| (s.cursor, s.anchor))
            .unwrap_or((0, 0));
        b.push_slot::<u32>(16, cursor, 0);
        b.push_slot::<u32>(18, anchor, 0);
    }
    b.end_table(t)
}

fn build_rect<'b>(b: &mut FlatBufferBuilder<'b>, rect: Rect) -> Table<'b> {
    let t = b.start_table();
    b.push_slot::<i32>(4, rect.x, 0);
    b.push_slot::<i32>(6, rect.y, 0);
    b.push_slot::<i32>(8, rect.width, 0);
    b.push_slot::<i32>(10, rect.height, 0);
    b.end_table(t)
}

fn config_entries<'b>(
    b: &mut FlatBufferBuilder<'b>,
    entries: &[ConfigEntry],
) -> Option<WIPOffset<flatbuffers::Vector<'b, ForwardsUOffset<flatbuffers::TableFinishedWIPOffset>>>>
{
    if entries.is_empty() {
        return None;
    }
    let offsets: Vec<Table> = entries
        .iter()
        .map(|entry| {
            let key = bounded(b, &entry.key);
            let value = bounded(b, &entry.value);
            let t = b.start_table();
            if let Some(s) = key {
                b.push_slot_always::<WIPOffset<_>>(4, s);
            }
            if let Some(s) = value {
                b.push_slot_always::<WIPOffset<_>>(6, s);
            }
            b.end_table(t)
        })
        .collect();
    Some(b.create_vector(&offsets))
}

fn endpoint_kind(endpoint: Endpoint) -> u8 {
    match endpoint {
        Endpoint::None => 0,
        Endpoint::WaylandTextInput => 1,
        Endpoint::Flutter => 2,
        Endpoint::Legacy => 3,
    }
}

fn cloud_override(cloud: CloudOverride) -> u8 {
    match cloud {
        CloudOverride::Unchanged => 0,
        CloudOverride::Enable => 1,
        CloudOverride::Disable => 2,
    }
}

fn engine_status(status: EngineStatus) -> u8 {
    match status {
        EngineStatus::Starting => 1,
        EngineStatus::Ready => 2,
        EngineStatus::Error => 3,
    }
}

fn preedit_style(style: PreeditStyle) -> u8 {
    match style {
        PreeditStyle::Plain => 0,
        PreeditStyle::Underline => 1,
        PreeditStyle::Highlight => 2,
        PreeditStyle::Prediction => 3,
    }
}
