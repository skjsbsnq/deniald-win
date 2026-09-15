//! 按键怎么作用到 Engine / 高亮上。分流规则与 Windows Server 的
//! `dispatch/key/input.rs`（以及 macOS 壳的 `handle_text`）对齐：
//! 功能键靠 evdev 键码，其余靠翻译出的字符；组句中「修饰键 + 数字」是快捷键；
//! 带 Ctrl / Alt / Super 而没配到快捷键的键交还宿主回注。

use qingjian_core::QUESTION_PREFIX;
use qingjian_core::shortcut;

use super::Session;
use super::effect::{Effect, with_prefix};
use crate::keys::{self, KeyEvent};

impl Session {
    /// 一次按下的分派；应答语义由调用方按 [`Effect`] 折成 `handled`。
    pub(super) fn apply_key(&mut self, event: &KeyEvent) -> Effect {
        if self.composing()
            && !self.engine.expression_mode()
            && let Some(digit) = keys::digit_key(event.keycode)
            && let Some(effect) = self.apply_digit_shortcut(digit, event.modifiers)
        {
            return effect;
        }
        if event.modifiers.has_command_key() {
            return Effect::Passthrough;
        }
        let Some(c) = event.character.filter(|c| !c.is_control()) else {
            return self.apply_function_key(event);
        };
        // Caps 亮着无论中英模式都直接出英文；英文候选只在英文（Latin 或
        // Legacy 直通）模式、Caps 灭、应用允许时给。
        let caps = event.caps;
        let english = caps || self.effective_latin();
        let english_candidates = self.effective_latin()
            && !caps
            && self.config.english_candidates_in(self.focused_app());
        // 缓冲区为空时敲 `?` 先进问字模式，中英文模式都行：后面跟字母就是在问字，
        // 跟别的键就还原成问号。
        if !self.composing() && c == QUESTION_PREFIX {
            self.engine.set_english_mode(false);
            self.engine.push(c);
            return Effect::Changed(None);
        }
        let question = self.composing() && self.engine.question_mode();
        // 英文模式下问字：Caps 让字母以大写送来，按小写收进问题。
        let c = if question && english && c.is_ascii_uppercase() {
            c.to_ascii_lowercase()
        } else {
            c
        };
        // 只有一个 `?` 时敲了字母以外的键：还原成问号上屏；空格只是「把这个 ?
        // 上屏」，其他键按没在组句重新分派。
        if question && !c.is_ascii_lowercase() && self.engine.bare_question() {
            let mark = self
                .engine
                .restore_bare_question(english)
                .unwrap_or_else(|| {
                    self.engine.clear();
                    QUESTION_PREFIX.to_string()
                });
            if c == ' ' {
                return Effect::Changed(Some(mark));
            }
            return with_prefix(Some(mark), self.apply_key(event), c);
        }
        // 英文组词中候选被关掉（Caps 亮 / 切应用）：敲过的字母先原样上屏。
        let flushed = (self.composing() && !english_candidates && self.engine.english_mode())
            .then(|| self.engine.take_raw());
        self.engine
            .set_english_mode(english_candidates && !question);
        let effect = if english && !question {
            self.apply_english(c, english_candidates, event)
        } else {
            self.apply_chinese(c, event)
        };
        with_prefix(flushed, effect, c)
    }

    /// 退格 / Esc / 回车 / Tab / 方向键；没在组句时都交还宿主回注。
    fn apply_function_key(&mut self, event: &KeyEvent) -> Effect {
        if !self.composing() {
            // 回车交给应用：文本流里是一个段落边界（macOS 壳同样记）。
            if event.keycode == keys::ENTER {
                self.engine.note_passthrough('\n');
            }
            return Effect::Passthrough;
        }
        // 只有一个 `?` 时按了回车：回车就是「把这个 ? 上屏」，吞掉，否则聊天框会
        // 连消息一起发出去；退格 / Esc 照常删掉它。其他功能键还原成问号后一
        // 并吞掉：放行是宿主回注、上屏是另一包，先动光标再插问号会插错位置。
        if self.engine.bare_question() && !matches!(event.keycode, keys::BACKSPACE | keys::ESC) {
            let english = event.caps || self.effective_latin();
            let mark = self
                .engine
                .restore_bare_question(english)
                .unwrap_or_else(|| QUESTION_PREFIX.to_string());
            return Effect::Changed(Some(mark));
        }
        match event.keycode {
            keys::BACKSPACE => {
                self.engine.backspace();
                Effect::Changed(None)
            }
            keys::ESC => {
                self.engine.clear();
                Effect::Changed(None)
            }
            keys::ENTER => Effect::Changed(Some(self.engine.take_raw())),
            keys::TAB if self.engine.english_mode() => {
                Effect::Changed(Some(self.commit_highlighted()))
            }
            // 中文模式 Tab：有整句补全就接受，否则交还宿主（缩进 / 跳焦点）。
            keys::TAB => match self.sentence.take() {
                Some(sentence) => Effect::Changed(Some(self.engine.accept_prediction(&sentence))),
                None => Effect::Passthrough,
            },
            keys::DOWN => {
                self.move_highlight(1);
                Effect::Navigated
            }
            keys::UP => {
                self.move_highlight(-1);
                Effect::Navigated
            }
            keys::PAGE_DOWN => {
                self.page(1);
                Effect::Navigated
            }
            keys::PAGE_UP => {
                self.page(-1);
                Effect::Navigated
            }
            keys::LEFT => {
                self.engine.move_cursor_left();
                Effect::Changed(None)
            }
            keys::RIGHT => {
                self.engine.move_cursor_right();
                Effect::Changed(None)
            }
            keys::HOME => {
                self.engine.move_cursor_home();
                Effect::Changed(None)
            }
            keys::END => {
                self.engine.move_cursor_end();
                Effect::Changed(None)
            }
            _ => Effect::Passthrough,
        }
    }

