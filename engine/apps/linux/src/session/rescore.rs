//! 本地整句模型：后台加载、停键后请求重排、结果到了重查并重画当前页。
//! 节拍与常数与 Windows Server 的 `dispatch/rescore`（及 macOS 壳的
//! `RescoreMonitor`）相同：按键路径只跑词级模型，模型的意见在停键 80ms
//! 后请求、几十毫秒后到；用户翻过页或动过高亮就不打扰。

use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, TryRecvError, channel};
use std::time::{Duration, Instant};

use qingjian_core::CandidateLayout;
use qingjian_neural::CharScorer;

use super::Session;
use super::composed::Composed;

/// 停键多久才请求重排：比一般的击键间隔短，连着敲时不请求。
const DEBOUNCE: Duration = Duration::from_millis(80);

/// 轮询间隔：模型一次几十毫秒。
const POLL_INTERVAL: Duration = Duration::from_millis(20);

/// 最长等多久；后台线程卡住时兜底。
const MAX_WAIT: Duration = Duration::from_secs(2);

/// 重排的进行态。
#[derive(Debug, Default)]
pub(crate) struct RescoreState {
    /// 最近一次缓冲变化的时间；有它表示在等防抖到点。
    wanted_since: Option<Instant>,

    /// 本轮请求发出的时间；有它表示在等后台结果。
    polling_since: Option<Instant>,
}

impl RescoreState {
    /// 又敲了一键：重新计时。
    pub(super) fn schedule(&mut self) {
        self.wanted_since = Some(Instant::now());
    }

    /// 防抖到点了没。
    fn debounce_elapsed(&self) -> bool {
        self.wanted_since
            .is_some_and(|since| since.elapsed() >= DEBOUNCE)
    }

    /// 请求已发出：开始等结果。
    fn start_polling(&mut self) {
        self.wanted_since = None;
        self.polling_since = Some(Instant::now());
    }

    fn polling(&self) -> bool {
        self.polling_since.is_some()
    }

    /// 等结果等太久了。
    fn expired(&self) -> bool {
        self.polling_since
            .is_some_and(|since| since.elapsed() > MAX_WAIT)
    }

    /// 什么都不等。
    pub(super) fn stop(&mut self) {
        self.wanted_since = None;
        self.polling_since = None;
    }

    /// 下一次该来 tick 的时长；什么都不等为 `None`。
    pub(super) fn next_deadline(&self) -> Option<Duration> {
        if self.polling_since.is_some() {
            return Some(POLL_INTERVAL);
        }
        self.wanted_since
            .map(|since| DEBOUNCE.saturating_sub(since.elapsed()))
    }
}

/// 一次进行中的模型加载。
pub(crate) struct ModelLoader {
    result: Receiver<Result<CharScorer, qingjian_neural::NeuralError>>,
}

/// 一次加载的结局。
enum Loaded {
    /// 还在加载。
    Pending,

    /// 加载好了（或失败了）。装箱：模型结构体比另两个变体大得多。
    Done(Box<Result<CharScorer, qingjian_neural::NeuralError>>),

    /// 加载线程没了（起不来 / panic）。
    Gone,
}

impl ModelLoader {
    /// 起线程加载 `path`（`.qjm` 或三件套目录）并预热一次；线程起不来返回 `None`。
    pub(super) fn spawn(path: &Path) -> Option<Self> {
        let path: PathBuf = path.to_path_buf();
        let (tx, result) = channel();
        let spawned = std::thread::Builder::new()
            .name("qingjian-model-load".to_owned())
            .spawn(move || {
                let started = Instant::now();
                let loaded = CharScorer::load(&path).and_then(|scorer| {
                    scorer.score("", &["的"])?;
                    Ok(scorer)
                });
                if loaded.is_ok() {
                    tracing::info!(
                        path = %path.display(),
                        total_ms = started.elapsed().as_millis(),
                        "本地整句模型已加载并预热"
                    );
                }
                let _ = tx.send(loaded);
            });
        match spawned {
            Ok(_) => Some(Self { result }),
            Err(error) => {
                tracing::warn!(%error, "起不了模型加载线程，本地整句模型不用");
                None
            }
        }
    }

    /// 看一眼有没有结果，不阻塞。
    fn poll(&self) -> Loaded {
        match self.result.try_recv() {
            Ok(result) => Loaded::Done(Box::new(result)),
            Err(TryRecvError::Empty) => Loaded::Pending,
            Err(TryRecvError::Disconnected) => Loaded::Gone,
        }
    }
}

