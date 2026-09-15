//! 线上载荷的自有类型：编解码落在 [`crate::ime::wire`]，这里只放语义。
//!
//! 类型与 `ime.fbs` 一一对应，字段语义见那份 schema 与协议规范文档。

/// 端点能力（`ImeEndpointKind`）。`Legacy` 无 surrounding、无光标矩形、
/// 不能 delete-surrounding，preedit 只在候选面板里。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Endpoint {
    /// 无焦点端点；激活里不会出现，只为与宿主状态枚举同编号。
    #[default]
    None,

    /// Wayland text-input-v3。
    WaylandTextInput,

    /// 壳内嵌编辑器（Flutter 文本通道）。
    Flutter,

    /// 合成键路径到达的旧客户端（X11 / 无 text-input）。
    Legacy,
}

impl Endpoint {
    /// 端点支持行内 preedit 与 delete-surrounding。
    pub fn capable(self) -> bool {
        matches!(self, Self::WaylandTextInput | Self::Flutter)
    }
}

/// 粗粒度输入模式（`ImeInputMode`）：Latin 原样直通，Chinese 组句。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputMode {
    /// 原样直通。
    #[default]
    Latin,

    /// 组句输入。
    Chinese,
}

/// `ImeSetInputMode.cloud` 的三态覆盖。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CloudOverride {
    /// 不动引擎自己的开关。
    #[default]
    Unchanged,

    /// 强制开。
    Enable,

    /// 强制关。
    Disable,
}

/// 引擎生命周期（`ImeEngineStatus`）；`Offline` 保留给宿主，引擎不发。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineStatus {
    /// 装配中。
    Starting,

    /// 就绪。
    Ready,

    /// 出错（附带诊断串）。
    Error,
}

/// 面板 preedit 分段的显示提示（`ImePreeditStyle`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PreeditStyle {
    /// 普通。
    #[default]
    Plain,

    /// 敲的拼音段（画下划线）。
    Underline,

    /// 强调（纠错改掉的原字母等）。
    Highlight,

    /// 联想预览段。
    Prediction,
}

/// 逻辑像素的光标矩形（`ImeRect`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Rect {
    /// 左上 x。
    pub x: i32,

    /// 左上 y。
    pub y: i32,

    /// 宽。
    pub width: i32,

    /// 高。
    pub height: i32,
}

/// 一条配置键值（`ImeConfigEntry`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigEntry {
    /// 键。
    pub key: String,

    /// 值。
    pub value: String,
}

/// 激活 / 更新里共用的可变编辑器状态：`ImeActivate` 与 `ImeEditorUpdate`
/// 只差 `endpoint` 与 `config`，其余字段同形。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EditorState {
    /// 焦点客户端的 app-id，未知为空。
    pub app_id: String,

    /// text-input-v3 content_hint，原样透传。
    pub content_hint: u32,

    /// text-input-v3 content_purpose，原样透传。
    pub content_purpose: u32,

    /// 光标矩形；`None` 表示端点不报。
    pub cursor_rectangle: Option<Rect>,

    /// 光标附近文本与光标 / 锚点字节偏移；`None` 表示端点不提供。
    pub surrounding: Option<Surrounding>,
}

/// `surrounding_text` 三元组：文本 + 光标 / 锚点（UTF-8 字节偏移）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Surrounding {
    /// 光标附近文本（≤ 4000 字节）。
    pub text: String,

    /// 光标偏移。
    pub cursor: u32,

    /// 锚点偏移。
    pub anchor: u32,
}

/// 面板的一行候选（`ImeCandidate`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CandidateRow {
    /// 候选文本。
    pub text: String,

    /// 右侧注解（译文等），可空。
    pub annotation: String,

    /// 云来源徽标。
    pub from_cloud: bool,

    /// 声调徽标。
    pub tone_mark: bool,
}

/// 面板 preedit 的一段（`ImePreeditSpan`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreeditSpan {
    /// 文本。
    pub text: String,

    /// 显示提示。
    pub style: PreeditStyle,
}

/// 激活级面板快照（`ImeFrame`）：此刻屏幕该是什么样，不是增量。
/// 全空帧收起候选面板。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    /// preedit 分段。
    pub preedit: Vec<PreeditSpan>,

    /// 光标在拼接后 preedit 里的 UTF-8 字节偏移；`-1` 为无显式光标。
    pub preedit_cursor: i32,

    /// 当前页候选。
    pub candidates: Vec<CandidateRow>,

    /// `candidates` 里的高亮下标；`-1` 为无高亮。
    pub highlighted: i32,

    /// 当前页码（0 起）。
    pub page_index: u32,

    /// 总页数；0 表示没有候选态（此时 candidates 必空、highlighted 必 -1）。
    pub page_count: u32,

    /// 整句补全预览。
    pub completion: Option<String>,

    /// 瞬时提示。
    pub notice: Option<String>,
}

