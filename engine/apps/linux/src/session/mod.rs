//! 会话：宿主整个 seat 同一时刻只有一个活跃编辑器，所以一个 `Session`
//! 持当前组句。激活 / 去激活边界上 `break_chain`、清面板状态、落学习数据。
//! 职责对应 Windows Server 的 `dispatch`（那边按应用线程分会话）。

mod composed;
mod config;
mod effect;
mod input;
mod pending;
mod reload;
mod rescore;
mod shortcut;
#[cfg(test)]
mod tests;

use std::path::PathBuf;
use std::time::{Duration, Instant};

use qingjian_core::{Engine, SurroundingText};

use crate::ime::message::{CloudOverride, EditorState, Endpoint, Inbound, InputMode, Outbound};
use crate::keys;

pub(crate) use self::composed::Composed;
pub use self::config::SessionConfig;
use self::pending::{Active, Pending};
use self::reload::ConfigReload;
pub use self::reload::attach_cloud;
use self::rescore::{ModelLoader, RescoreState};

/// 学习数据落盘间隔（与 macOS / Windows 壳一致）；服务循环借节拍看时间。
const LEARNING_FLUSH_INTERVAL: Duration = Duration::from_secs(60);

/// 组句中 tick 的节拍上限：云联想 / 重排的在飞结果要勤看。
const COMPOSING_TICK: Duration = Duration::from_millis(50);

/// text-input-v3 `content_purpose` 里的敏感取值：8 = password、9 = pin。
/// 7 = name 不算（姓名字段没有保密语义）；terminal(13) 是用途提示而非
/// 保密位，同样不抑制。
const PRIVATE_PURPOSES: [u32; 2] = [8, 9];

/// text-input-v3 `content_hint` 的 `sensitive_data` 位。
const HINT_SENSITIVE: u32 = 1 << 7;

/// 输入会话：Engine + 分派配置 + 激活 / 展示 / 后台任务状态。
pub struct Session {
    /// 输入内核，进程内唯一。
    engine: Engine,

    /// 会话分派用的配置子集。
    config: SessionConfig,

    /// evdev 键码 → 字符翻译器（xkb 或 US 兜底）。
    keys: keys::Translator,

    /// 当前激活；`None` 表示没有编辑器持有文本焦点。
    active: Option<Active>,

    /// 还没等到 `ImeDone` 的状态组。
    pending: Option<Pending>,

    /// 持久英文（Latin）模式：只由 `ImeSetInputMode` 置位，跨激活保留。
    latin: bool,

    /// 本次激活的 Legacy 直通：激活落在 Legacy 端点且 `legacy_direct`
    /// 开着时置位（激活时重算）；用户切中文可解除。「端点缓解」与「用户
    /// 模式」两个语义分开，否则聚焦过一个 Legacy 窗口后，下一个普通
    /// 端点会继承直通。
    legacy_passthrough: bool,

    /// 观察到的 Caps Lock（锁键按普通事件转发，按下即翻转）。
    caps: bool,

    /// 观察到的 Num Lock（翻符号用）。
    num: bool,

    /// `ImeSetInputMode.cloud` 的三态覆盖；`None` 按 `[predict]` 配置。
    cloud_override: Option<bool>,

    /// Legacy 端点上默认英文直通、手动（Caps / 壳模式切换）进组句；
    /// 配置快照键 `legacy_direct`，缺省开（缓解 X11 密码框不可识别的缺口）。
    legacy_direct: bool,

    /// 当前组句的展示状态；没在组句时为 `None`。
    composed: Option<Composed>,

    /// 整句补全（preedit 右侧、Tab 上屏）；缓冲变化时清空。
    sentence: Option<String>,

    /// 删候选后的提示，随下一帧下发、下一次按键清。
    notice: Option<String>,

    /// 当前高亮候选在布局里的下标（跨页）。
    highlight: usize,

    /// 这轮查询里动过高亮：英文模式空格只在动过之后才选高亮词。
    navigated: bool,

    /// 行内 preedit 是否已下发（清了就不再发清除包）。
    inline_sent: bool,