impl Session {
    /// 启动时：记下模型文件，按 `[model] enabled` 决定要不要加载。
    pub fn configure_local_model(
        &mut self,
        model_path: Option<PathBuf>,
        config: &qingjian_platform::LocalModelConfig,
    ) {
        self.model_path = model_path;
        self.applied_model = config.clone();
        if config.enabled {
            self.load_local_model();
        }
    }

    /// 配置热加载：`[model]` 变了才重载 / 卸载。
    pub(super) fn apply_model_config(&mut self, config: &qingjian_platform::LocalModelConfig) {
        if *config == self.applied_model {
            return;
        }
        self.applied_model = config.clone();
        if config.enabled {
            self.load_local_model();
        } else {
            self.unload_local_model();
        }
    }

    /// 在后台线程加载模型；没有模型文件就什么都不做。
    fn load_local_model(&mut self) {
        if self.model_loader.is_some() || self.engine.has_sentence_scorer() {
            return;
        }
        let Some(path) = &self.model_path else {
            tracing::info!("没有本地整句模型文件，不重排");
            return;
        };
        self.model_loader = ModelLoader::spawn(path);
    }

    /// 卸掉模型（配置关掉）。
    fn unload_local_model(&mut self) {
        self.model_loader = None;
        self.engine.set_async_sentence_scorer(None);
        self.rescore.stop();
        tracing::info!("本地整句模型已卸载（[model] enabled = false）");
    }

    /// 加载线程有结果了就接到 Engine 上；每次按键 / tick 顺手看一眼，不阻塞。
    pub(super) fn attach_loaded_model(&mut self) {
        let Some(loader) = &self.model_loader else {
            return;
        };
        match loader.poll() {
            Loaded::Pending => {}
            Loaded::Done(result) => {
                match *result {
                    Ok(scorer) => {
                        self.engine
                            .set_async_sentence_scorer(Some(Box::new(scorer)));
                        // 模型上线了：日志里补一条会话信息，之后的条目知道重排开着
                        self.engine.log_session(env!("CARGO_PKG_VERSION"), "linux");
                    }
                    Err(error) => tracing::warn!(%error, "本地整句模型加载失败，不重排"),
                }
                self.model_loader = None;
            }
            Loaded::Gone => self.model_loader = None,
        }
    }

    /// 组句结束：什么都不等了；应用前文也作废（下一段组句端点会再送）。
    pub(super) fn stop_rescoring(&mut self) {
        self.rescore.stop();
        self.engine.set_rescoring_context(None);
    }

    /// 缓冲变化之后：有整句路径等着打分就起防抖计时，否则停下。
    pub(super) fn schedule_rescoring(&mut self) {
        if self.engine.rescoring_pending() {
            self.rescore.schedule();
        } else {
            self.rescore.stop();
        }
    }

    /// 防抖到点就发请求；在等结果就收一次，收到了重查并让调用方重发当前页帧。
    /// 返回 `true` 表示候选顺序可能变了、要重发帧。
    pub(super) fn advance_rescoring(&mut self) -> bool {
        if self.engine.composition().is_empty() {
            self.rescore.stop();
            return false;
        }
        if self.rescore.debounce_elapsed() {
            if self.engine.request_rescoring() {
                self.rescore.start_polling();
            } else {
                self.rescore.stop();
            }
        }
        if !self.rescore.polling() {
            return false;
        }
        if !self.engine.poll_rescoring() {
            // 等太久多半是前文变了（上屏后接着打下一段）、结果作废
            if self.rescore.expired() {
                tracing::debug!("等本地整句模型超时，本轮不重排");
                self.rescore.stop();
            }
            return false;
        }
        self.rescore.stop();
        if self.highlight >= self.config.page_size || self.navigated {
            return false;
        }
        self.requery_rescored();
        true
    }

    /// 分回来了：按重排后的顺序重建候选布局，云端词与整句补全留着。
    fn requery_rescored(&mut self) {
        let Ok(query) = self.engine.query() else {
            return;
        };
        let Some(Composed::Candidates {
            preedit,
            cursor,
            layout,
        }) = self.composed.as_mut()
        else {
            return;
        };
        let cloud = layout.cloud().to_vec();
        let mut rebuilt = CandidateLayout::new(
            query.candidates.items.clone(),
            self.config.page_size,
            self.config.cloud_slots,
        );
        if !cloud.is_empty() {
            rebuilt.set_cloud(cloud);
        }
        *layout = rebuilt;
        *preedit = query
            .marked_segments()
            .iter()
            .map(super::composed::preedit_span)
            .collect();
        *cursor = query.marked_cursor();
        // 前文在结果回来之前换过：这次查询又记下了一批要打分的，再来一轮
        self.schedule_rescoring();
    }
}
