//! 会话要用的配置项，与 Windows Server 的 `RouterConfig` 对齐。

use qingjian_core::ShuangpinScheme;
use qingjian_platform::{AppsConfig, Config, PreeditMode};

use crate::keys::KeyModifiers;

/// 会话分派用的配置子集。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionConfig {
    /// 每页候选数（`[general] page_size`）。
    pub(crate) page_size: usize,

    /// 云端候选在第一页预留的格数（`[predict] slots`）。
    pub(crate) cloud_slots: usize,

    /// 翻页键对（`[general] page_keys`，上一页 / 下一页）。
    pub(crate) page_keys: (char, char),

    /// 英文（Caps）模式给不给英文候选（`[general] english_candidates`）。
    pub(crate) english_candidates: bool,

    /// 中文模式下不在组句时的标点转全角（`[general] full_width_punctuation`）。
    pub(crate) full_width: bool,

    /// 英文模式的那一份（`[general] english_full_width_punctuation`）。
    pub(crate) english_full_width: bool,

    /// 大千注音（`[general] zhuyin`）。
    pub(crate) zhuyin: bool,

    /// 按应用的设置（`[apps]`），按 app-id 认。
    pub(crate) apps: AppsConfig,

    /// 上屏第一 / 第二个译词的修饰键（`[shortcut] translation` / `translation_second`）。
    pub(crate) translation_keys: (KeyModifiers, KeyModifiers),

    /// 删候选的修饰键（`[shortcut] delete_candidate`）。
    pub(crate) delete_keys: KeyModifiers,

    /// 双拼方案（`[general] shuangpin`）；全拼为 `None`。
    pub(crate) shuangpin: Option<ShuangpinScheme>,

    /// 拼音显示位置（`[general] preedit`）；决定要不要发行内 preedit。
    pub(crate) preedit: PreeditMode,
}

impl SessionConfig {
    /// 全局开关开着，且应用不在 `[apps] english_candidates_off` 里；没报 app-id 按不关。
    pub(crate) fn english_candidates_in(&self, app: Option<&str>) -> bool {
        self.english_candidates && !app.is_some_and(|app| self.apps.english_candidates_off(app))
    }
}

impl From<&Config> for SessionConfig {
    fn from(config: &Config) -> Self {
        Self {
            page_size: config.general.page_size().max(1),
            cloud_slots: config.predict.slots,
            page_keys: config.general.page_keys(),
            english_candidates: config.general.english_candidates,
            full_width: config.general.full_width_punctuation,
            english_full_width: config.general.english_full_width_punctuation,
            zhuyin: config.general.zhuyin,
            apps: config.apps.clone(),
            translation_keys: {
                let (first, second) = config.shortcut.translation_keys();
                (first.into(), second.into())
            },
            delete_keys: config.shortcut.delete_keys().into(),
            shuangpin: config.general.shuangpin(),
            preedit: config.general.preedit,
        }
    }
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self::from(&Config::default())
    }
}
