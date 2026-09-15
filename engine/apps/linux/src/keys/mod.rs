//! 按键翻译：协议的 evdev 键码 + 修饰掩码 → [`KeyEvent`]（字符 / 功能键）。
//!
//! 翻译在 [`xkb`]（尊重会话键盘布局），xkb 起不来退回 [`codes`] 的 US 兜底表。
//! 锁定位（Caps / Num）不在协议的修饰掩码里，由会话观察锁键事件得出，
//! 再喂给这里的字符解析。

mod codes;
mod xkb;

pub(crate) use self::codes::*;
pub(crate) use self::xkb::Translator;

/// 一次按键的修饰键状态（协议 `ImeKeyEvent.modifiers` 的位展开）。
/// 锁定位与输入法模式不在这里。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct KeyModifiers {
    /// Shift。
    pub shift: bool,

    /// Ctrl。
    pub ctrl: bool,

    /// Alt（Mod1）。
    pub alt: bool,

    /// Super（Mod4）。
    pub logo: bool,
}

impl KeyModifiers {
    /// 协议掩码展开。
    pub fn from_mask(mask: u32) -> Self {
        Self {
            shift: mask & 1 != 0,
            ctrl: mask & 2 != 0,
            alt: mask & 4 != 0,
            logo: mask & 8 != 0,
        }
    }

    /// 有没有按着 Ctrl / Alt / Super（Shift 只改字符大小写与标点，不算）。
    pub fn has_command_key(self) -> bool {
        self.ctrl || self.alt || self.logo
    }
}

/// 配置层 [`qingjian_platform::Modifiers`]（macOS 命名）落到本平台的键位：
/// option 是 Alt、command 是 Super、control 是 Ctrl。
impl From<qingjian_platform::Modifiers> for KeyModifiers {
    fn from(m: qingjian_platform::Modifiers) -> Self {
        Self {
            shift: m.shift,
            ctrl: m.control,
            alt: m.option,
            logo: m.command,
        }
    }
}

/// 翻译后喂给会话分流的一次按键。
#[derive(Debug, Clone, Copy)]
pub(crate) struct KeyEvent {
    /// evdev 键码；功能键、锁键、修饰键按它认。
    pub keycode: u32,

    /// 该键在当前修饰 / 锁定状态下产生的字符；功能键为 `None`。
    pub character: Option<char>,

    /// 按下时的修饰键。
    pub modifiers: KeyModifiers,

    /// Caps Lock 亮着（会话观察锁键事件得出）。
    pub caps: bool,
}