    /// 中文模式：小写字母进拼音；Shift 大写字母是临时打英文，组句中先把拼音
    /// 原样上屏；没在组句时的其他字符走全角标点（组句中的标点仍进英文直输段）。
    fn apply_chinese(&mut self, c: char, event: &KeyEvent) -> Effect {
        if c.is_ascii_uppercase() {
            let raw = self.composing().then(|| self.engine.take_raw());
            self.engine.note_passthrough(c);
            return with_prefix(raw, Effect::Passthrough, c);
        }
        if c.is_ascii_lowercase() {
            self.engine.push(c);
            return Effect::Changed(None);
        }
        if !self.composing() {
            return self.apply_punctuation(c, event);
        }
        self.apply_printable(c, event)
    }

    /// 当前模式开着全角就让 Core 转（数字后的 `.` 保持半角）；转不了的原样
    /// 交还宿主并告知 Core。
    fn apply_punctuation(&mut self, c: char, event: &KeyEvent) -> Effect {
        let english = event.caps || self.effective_latin();
        if self.full_width_for(english)
            && let Some(text) = self.engine.punctuate(c)
        {
            return Effect::Changed(Some(text.to_owned()));
        }
        self.engine.note_passthrough(c);
        Effect::Passthrough
    }

    /// 英文模式。开着候选：字母进缓冲区，空格 / 标点先把字母原样上屏（动过
    /// 高亮的空格才选词）；关着候选：字母由我们上屏。其他键按英文模式那份
    /// 全角设置转，转不了的交还宿主。
    fn apply_english(&mut self, c: char, candidates: bool, event: &KeyEvent) -> Effect {
        let composing = self.composing();
        if !candidates {
            let raw = composing.then(|| self.engine.take_raw());
            let effect = if c.is_ascii_alphabetic() {
                self.engine.note_passthrough(c);
                Effect::Changed(Some(c.to_string()))
            } else {
                self.apply_punctuation(c, event)
            };
            return with_prefix(raw, effect, c);
        }
        if c.is_ascii_alphabetic()
            || (composing && (c.is_ascii_digit() || matches!(c, '_' | '\'' | '-')))
        {
            self.engine.push(c);
            return Effect::Changed(None);
        }
        let committed = composing.then(|| {
            if c == ' ' && self.navigated {
                self.commit_highlighted()
            } else {
                self.engine.take_raw()
            }
        });
        let effect = self.apply_punctuation(c, event);
        with_prefix(committed, effect, c)
    }

    /// 组句中的可打印键：数字选当前页第 N 个，翻页键翻页，空格上屏高亮，其余
    /// 进英文直输段。表达式 / 问字 / 双拼 `;` 的特例与 Windows 一致。
    fn apply_printable(&mut self, c: char, event: &KeyEvent) -> Effect {
        let expression = self.engine.expression_mode();
        if (expression && shortcut::is_expression_char(c))
            || (self.engine.unicode_entry() && (c.is_ascii_digit() || c == '+'))
            || (c == ';' && self.engine.takes_semicolon())
        {
            self.engine.push(c);
            return Effect::Changed(None);
        }
        if let Some(digit) = digit(event)
            && self.candidate_count() > 0
        {
            let page_size = self.config.page_size;
            let page = self.highlight / page_size;
            return Effect::Changed(self.commit_index(page * page_size + digit - 1));
        }
        if let Some(step) = page_key(event, self.config.page_keys) {
            self.page(step);
            return Effect::Navigated;
        }
        if c == ' ' {
            return Effect::Changed(Some(self.commit_highlighted()));
        }
        // 表达式 / 问字模式下的其他字符不进缓冲区：先把高亮候选上屏，
        // 再按没在组句处理这个键。
        if c != '\'' && (expression || self.engine.question_mode()) {
            let committed = self.commit_highlighted();
            let effect = self.apply_punctuation(c, event);
            return with_prefix(Some(committed), effect, c);
        }
        self.engine.push(c);
        Effect::Changed(None)
    }

    /// 上屏高亮候选；没有候选时缓冲原样上屏。
    fn commit_highlighted(&mut self) -> String {
        match self.commit_index(self.highlight) {
            Some(text) => text,
            None => self.engine.take_raw(),
        }
    }

    fn composing(&self) -> bool {
        !self.engine.composition().is_empty()
    }

    fn full_width_for(&self, english: bool) -> bool {
        if english {
            self.config.english_full_width
        } else {
            self.config.full_width
        }
    }
}

/// 敲出来是数字 1–9 的键（选候选用）：按字符认，Shift 出的 `!@#` 不算。
fn digit(event: &KeyEvent) -> Option<usize> {
    match event.character {
        Some(c) => ('1'..='9').contains(&c).then(|| c as usize - '0' as usize),
        None => keys::digit_key(event.keycode),
    }
}

/// 翻页键对 `(上一页, 下一页)`：返回 -1 / +1。
fn page_key(event: &KeyEvent, page_keys: (char, char)) -> Option<isize> {
    let c = event.character?;
    if c == page_keys.0 {
        Some(-1)
    } else if c == page_keys.1 {
        Some(1)
    } else {
        None
    }
}
