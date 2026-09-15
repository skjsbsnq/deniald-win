//! 入站包的结构校验：等价于 flatc 给每个表生成的 `Verifier` 调用，
//! 手写在 `flatbuffers` 运行时的 `Verifier` / `Verifiable` 上。
//!
//! 这里只管结构（偏移、vtable、字符串 NUL 结尾与 UTF-8、深度 / 表数上限）；
//! 字段语义（serial 非零、字符串长度、枚举范围、方向）在 [`super::decode`]。

use flatbuffers::{
    ForwardsUOffset, InvalidFlatbuffer, TableVerifier, Vector, Verifiable, Verifier,
};

use super::tag;

/// 结构校验的结果类型（`flatbuffers::verifier::Result`，该模块不公开）。
type Result<T> = std::result::Result<T, InvalidFlatbuffer>;

/// 字符串字段的存储类型。
type Str = ForwardsUOffset<&'static str>;

/// 子表字段的存储类型。
type Sub<T> = ForwardsUOffset<T>;

/// 表向量字段的存储类型。
type TableVec<T> = ForwardsUOffset<Vector<'static, ForwardsUOffset<T>>>;

/// 入站信封校验：magic 已在 [`super::decode`] 先核过，这里从根表开始走。
/// 返回根表在包里的字节位置。
pub(crate) fn verify_envelope(v: &mut Verifier) -> Result<usize> {
    let root = v.get_uoffset(0)? as usize;
    v.visit_table(root)?
        // schema 缺省就是 1：字段缺席合法，版本对不对由 decode 的语义校验判。
        .visit_field::<u16>("protocol_version", 4, false)?
        .visit_field::<u64>("sequence", 6, true)?
        .visit_union::<u8, _>("payload_type", 8, "payload", 10, true, verify_payload)?
        .finish();
    Ok(root)
}

/// union 判别值 → 对应表的校验。双向类型都列全：反方向的表在结构层合法，
/// 方向检查在 [`super::decode`]。
fn verify_payload(kind: u8, v: &mut Verifier, pos: usize) -> Result<()> {
    match kind {
        tag::HELLO => v.verify_union_variant::<Sub<VHello>>("ImeHello", pos),
        tag::ACTIVATE => v.verify_union_variant::<Sub<VActivate>>("ImeActivate", pos),
        tag::DEACTIVATE => v.verify_union_variant::<Sub<VDeactivate>>("ImeDeactivate", pos),
        tag::EDITOR_UPDATE => v.verify_union_variant::<Sub<VEditorUpdate>>("ImeEditorUpdate", pos),
        tag::DONE => v.verify_union_variant::<Sub<VDone>>("ImeDone", pos),
        tag::KEY_EVENT => v.verify_union_variant::<Sub<VKeyEvent>>("ImeKeyEvent", pos),
        tag::SELECT_CANDIDATE => {
            v.verify_union_variant::<Sub<VSelectCandidate>>("ImeSelectCandidate", pos)
        }
        tag::PAGE_CANDIDATES => {
            v.verify_union_variant::<Sub<VPageCandidates>>("ImePageCandidates", pos)
        }
        tag::SET_INPUT_MODE => v.verify_union_variant::<Sub<VSetInputMode>>("ImeSetInputMode", pos),
        tag::RELOAD_CONFIGURATION => {
            v.verify_union_variant::<Sub<VReloadConfiguration>>("ImeReloadConfiguration", pos)
        }
        tag::FRAME => v.verify_union_variant::<Sub<VFrame>>("ImeFrame", pos),
        tag::COMMIT_TEXT => v.verify_union_variant::<Sub<VCommitText>>("ImeCommitText", pos),
        tag::INLINE_PREEDIT => {
            v.verify_union_variant::<Sub<VInlinePreedit>>("ImeInlinePreedit", pos)
        }
        tag::DELETE_SURROUNDING => {
            v.verify_union_variant::<Sub<VDeleteSurrounding>>("ImeDeleteSurrounding", pos)
        }
        tag::MODE_STATE => v.verify_union_variant::<Sub<VModeState>>("ImeModeState", pos),
        tag::STATUS => v.verify_union_variant::<Sub<VStatus>>("ImeStatus", pos),
        tag::KEY_RESULT => v.verify_union_variant::<Sub<VKeyResult>>("ImeKeyResult", pos),
        _ => InvalidFlatbuffer::new_inconsistent_union("payload_type", "payload"),
    }
}