    /// 上次把学习数据落盘的时间。
    last_flush: Instant,

    /// 重排的防抖 / 轮询进行态。
    rescore: RescoreState,

    /// 本地整句模型文件；没有为 `None`。
    model_path: Option<PathBuf>,

    /// 进行中的模型加载。
    model_loader: Option<ModelLoader>,

    /// 上次套用的 `[model]`，变了才重载 / 卸载。
    applied_model: qingjian_platform::LocalModelConfig,

    /// 配置文件热加载状态；`None` 表示不热加载。
    reload: Option<ConfigReload>,
}

impl Session {
    pub fn new(engine: Engine, config: SessionConfig) -> Self {
        Self {
            engine,
            config: SessionConfig {
                page_size: config.page_size.max(1),
                ..config
            },
            keys: keys::Translator::new(),
            active: None,
            pending: None,
            latin: false,
            legacy_passthrough: false,
            caps: false,
            num: false,
            cloud_override: None,
            legacy_direct: true,
            composed: None,
            sentence: None,
            notice: None,
            highlight: 0,
            navigated: false,
            inline_sent: false,
            last_flush: Instant::now(),
            rescore: RescoreState::default(),
            model_path: None,
            model_loader: None,
            applied_model: qingjian_platform::LocalModelConfig::default(),
            reload: None,
        }
    }