/// 空帧（收面板）：`highlighted` / `preedit_cursor` 的空值是 -1，不是 0——
/// 规范要求 `page_count = 0` 时 `highlighted` 必为 -1。
impl Default for Frame {
    fn default() -> Self {
        Self {
            preedit: Vec::new(),
            preedit_cursor: -1,
            candidates: Vec::new(),
            highlighted: -1,
            page_index: 0,
            page_count: 0,
            completion: None,
            notice: None,
        }
    }
}

/// 宿主 → 引擎的载荷。解码时只产出本方向的类型；收到引擎→宿主方向的
/// 类型直接判协议错误，不会出现在这里。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Inbound {
    /// 开激活：完整编辑器快照 + 配置快照。
    Activate {
        /// 激活世代。
        serial: u64,

        /// 端点能力。
        endpoint: Endpoint,

        /// 可变编辑器状态。
        editor: EditorState,

        /// 解析好的配置快照。
        config: Vec<ConfigEntry>,
    },

    /// 激活内整体替换可变编辑器状态。
    EditorUpdate {
        /// 激活世代。
        serial: u64,

        /// 新的编辑器状态。
        editor: EditorState,
    },

    /// 结束激活（自洽，吃掉开着的状态组）。
    Deactivate {
        /// 激活世代。
        serial: u64,
    },

    /// 关闭一组状态消息；组按原子单位生效。
    Done {
        /// 激活世代。
        serial: u64,
    },

    /// 一次原始物理按键。
    KeyEvent {
        /// 激活世代。
        serial: u64,

        /// evdev 键码。
        keycode: u32,

        /// 修饰键掩码（bit0 Shift / bit1 Ctrl / bit2 Alt / bit3 Super）。
        modifiers: u32,

        /// true 按下、false 抬起。
        pressed: bool,

        /// 激活内从 1 起的按键计数，应答时原样回显。
        key_id: u32,
    },

    /// 面板点选：上屏最新帧第 `index` 个候选。
    SelectCandidate {
        /// 激活世代。
        serial: u64,

        /// 最新帧 candidates 里的下标。
        index: u32,
    },

    /// 候选翻页；只看 `delta` 符号。
    PageCandidates {
        /// 激活世代。
        serial: u64,

        /// 翻页方向。
        delta: i32,
    },

    /// 壳请求的模式切换。
    SetInputMode {
        /// 激活世代。
        serial: u64,

        /// 目标模式。
        mode: InputMode,

        /// 云联想三态覆盖。
        cloud: CloudOverride,
    },

    /// 丢内存状态、按新快照原子重载配置。
    ReloadConfiguration {
        /// 激活世代。
        serial: u64,

        /// 新配置快照。
        config: Vec<ConfigEntry>,
    },
}

/// 引擎 → 宿主的载荷。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outbound {
    /// 连接后第一包（`ImeHello`）。
    Hello {
        /// 人类可读的名字（诊断用）。
        name: String,

        /// 人类可读的版本（诊断用）。
        version: String,
    },

    /// 面板快照（`ImeFrame`）。
    Frame {
        /// 激活世代。
        serial: u64,

        /// 快照内容。
        frame: Frame,
    },

    /// 上屏文本（`ImeCommitText`）。
    CommitText {
        /// 激活世代。
        serial: u64,

        /// 文本。
        text: String,
    },

    /// 行内 preedit（`ImeInlinePreedit`）；`text` 为 `None` 清除。
    InlinePreedit {
        /// 激活世代。
        serial: u64,

        /// 组字串；`None` 清除。
        text: Option<String>,

        /// 光标起（UTF-8 字节偏移，-1 无光标）。
        cursor_begin: i32,

        /// 光标止。
        cursor_end: i32,
    },

    /// 删光标周围文本（`ImeDeleteSurrounding`）。编码 / 校验齐备，但当前
    /// 没有任何代码路径产出它（暂不使用：上屏修文等场景才可能用到）；
    /// Legacy 端点本就拒收。
    DeleteSurrounding {
        /// 激活世代。
        serial: u64,

        /// 光标前删多少字节。
        before_bytes: u32,

        /// 光标后删多少字节。
        after_bytes: u32,
    },

    /// 引擎发起的模式 / 云开关状态（`ImeModeState`）。
    ModeState {
        /// 激活世代。
        serial: u64,

        /// 当前模式。
        mode: InputMode,

        /// 云联想是否生效。
        cloud_enabled: bool,
    },

    /// 生命周期状态（`ImeStatus`）。
    Status {
        /// 状态。
        status: EngineStatus,

        /// 诊断串（可空）。
        error: Option<String>,
    },

    /// 按键应答（`ImeKeyResult`）。
    KeyResult {
        /// 激活世代。
        serial: u64,

        /// 回显 `ImeKeyEvent.key_id`。
        key_id: u32,

        /// 引擎是否消费了这键。
        handled: bool,
    },
}