struct VHello;
struct VActivate;
struct VDeactivate;
struct VEditorUpdate;
struct VDone;
struct VKeyEvent;
struct VSelectCandidate;
struct VPageCandidates;
struct VSetInputMode;
struct VReloadConfiguration;
struct VFrame;
struct VCommitText;
struct VInlinePreedit;
struct VDeleteSurrounding;
struct VModeState;
struct VStatus;
struct VKeyResult;

struct VRect;
struct VConfigEntry;
struct VPreeditSpan;
struct VCandidate;

/// 编辑器状态公共字段（`ImeActivate` 与 `ImeEditorUpdate` 只差端点与配置）。
fn editor_fields<'v, 'o, 'b>(
    t: TableVerifier<'v, 'o, 'b>,
    base: u16,
) -> Result<TableVerifier<'v, 'o, 'b>> {
    t.visit_field::<Str>("app_id", base, false)?
        .visit_field::<u32>("content_hint", base + 2, false)?
        .visit_field::<u32>("content_purpose", base + 4, false)?
        .visit_field::<Sub<VRect>>("cursor_rectangle", base + 6, false)?
        .visit_field::<Str>("surrounding_text", base + 8, false)?
        .visit_field::<u32>("surrounding_cursor", base + 10, false)?
        .visit_field::<u32>("surrounding_anchor", base + 12, false)
}

impl Verifiable for VHello {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u16>("client_version", 4, false)?
            .visit_field::<Str>("name", 6, false)?
            .visit_field::<Str>("version", 8, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VActivate {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        editor_fields(
            v.visit_table(pos)?
                .visit_field::<u64>("serial", 4, true)?
                .visit_field::<u8>("endpoint", 6, false)?,
            8,
        )?
        .visit_field::<TableVec<VConfigEntry>>("config", 22, false)?
        .finish();
        Ok(())
    }
}

impl Verifiable for VDeactivate {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VEditorUpdate {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        editor_fields(
            v.visit_table(pos)?.visit_field::<u64>("serial", 4, true)?,
            6,
        )?
        .finish();
        Ok(())
    }
}

impl Verifiable for VDone {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VKeyEvent {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u32>("keycode", 6, false)?
            .visit_field::<u32>("modifiers", 8, false)?
            .visit_field::<bool>("pressed", 10, false)?
            .visit_field::<u32>("key_id", 12, true)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VSelectCandidate {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u32>("index", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VPageCandidates {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<i32>("delta", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VSetInputMode {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u8>("mode", 6, false)?
            .visit_field::<u8>("cloud", 8, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VReloadConfiguration {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<TableVec<VConfigEntry>>("config", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VFrame {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<TableVec<VPreeditSpan>>("preedit", 6, false)?
            .visit_field::<i32>("preedit_cursor", 8, false)?
            .visit_field::<TableVec<VCandidate>>("candidates", 10, false)?
            .visit_field::<i32>("highlighted", 12, false)?
            .visit_field::<u32>("page_index", 14, false)?
            .visit_field::<u32>("page_count", 16, false)?
            .visit_field::<Str>("completion", 18, false)?
            .visit_field::<Str>("notice", 20, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VCommitText {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<Str>("text", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VInlinePreedit {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<Str>("text", 6, false)?
            .visit_field::<i32>("cursor_begin", 8, false)?
            .visit_field::<i32>("cursor_end", 10, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VDeleteSurrounding {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u32>("before_bytes", 6, false)?
            .visit_field::<u32>("after_bytes", 8, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VModeState {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u8>("mode", 6, false)?
            .visit_field::<bool>("cloud_enabled", 8, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VStatus {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u8>("status", 4, false)?
            .visit_field::<Str>("error", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VKeyResult {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<u64>("serial", 4, true)?
            .visit_field::<u32>("key_id", 6, false)?
            .visit_field::<bool>("handled", 8, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VRect {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<i32>("x", 4, false)?
            .visit_field::<i32>("y", 6, false)?
            .visit_field::<i32>("width", 8, false)?
            .visit_field::<i32>("height", 10, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VConfigEntry {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<Str>("key", 4, false)?
            .visit_field::<Str>("value", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VPreeditSpan {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<Str>("text", 4, false)?
            .visit_field::<u8>("style", 6, false)?
            .finish();
        Ok(())
    }
}

impl Verifiable for VCandidate {
    fn run_verifier(v: &mut Verifier, pos: usize) -> Result<()> {
        v.visit_table(pos)?
            .visit_field::<Str>("text", 4, false)?
            .visit_field::<Str>("annotation", 6, false)?
            .visit_field::<bool>("from_cloud", 8, false)?
            .visit_field::<bool>("tone_mark", 10, false)?
            .finish();
        Ok(())
    }
}
