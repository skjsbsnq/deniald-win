//! 组句的展示状态：缓冲变化时重查候选并重建 [`Composed`]，云端词异步并入，
//! 高亮 / 翻页，按状态生成 `ImeFrame` 面板快照。职责对应 Windows Server 的
//! `dispatch/composed`。

use qingjian_core::{Candidate, CandidateKind, CandidateLayout, CustomPhrase, MarkedKind};

use crate::ime::message::{CandidateRow, Frame, PreeditSpan, PreeditStyle};

use super::Session;

/// 当前组句缓冲对应的展示状态。缓冲变化时重建，导航只挪高亮。
pub(crate) enum Composed {
    /// 正常查到候选。
    Candidates {
        /// preedit 分段。
        preedit: Vec<PreeditSpan>,

        /// 光标在拼接后 preedit 里的字符位置。
        cursor: usize,

        /// 本地 + 云端槽位的候选布局。
        layout: CandidateLayout,
    },

    /// 查询失败（如上屏后剩下不可切分的残余）：显示原始拼音、无候选。
    /// 不能回空帧，否则组句非空却没有候选面板。
    Raw {
        /// 原始拼音。
        text: String,

        /// 光标字符位置。
        cursor: usize,
    },
}

impl Session {
    /// 缓冲变化后：按 Engine 状态重建 [`Composed`]，发一次云联想请求，归零高亮与整句补全。
    pub(super) fn recompose(&mut self) {
        self.highlight = 0;
        self.navigated = false;
        self.sentence = None;
        if self.engine.composition().is_empty() {
            self.composed = None;
            self.cancel_prediction();
            self.stop_rescoring();
            return;
        }
        self.attach_loaded_model();
        let built = self.engine.query().ok().map(|query| {
            let items = query.candidates.items.clone();
            let preedit: Vec<PreeditSpan> =
                query.marked_segments().iter().map(preedit_span).collect();
            // 光标用 Core 的映射：自动补的 `'` 会让显示串比敲的长。
            (items, preedit, query.marked_cursor())
        });
        self.composed = Some(match built {
            Some((items, preedit, cursor)) => {
                let layout =
                    CandidateLayout::new(items, self.config.page_size, self.config.cloud_slots);
                if self.cloud_enabled() {
                    self.engine
                        .request_prediction(self.surrounding_text(), layout.local());
                }
                Composed::Candidates {
                    preedit,
                    cursor,
                    layout,
                }
            }
            None => {
                self.cancel_prediction();
                let composition = self.engine.composition();
                let text = composition.text().to_owned();
                let cursor = text[..composition.cursor()].chars().count();
                Composed::Raw { text, cursor }
            }
        });
        self.schedule_rescoring();
    }

    /// 拉一次云联想结果：云端词并进候选布局，整句补全记下。
    /// 返回 `true` 表示有新结果并入、要重发帧。
    pub(super) fn poll_prediction(&mut self) -> bool {
        if !self.cloud_enabled() {
            return false;
        }
        let Some(prediction) = self.engine.poll_prediction() else {
            return false;
        };
        if let Some(Composed::Candidates { layout, .. }) = self.composed.as_mut() {
            let words: Vec<Candidate> = prediction
                .words
                .into_iter()
                .map(qingjian_core::CloudWord::into_candidate)
                .collect();
            layout.set_cloud(words);
            self.sentence = prediction.sentence;
        }
        true
    }

    pub(super) fn cancel_prediction(&mut self) {
        if self.engine.prediction_enabled() {
            self.engine.cancel_prediction();
        }
    }

    /// 高亮移动 `delta`，夹在 `[0, 末尾]`，到页边自然换页。
    pub(super) fn move_highlight(&mut self, delta: isize) {
        let count = self.candidate_count();
        if count == 0 {
            self.highlight = 0;
            return;
        }
        let next = (self.highlight as isize + delta).clamp(0, count as isize - 1) as usize;
        self.navigated |= next != self.highlight;
        self.highlight = next;
    }

    /// 整页翻 `step`，高亮落到目标页第一个候选。
    pub(super) fn page(&mut self, step: isize) {
        let count = self.candidate_count();
        if count == 0 {
            self.highlight = 0;
            return;
        }
        let page_size = self.config.page_size;
        let page_count = count.div_ceil(page_size);
        let current = (self.highlight / page_size) as isize;
        let target = (current + step).clamp(0, page_count as isize - 1) as usize;
        if target != current as usize {
            self.navigated = true;
            self.engine.note_page_turn();
        }
        self.highlight = (target * page_size).min(count - 1);
    }

    pub(super) fn candidate_count(&self) -> usize {
        match &self.composed {
            Some(Composed::Candidates { layout, .. }) => layout.len(),
            _ => 0,
        }
    }

    /// 候选布局里第 `index` 个（跨页下标）。
    pub(super) fn layout_candidate(&self, index: usize) -> Option<Candidate> {
        match &self.composed {
            Some(Composed::Candidates { layout, .. }) => layout.candidate(index).cloned(),
            _ => None,
        }
    }

    pub(super) fn commit_index(&mut self, index: usize) -> Option<String> {
        let candidate = self.layout_candidate(index)?;
        Some(self.engine.commit(&candidate))
    }

