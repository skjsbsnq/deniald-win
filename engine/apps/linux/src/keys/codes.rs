//! evdev（`linux/input-event-codes.h`）键码常量与 US 布局兜底字符表。

pub(crate) const ESC: u32 = 1;
pub(crate) const BACKSPACE: u32 = 14;
pub(crate) const TAB: u32 = 15;
pub(crate) const ENTER: u32 = 28;
pub(crate) const LEFT_CTRL: u32 = 29;
pub(crate) const LEFT_SHIFT: u32 = 42;
pub(crate) const RIGHT_SHIFT: u32 = 54;
pub(crate) const LEFT_ALT: u32 = 56;
pub(crate) const CAPS_LOCK: u32 = 58;
pub(crate) const NUM_LOCK: u32 = 69;
pub(crate) const RIGHT_CTRL: u32 = 97;
pub(crate) const RIGHT_ALT: u32 = 100;
pub(crate) const HOME: u32 = 102;
pub(crate) const UP: u32 = 103;
pub(crate) const PAGE_UP: u32 = 104;
pub(crate) const LEFT: u32 = 105;
pub(crate) const RIGHT: u32 = 106;
pub(crate) const END: u32 = 107;
pub(crate) const DOWN: u32 = 108;
pub(crate) const PAGE_DOWN: u32 = 109;
pub(crate) const LEFT_META: u32 = 125;
pub(crate) const RIGHT_META: u32 = 126;

/// 是不是纯修饰键（Shift / Ctrl / Alt / Super 本体）：不放行消费决定靠它。
pub(crate) fn is_modifier(keycode: u32) -> bool {
    matches!(
        keycode,
        LEFT_SHIFT
            | RIGHT_SHIFT
            | LEFT_CTRL
            | RIGHT_CTRL
            | LEFT_ALT
            | RIGHT_ALT
            | LEFT_META
            | RIGHT_META
    )
}

/// 数字键 1–9（主键盘区）的键位值，选候选 / 修饰键快捷键按键位认。
pub(crate) fn digit_key(keycode: u32) -> Option<usize> {
    (2..=10).contains(&keycode).then(|| (keycode - 1) as usize)
}

/// US 布局兜底：xkb 起不来时把键码翻成字符，保住基本打字。
/// `shift` 为上档后的字符；`caps` 只翻转字母键的上档（数字 / 标点不受
/// Caps 影响），Num Lock 对这张表里的键位无作用故不吃。
pub(crate) fn us_char(keycode: u32, shift: bool, caps: bool) -> Option<char> {
    let shift = shift ^ (caps && is_letter_key(keycode));
    let (plain, shifted) = match keycode {
        // 主键盘数字行
        2 => ('1', '!'),
        3 => ('2', '@'),
        4 => ('3', '#'),
        5 => ('4', '$'),
        6 => ('5', '%'),
        7 => ('6', '^'),
        8 => ('7', '&'),
        9 => ('8', '*'),
        10 => ('9', '('),
        11 => ('0', ')'),
        12 => ('-', '_'),
        13 => ('=', '+'),
        // QWERTY 三排
        16..=25 => (qwerty_row(0, keycode - 16), qwerty_upper(0, keycode - 16)),
        30..=38 => (qwerty_row(1, keycode - 30), qwerty_upper(1, keycode - 30)),
        44..=50 => (qwerty_row(2, keycode - 44), qwerty_upper(2, keycode - 44)),
        // 标点与其余
        26 => ('[', '{'),
        27 => (']', '}'),
        39 => (';', ':'),
        40 => ('\'', '"'),
        41 => ('`', '~'),
        43 => ('\\', '|'),
        51 => (',', '<'),
        52 => ('.', '>'),
        53 => ('/', '?'),
        57 => (' ', ' '),
        _ => return None,
    };
    Some(if shift { shifted } else { plain })
}

/// QWERTY 三排字母键的键码段。
fn is_letter_key(keycode: u32) -> bool {
    matches!(keycode, 16..=25 | 30..=38 | 44..=50)
}

const ROWS: [(&str, &str); 3] = [
    ("qwertyuiop", "QWERTYUIOP"),
    ("asdfghjkl", "ASDFGHJKL"),
    ("zxcvbnm", "ZXCVBNM"),
];

fn qwerty_row(row: usize, index: u32) -> char {
    ROWS[row].0.as_bytes()[index as usize] as char
}

fn qwerty_upper(row: usize, index: u32) -> char {
    ROWS[row].1.as_bytes()[index as usize] as char
}
