//! xkbcommon 按键翻译：evdev 键码 + 修饰掩码 + 锁定位 → 字符。
//!
//! 自己起一份 XKB 上下文（`XKB_DEFAULT_*` 环境变量或系统默认布局），
//! 每个事件用 `update_mask` 显式喂入协议给的修饰掩码与会话观察到的锁定位，
//! 不从 `update_key` 累计状态——协议的掩码是唯一权威，事件乱序也不会让
//! 内部状态漂掉。

use xkbcommon::xkb;

/// evdev 键码到 xkb 键码的固定偏移。
const EVDEV_OFFSET: u32 = 8;

/// 键码 → 字符的翻译器；xkb 初始化失败退回 US 布局表（[`super::codes::us_char`]）。
pub(crate) struct Translator {
    /// xkb 状态；`None` 走兜底表。
    xkb: Option<Xkb>,
}

struct Xkb {
    /// 键盘状态（掩码每个事件显式重设，不累计）。
    state: xkb::State,

    /// Shift 的 mod 位。
    shift: u32,

    /// Ctrl 的 mod 位。
    ctrl: u32,

    /// Alt（Mod1）的 mod 位。
    alt: u32,

    /// Super（Mod4）的 mod 位。
    logo: u32,

    /// Caps Lock 的 mod 位。
    lock: u32,

    /// Num Lock 的 mod 位。
    num: u32,
}

impl Translator {
    /// 起 xkb；失败记日志、退回兜底表。
    pub(crate) fn new() -> Self {
        Self { xkb: Xkb::new() }
    }

    /// 一次按键翻译成 [`super::KeyEvent`]。`caps` / `num` 是会话观察到的锁定位。
    pub(crate) fn translate(
        &mut self,
        keycode: u32,
        modifiers: super::KeyModifiers,
        caps: bool,
        num: bool,
    ) -> super::KeyEvent {
        let character = self.character(keycode, modifiers, caps, num);
        super::KeyEvent {
            keycode,
            character,
            modifiers,
            caps,
        }
    }

    fn character(
        &mut self,
        keycode: u32,
        modifiers: super::KeyModifiers,
        caps: bool,
        num: bool,
    ) -> Option<char> {
        if let Some(xkb) = &mut self.xkb {
            return xkb.character(keycode, modifiers, caps, num);
        }
        super::codes::us_char(keycode, modifiers.shift, caps)
    }
}

impl Xkb {
    fn new() -> Option<Self> {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        // 空 RMLVO 走 XKB_DEFAULT_* 环境变量与系统默认，跟会话布局一致。
        let keymap = xkb::Keymap::new_from_names(
            &context,
            "",
            "",
            "",
            "",
            None,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )?;
        let state = xkb::State::new(&keymap);
        let index = |name: &str| {
            let i = keymap.mod_get_index(name);
            (i != xkb::MOD_INVALID).then_some(i)
        };
        Some(Self {
            state,
            shift: index("Shift").map(|i| 1 << i).unwrap_or(0),
            ctrl: index("Control").map(|i| 1 << i).unwrap_or(0),
            alt: index("Mod1").map(|i| 1 << i).unwrap_or(0),
            logo: index("Mod4").map(|i| 1 << i).unwrap_or(0),
            lock: index("Lock").map(|i| 1 << i).unwrap_or(0),
            num: index("Mod2").map(|i| 1 << i).unwrap_or(0),
        })
    }

    /// 显式喂修饰 / 锁定位后取字符；多字符结果（如 keysym 展开）只取第一个字符。
    fn character(
        &mut self,
        keycode: u32,
        modifiers: super::KeyModifiers,
        caps: bool,
        num: bool,
    ) -> Option<char> {
        let depressed = modifiers.shift as u32 * self.shift
            + modifiers.ctrl as u32 * self.ctrl
            + modifiers.alt as u32 * self.alt
            + modifiers.logo as u32 * self.logo;
        let locked = caps as u32 * self.lock + num as u32 * self.num;
        self.state.update_mask(depressed, 0, locked, 0, 0, 0);
        let text = self
            .state
            .key_get_utf8(xkb::Keycode::new(keycode + EVDEV_OFFSET));
        text.chars().next().filter(|c| !c.is_control())
    }
}