    /// 按当前状态生成一帧：没在组句给空帧；否则给高亮所在的那一页。
    /// `ImeFrame` 是全量快照，面板按它整面替换。
    /// 发帧近似「画出了这一页」：当页候选记给 `Engine::note_displayed`
    /// （词汇曝光 / fresh 毕业靠它——壳不掌握面板真实绘出时机，按发帧算）；
    /// 空帧 / 无候选页传空迭代器。
    pub(super) fn current_frame(&mut self) -> Frame {
        match &self.composed {
            None => {
                self.engine.note_displayed(std::iter::empty());
                Frame::default()
            }
            Some(Composed::Raw { text, cursor }) => {
                self.engine.note_displayed(std::iter::empty());
                Frame {
                    preedit: vec![PreeditSpan {
                        text: text.clone(),
                        style: PreeditStyle::Underline,
                    }],
                    preedit_cursor: cursor_byte_offset(text, *cursor),
                    candidates: Vec::new(),
                    highlighted: -1,
                    page_index: 0,
                    page_count: 0,
                    completion: None,
                    notice: self.notice.clone(),
                }
            }
            Some(Composed::Candidates {
                preedit,
                cursor,
                layout,
            }) => {
                let page_size = self.config.page_size;
                let count = layout.len();
                if count == 0 {
                    self.engine.note_displayed(std::iter::empty());
                    return Frame {
                        preedit: preedit.clone(),
                        preedit_cursor: preedit_cursor(preedit, *cursor),
                        candidates: Vec::new(),
                        highlighted: -1,
                        page_index: 0,
                        page_count: 0,
                        completion: self.sentence.clone(),
                        notice: self.notice.clone(),
                    };
                }
                let highlight = self.highlight.min(count - 1);
                let page = highlight / page_size;
                // 高亮是帧内下标：布局里的空格（自定义短语留的位）不占行，
                // 落在空格上时本帧无高亮（-1）。
                let within = highlight - page * page_size;
                let mut highlighted = -1i32;
                let mut items: Vec<Candidate> = Vec::new();
                for (index, cell) in layout.page(page).iter().enumerate() {
                    let Some(candidate) = cell.candidate() else {
                        continue;
                    };
                    if index == within {
                        highlighted = items.len() as i32;
                    }
                    items.push(candidate.clone());
                }
                let mut candidates = qingjian_core::CandidateList { items };
                self.engine.annotate(&mut candidates);
                // 当页候选算「这一轮被看到过」：曝光记进词汇表（fresh 毕业）。
                self.engine.note_displayed(candidates.items.iter());
                Frame {
                    preedit: preedit.clone(),
                    preedit_cursor: preedit_cursor(preedit, *cursor),
                    candidates: candidates.items.iter().map(candidate_row).collect(),
                    highlighted,
                    page_index: page as u32,
                    page_count: layout.pages() as u32,
                    completion: self.sentence.clone(),
                    notice: self.notice.clone(),
                }
            }
        }
    }
}

/// Core 的 marked 分段 → 面板 preedit 段。
pub(super) fn preedit_span(segment: &qingjian_core::MarkedSegment) -> PreeditSpan {
    PreeditSpan {
        text: segment.text.clone(),
        style: preedit_style(segment.kind),
    }
}

/// `MarkedKind` → 面板 preedit 的显示提示：敲的拼音下划线，光标后的残余淡显
/// （`Plain`），被纠错改掉的原字母强调。
fn preedit_style(kind: MarkedKind) -> PreeditStyle {
    match kind {
        MarkedKind::Typed => PreeditStyle::Underline,
        MarkedKind::Rest => PreeditStyle::Plain,
        MarkedKind::Corrected => PreeditStyle::Highlight,
    }
}

/// preedit 分段拼接后，第 `cursor` 个字符边界的 UTF-8 字节偏移（`-1` 为空 preedit）。
fn preedit_cursor(preedit: &[PreeditSpan], cursor: usize) -> i32 {
    let text: String = preedit.iter().map(|span| span.text.as_str()).collect();
    if text.is_empty() {
        return -1;
    }
    cursor_byte_offset(&text, cursor)
}

/// 第 `chars` 个字符边界的字节偏移；越界时收在末尾。
fn cursor_byte_offset(text: &str, chars: usize) -> i32 {
    let offset = text
        .char_indices()
        .nth(chars)
        .map(|(index, _)| index)
        .unwrap_or(text.len());
    offset as i32
}

/// Core 候选 → 面板行：注解拼 `读音 · 词性 译文(假名)`，`from_cloud` /
/// `tone_mark` 是纯徽标。自定义短语给预览截断（与 macOS 行一致）。
fn candidate_row(candidate: &Candidate) -> CandidateRow {
    let mut parts: Vec<String> = Vec::new();
    if let Some(reading) = &candidate.reading {
        parts.push(reading.clone());
    }
    if let Some(translation) = &candidate.translation {
        for sense in translation.senses() {
            let mut text = String::new();
            if let Some(pos) = sense.part_of_speech {
                text.push_str(&format!("{pos} "));
            }
            text.push_str(&sense.text);
            if let Some(reading) = &sense.reading {
                text.push_str(&format!("({reading})"));
            }
            parts.push(text);
        }
    }
    CandidateRow {
        text: if matches!(candidate.kind, CandidateKind::Custom(_)) {
            CustomPhrase::preview(&candidate.text, 60)
        } else {
            candidate.text.clone()
        },
        annotation: parts.join(" · "),
        from_cloud: matches!(candidate.kind, CandidateKind::Cloud),
        // 问字模式答案的带声调读音：面板用它画声调徽标。
        tone_mark: candidate.reading.is_some(),
    }
}