    /// 处理一条入站载荷，产出要回给宿主的出站载荷（按发送顺序）。
    /// serial 失配的载荷按规范直接丢。周期落盘**不在这里**：它是 fsync 级
    /// IO，「收到按键到应答之间不得有 IO」是任务卡硬要求——由调用方把
    /// 应答发完之后调 [`Self::flush_due`]。
    pub fn handle(&mut self, inbound: Inbound) -> Vec<Outbound> {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.dispatch(inbound)))
            .unwrap_or_else(|_| {
                tracing::error!("分派载荷时 panic，按空操作继续");
                Vec::new()
            })
    }

    /// 连接断开：组句作废、学习落盘；serial 由宿主重新发。
    /// 整个收尾在 panic 边界内，断连路径上的 panic 不该杀死服务循环。
    pub fn connection_lost(&mut self) {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.pending = None;
            self.active = None;
            self.reset_activation_state();
            self.reset_composition();
            self.flush_learning();
        }))
        .unwrap_or_else(|_| tracing::error!("断连收尾 panic，按已收尾继续"));
    }

    /// 空闲节拍：模型接入 / 重排推进 / 云联想收包 / 释义兜底 / 配置热加载。
    /// 有需要重发的帧就带回来。
    pub fn tick(&mut self) -> Vec<Outbound> {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.tick_inner())).unwrap_or_else(
            |_| {
                tracing::error!("空闲节拍 panic，按空操作继续");
                Vec::new()
            },
        )
    }

    fn tick_inner(&mut self) -> Vec<Outbound> {
        self.attach_loaded_model();
        let mut frame = false;
        if self.advance_rescoring() {
            frame = true;
        }
        if self.poll_prediction() {
            frame = true;
        }
        let learned = self.engine.poll_glosses();
        if learned > 0 {
            tracing::info!(learned, "释义兜底写入个人释义表");
        }
        self.poll_config_reload();
        match (self.current_serial(), frame) {
            (Some(serial), true) => vec![Outbound::Frame {
                serial,
                frame: self.current_frame(),
            }],
            _ => Vec::new(),
        }
    }

    /// 下次该 tick 的时长：在等重排按它的节拍，组句中按云联想的节拍，
    /// 否则按配置热加载的一秒。
    pub fn next_tick(&self) -> Duration {
        let composing = !self.engine.composition().is_empty();
        let idle = if composing {
            COMPOSING_TICK
        } else {
            reload::CONFIG_POLL_INTERVAL
        };
        self.rescore
            .next_deadline()
            .map_or(idle, |deadline| deadline.min(idle))
    }

    /// 到点（`LEARNING_FLUSH_INTERVAL`）就把学习数据落盘。由服务循环在
    /// **应答发出之后**调：收键到应答之间不允许出现 write/fsync 级 IO。
    /// tick 路径同样先发出站包再调它。
    pub fn flush_due(&mut self) {
        if self.last_flush.elapsed() >= LEARNING_FLUSH_INTERVAL {
            self.flush_learning();
        }
    }

    pub fn flush_learning(&mut self) {
        // 落盘是 IO：panic 不能拖垮服务循环，失败等下个 60 秒再来。
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.engine.flush_learning();
        }))
        .map_err(|_| tracing::error!("学习数据落盘 panic，等下一周期重试"));
        self.last_flush = Instant::now();
    }

    /// 当前引擎学语言 / 日志等（测试与诊断用）。
    #[cfg(test)]
    pub(crate) fn engine(&mut self) -> &mut Engine {
        &mut self.engine
    }

    fn dispatch(&mut self, inbound: Inbound) -> Vec<Outbound> {
        match inbound {
            Inbound::Activate {
                serial,
                endpoint,
                editor,
                config,
            } => {
                // 开着别的组：上一个组没等到 Done 就被覆盖了，丢掉（Deactivation
                // 语义同样隐式丢组）。
                self.pending = Some(Pending::Activate {
                    serial,
                    endpoint,
                    editor,
                    config,
                });
                Vec::new()
            }
            Inbound::EditorUpdate { serial, editor } => {
                match self.pending.as_ref().map(Pending::serial) {
                    // 组内更新：整体替换暂存的编辑器状态。
                    Some(group) if group == serial => match &mut self.pending {
                        Some(Pending::Activate { editor: staged, .. })
                        | Some(Pending::Updates { editor: staged, .. }) => *staged = editor,
                        None => {}
                    },
                    // 已有别的组开着：serial 不符的更新整条丢（规范：丢非当前
                    // serial 的载荷）——不能让它把开着的 Activate 组冲掉。
                    Some(_) => {}
                    // 属于当前激活的更新开一个新组；别的 serial 直接丢。
                    None if self.current_serial() == Some(serial) => {
                        self.pending = Some(Pending::Updates { serial, editor });
                    }
                    None => {}
                }
                Vec::new()
            }
            Inbound::Done { serial } => self.apply_pending(serial),
            Inbound::Deactivate { serial } => self.deactivate(serial),
            Inbound::KeyEvent {
                serial,
                keycode,
                modifiers,
                pressed,
                key_id,
            } => self.handle_key(serial, keycode, modifiers, pressed, key_id),
            Inbound::SelectCandidate { serial, index } => self.select_candidate(serial, index),
            Inbound::PageCandidates { serial, delta } => self.page_candidates(serial, delta),
            Inbound::SetInputMode {
                serial,
                mode,
                cloud,
            } => self.set_input_mode(serial, mode, cloud),
            Inbound::ReloadConfiguration { serial, config } => {
                if self.current_serial() != Some(serial) {
                    return Vec::new();
                }
                self.reset_composition();
                self.reload_configuration(&config);
                vec![Outbound::Frame {
                    serial,
                    frame: self.current_frame(),
                }]
            }
        }
    }

    /// `ImeDone`：应用暂存的组；serial 对不上（过期 / 无组）只丢这条
    /// Done，开着的组不动。
    fn apply_pending(&mut self, serial: u64) -> Vec<Outbound> {
        match &self.pending {
            Some(pending) if pending.serial() == serial => {}
            Some(_) => {
                tracing::debug!(serial, "Done 的 serial 与开着的组不符，丢弃");
                return Vec::new();
            }
            None => return Vec::new(),
        }
        match self.pending.take().unwrap() {
            Pending::Activate {
                serial,
                endpoint,
                editor,
                config,
            } => self.activate(serial, endpoint, editor, config),
            Pending::Updates { serial, editor } => {
                if self.current_serial() == Some(serial) {
                    self.apply_editor(&editor);
                }
                Vec::new()
            }
        }
    }

    /// 开激活：重置组句，应用编辑器状态与配置快照，回报模式。
    fn activate(
        &mut self,
        serial: u64,
        endpoint: Endpoint,
        editor: EditorState,
        config: Vec<crate::ime::message::ConfigEntry>,
    ) -> Vec<Outbound> {
        self.reset_composition();
        // 观察到的锁位不跨激活留：锁键只在激活期内被转发，激活外按过的
        // Caps / Num 看不见；每次激活回到已知基线（残余缺口见 crate-notes：
        // Activate/EditorUpdate 本就不带锁状态）。
        self.reset_activation_state();
        self.active = Some(Active {
            serial,
            endpoint,
            editor,
        });
        self.apply_config_snapshot(&config);
        // Legacy 直通策略：端点没有能力信号，默认先英文直通，用户经壳
        // 切模式进组句。激活级状态：下一激活按新端点重算（配置快照刚
        // 改过 legacy_direct 的话用新值）。
        self.legacy_passthrough = endpoint == Endpoint::Legacy && self.legacy_direct;
        let editor = self.active.as_ref().unwrap().editor.clone();
        self.apply_editor(&editor);
        tracing::debug!(serial, ?endpoint, app = %editor.app_id, "激活");
        vec![Outbound::ModeState {
            serial,
            mode: self.input_mode(),
            cloud_enabled: self.cloud_enabled(),
        }]
    }

    /// 编辑器状态整体生效：应用身份 / 私密位 / 光标前文。
    fn apply_editor(&mut self, editor: &EditorState) {
        let app = (!editor.app_id.is_empty()).then(|| editor.app_id.clone());
        self.engine.set_application(app);
        let private = PRIVATE_PURPOSES.contains(&editor.content_purpose)
            || editor.content_hint & HINT_SENSITIVE != 0;
        self.engine.set_private(private);
        // 前文给本地整句重排当上下文；组句空着时也记下，下一次组句直接用。
        let before = editor
            .surrounding
            .as_ref()
            .map(|s| s.text[..s.cursor as usize].to_owned());
        self.engine.set_rescoring_context(before);
    }

    /// 去激活：清组句与面板状态、落学习数据；按规范不再为该 serial 发
    /// 任何载荷（面板由宿主收起）。serial 只命中暂存组时只丢组——存活
    /// 激活不动；serial 命中存活激活时按规范隐含丢弃任何开着的组。
    fn deactivate(&mut self, serial: u64) -> Vec<Outbound> {
        if self.pending.as_ref().is_some_and(|p| p.serial() == serial) {
            self.pending = None;
            tracing::debug!(serial, "去激活吃掉没关的暂存组");
        }
        if self.current_serial() != Some(serial) {
            return Vec::new();
        }
        self.pending = None;
        self.active = None;
        self.reset_activation_state();
        self.reset_composition();
        self.flush_learning();
        tracing::debug!(serial, "去激活");
        Vec::new()
    }

    /// 一次按键：serial 失配整个丢；每个转发的键都要回 `ImeKeyResult`。
    /// 从收到键到给出应答的路径上没有 IO / 锁等待：xkb 翻译、Engine 查询、
    /// 帧组装全是内存操作，出站包由调用方随后一次性发。
    fn handle_key(
        &mut self,
        serial: u64,
        keycode: u32,
        modifiers: u32,
        pressed: bool,
        key_id: u32,
    ) -> Vec<Outbound> {
        if self.current_serial() != Some(serial) {
            return Vec::new();
        }
        let result = |handled| Outbound::KeyResult {
            serial,
            key_id,
            handled,
        };
        if !pressed {
            // 抬起不消费：按下的判定已经发过，抬起原样放行保持一致。
            return vec![result(false)];
        }
        // 锁键：只观察翻转，放行给系统（宿主的锁状态与我们观察的一致）。
        match keycode {
            keys::CAPS_LOCK => {
                self.caps = !self.caps;
                return vec![
                    result(false),
                    Outbound::ModeState {
                        serial,
                        mode: self.input_mode(),
                        cloud_enabled: self.cloud_enabled(),
                    },
                ];
            }
            keys::NUM_LOCK => {
                self.num = !self.num;
                return vec![result(false)];
            }
            _ => {}
        }
        // 修饰键本体永远放行：它们只作为掩码有意义。
        if keys::is_modifier(keycode) {
            return vec![result(false)];
        }
        self.notice = None;
        let event = self.keys.translate(
            keycode,
            keys::KeyModifiers::from_mask(modifiers),
            self.caps,
            self.num,
        );
        match self.apply_key(&event) {
            effect::Effect::Changed(commit) => {
                self.recompose();
                self.poll_prediction();
                let mut out = vec![result(true)];
                if let Some(text) = commit.filter(|text| !text.is_empty()) {
                    out.push(Outbound::CommitText { serial, text });
                }
                out.extend(self.inline_preedit(serial));
                out.push(Outbound::Frame {
                    serial,
                    frame: self.current_frame(),
                });
                out
            }
            effect::Effect::Navigated => {
                vec![
                    result(true),
                    Outbound::Frame {
                        serial,
                        frame: self.current_frame(),
                    },
                ]
            }
            effect::Effect::Passthrough => vec![result(false)],
        }
    }

    /// 面板点选：`index` 是最新帧 `candidates` 里的下标（帧内序号，不是布局下标）。
    fn select_candidate(&mut self, serial: u64, index: u32) -> Vec<Outbound> {
        if self.current_serial() != Some(serial) {
            return Vec::new();
        }
        let Some(layout_index) = self.layout_index_for_frame(index as usize) else {
            tracing::debug!(index, "点选下标不在最新帧候选范围");
            return Vec::new();
        };
        let Some(text) = self.commit_index(layout_index) else {
            return Vec::new();
        };
        self.recompose();
        self.poll_prediction();
        let mut out = vec![Outbound::CommitText { serial, text }];
        out.extend(self.inline_preedit(serial));
        out.push(Outbound::Frame {
            serial,
            frame: self.current_frame(),
        });
        out
    }

    /// 帧内候选下标 → 布局跨页下标：布局的空格不占帧行，按同样规则跳过。
    fn layout_index_for_frame(&self, index: usize) -> Option<usize> {
        let Some(Composed::Candidates { layout, .. }) = &self.composed else {
            return None;
        };
        let page_size = self.config.page_size;
        let page = self.highlight.min(layout.len().saturating_sub(1)) / page_size;
        layout
            .page(page)
            .iter()
            .enumerate()
            .filter(|(_, cell)| cell.candidate().is_some())
            .nth(index)
            .map(|(i, _)| page * page_size + i)
    }

    /// 面板翻页。
    fn page_candidates(&mut self, serial: u64, delta: i32) -> Vec<Outbound> {
        if self.current_serial() != Some(serial) {
            return Vec::new();
        }
        self.page(delta.signum() as isize);
        vec![Outbound::Frame {
            serial,
            frame: self.current_frame(),
        }]
    }

    /// 壳请求的模式切换 + 云三态覆盖；回报 `ImeModeState`。
    fn set_input_mode(
        &mut self,
        serial: u64,
        mode: InputMode,
        cloud: CloudOverride,
    ) -> Vec<Outbound> {
        if self.current_serial() != Some(serial) {
            return Vec::new();
        }
        self.latin = mode == InputMode::Latin;
        if mode == InputMode::Chinese {
            // 用户明确要组句：连本次激活的 Legacy 直通一起解除。
            self.legacy_passthrough = false;
        }
        self.cloud_override = match cloud {
            CloudOverride::Unchanged => self.cloud_override,
            CloudOverride::Enable => Some(true),
            CloudOverride::Disable => Some(false),
        };
        vec![
            Outbound::ModeState {
                serial,
                mode: self.input_mode(),
                cloud_enabled: self.cloud_enabled(),
            },
            // 切模式不动在飞组句（规范未要求，与 Windows 一致），但发一帧
            // 现状：面板上按旧模式画的候选 / preedit 立刻刷新，不挂到下一键。
            Outbound::Frame {
                serial,
                frame: self.current_frame(),
            },
        ]
    }

    /// 当前激活的 serial；没有激活为 `None`。
    fn current_serial(&self) -> Option<u64> {
        self.active.as_ref().map(|active| active.serial)
    }

    /// 聚焦应用的 app-id；没报为空串按 `None`。
    pub(super) fn focused_app(&self) -> Option<&str> {
        self.active
            .as_ref()
            .map(|active| active.editor.app_id.as_str())
            .filter(|app| !app.is_empty())
    }

    /// 端点给的光标前后文本 → Core 的 `SurroundingText`（按光标字节偏移切开）。
    /// Legacy 端点不提供。
    fn surrounding_text(&self) -> Option<SurroundingText> {
        let surrounding = self.active.as_ref()?.editor.surrounding.as_ref()?;
        Some(SurroundingText {
            before: surrounding.text[..surrounding.cursor as usize].to_owned(),
            after: surrounding.text[surrounding.cursor as usize..].to_owned(),
        })
    }

    /// 展示给壳的模式：Caps 亮着也算英文。
    fn input_mode(&self) -> InputMode {
        if self.caps || self.effective_latin() {
            InputMode::Latin
        } else {
            InputMode::Chinese
        }
    }

    /// 生效的英文直通判定：用户切的持久 Latin 模式，或本次激活的
    /// Legacy 直通（后者不跨激活）。
    fn effective_latin(&self) -> bool {
        self.latin || self.legacy_passthrough
    }

    /// 激活 / 断连边界上清掉按激活观察的状态：锁位回到已知基线，
    /// Legacy 直通作废（下次激活按新端点重算），行内 preedit 的「已下发」
    /// 标记同样作废——面板随激活由宿主收走，下一激活不该补发清除包。
    fn reset_activation_state(&mut self) {
        self.caps = false;
        self.num = false;
        self.legacy_passthrough = false;
        self.inline_sent = false;
    }

    /// 云联想当前是否生效：引擎接着 Predictor 且三态覆盖没关。
    pub(super) fn cloud_enabled(&self) -> bool {
        self.engine.prediction_enabled() && self.cloud_override.unwrap_or(true)
    }

    /// 行内 preedit：只有有能力的端点（WaylandTextInput / Flutter）且配置
    /// 不是 `Window` 才下发；组句结束清一次。Legacy 只在面板里画。
    fn inline_preedit(&mut self, serial: u64) -> Option<Outbound> {
        let capable = self
            .active
            .as_ref()
            .is_some_and(|active| active.endpoint.capable());
        let wanted = capable && self.config.preedit != qingjian_platform::PreeditMode::Window;
        if !wanted {
            if self.inline_sent {
                self.inline_sent = false;
                return Some(Outbound::InlinePreedit {
                    serial,
                    text: None,
                    cursor_begin: -1,
                    cursor_end: -1,
                });
            }
            return None;
        }
        let (text, cursor) = match &self.composed {
            Some(Composed::Raw { text, cursor }) => (text.clone(), *cursor),
            Some(Composed::Candidates {
                preedit, cursor, ..
            }) => {
                let text: String = preedit.iter().map(|span| span.text.as_str()).collect();
                (text, *cursor)
            }
            None => (String::new(), 0),
        };
        if text.is_empty() {
            if self.inline_sent {
                self.inline_sent = false;
                return Some(Outbound::InlinePreedit {
                    serial,
                    text: None,
                    cursor_begin: -1,
                    cursor_end: -1,
                });
            }
            return None;
        }
        self.inline_sent = true;
        let offset = text
            .char_indices()
            .nth(cursor)
            .map(|(index, _)| index)
            .unwrap_or(text.len()) as i32;
        Some(Outbound::InlinePreedit {
            serial,
            text: Some(text),
            cursor_begin: offset,
            cursor_end: offset,
        })
    }

    /// 清掉组句、展示状态、在飞的云联想与重排；行内 preedit 由下一次帧周期清。
    pub(super) fn reset_composition(&mut self) {
        self.engine.break_chain();
        self.engine.clear();
        self.cancel_prediction();
        self.stop_rescoring();
        self.composed = None;
        self.sentence = None;
        self.notice = None;
        self.highlight = 0;
        self.navigated = false;
    }
}
