//! 配置热加载：空闲时看 `config.toml` 的 mtime，改了就重读并应用
//! （与 Windows Server 的 `dispatch/reload` 对齐）。便宜的设置无条件重设；
//! 云联想 / 附加词库只在对应分节变了才重建。
//! `ImeReloadConfiguration` 走同一条路：重读文件 + 应用随包快照条目。

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

use qingjian_core::{Engine, NoGlossFiller, NoPredictor};
use qingjian_platform::{Config, extra_dictionaries};
use qingjian_predict::{CloudGlossFiller, CloudPredictor, PredictConfig};

use super::Session;
use super::config::SessionConfig;

/// 看配置文件 mtime 的最短间隔；主循环空闲时按它等。
pub(super) const CONFIG_POLL_INTERVAL: Duration = Duration::from_secs(1);

/// 热加载进行态；`None` 表示不热加载（测试）。
pub(crate) struct ConfigReload {
    /// 配置文件路径。
    config_path: PathBuf,

    /// 上次看 mtime 的时间。
    last_check: Instant,

    /// 随包领域词库目录。
    bundled_dicts_dir: Option<PathBuf>,

    /// 用户数据目录。
    user_dir: Option<PathBuf>,

    /// 上次见到的 mtime。
    last_mtime: Option<SystemTime>,

    /// 上次应用的 `[predict]`。
    applied_predict: PredictConfig,

    /// 上次应用的 `[dictionaries]`。
    applied_dictionaries: qingjian_platform::DictionariesConfig,
}

fn mtime(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path)
        .and_then(|meta| meta.modified())
        .ok()
}

/// 按 `[predict]` 接云联想与释义兜底；关着或缺密钥就退回本地实现。
/// 启动与热加载共用。
pub fn attach_cloud(engine: &mut Engine, predict: &PredictConfig) {
    if !predict.enabled {
        tracing::info!("云联想未开启（[predict] enabled = false）");
        engine.set_predictor(Box::new(NoPredictor));
        engine.set_gloss_filler(Box::new(NoGlossFiller));
        return;
    }
    match CloudPredictor::new(predict) {
        Ok(predictor) => {
            engine.set_predictor(Box::new(predictor));
            tracing::info!(model = %predict.model, "云联想已接入");
        }
        Err(error) => {
            tracing::warn!(%error, "云联想接入失败（缺 API key？），退回本地候选");
            engine.set_predictor(Box::new(NoPredictor));
        }
    }
    match CloudGlossFiller::new(predict) {
        Ok(filler) => engine.set_gloss_filler(Box::new(filler)),
        Err(error) => {
            tracing::warn!(%error, "释义兜底未启用");
            engine.set_gloss_filler(Box::new(NoGlossFiller));
        }
    }
}

impl Session {
    /// 开启配置文件热加载。
    pub fn watch_config(
        &mut self,
        config: &Config,
        config_path: PathBuf,
        bundled_dicts_dir: Option<PathBuf>,
        user_dir: Option<PathBuf>,
    ) {
        self.reload = Some(ConfigReload {
            last_mtime: mtime(&config_path),
            config_path,
            last_check: Instant::now(),
            bundled_dicts_dir,
            user_dir,
            applied_predict: config.predict.clone(),
            applied_dictionaries: config.dictionaries.clone(),
        });
    }

    /// 空闲时调；一秒内只真正看一次文件。解析失败保持原配置，mtime 照记。
    ///
    /// 注意权衡：重读 + 应用配置（`Config::load` / 附加词库 / `attach_cloud`
    /// 起线程）是单线程服务循环上的同步工作，期间到达的按键会排队等应答。
    /// 可接受的点：mtime 没变时只做一次 `stat`；真触发 reload 是罕见事件
    /// 且自愈（超时的键由宿主回注）。要更稳得把重应用拆到空闲段——目前不拆。
    pub fn poll_config_reload(&mut self) {
        let Some(reload) = &mut self.reload else {
            return;
        };
        if reload.last_check.elapsed() < CONFIG_POLL_INTERVAL {
            return;
        }
        reload.last_check = Instant::now();
        let current = mtime(&reload.config_path);
        if current == reload.last_mtime {
            return;
        }
        reload.last_mtime = current;
        let path = reload.config_path.clone();
        match Config::load(&path) {
            Ok(config) => {
                self.apply_config(&config);
                tracing::info!("配置已热加载");
            }
            Err(error) => tracing::error!(%error, "配置热加载解析失败，保持原配置"),
        }
    }

    /// `ImeReloadConfiguration`：重读配置文件并应用随包快照条目，原子生效。
    /// 与 `poll_config_reload` 同一条同步路径：载荷分派内做 `Config::load`
    /// + 词库 / 云重建，期间到达的按键会等——罕见且自愈，按现状接受。
    pub(super) fn reload_configuration(&mut self, entries: &[crate::ime::message::ConfigEntry]) {
        if let Some(reload) = &self.reload {
            let path = reload.config_path.clone();
            match Config::load(&path) {
                Ok(config) => self.apply_config(&config),
                Err(error) => {
                    tracing::error!(%error, "配置重载解析失败，保持原配置")
                }
            }
        }
        self.apply_config_snapshot(entries);
    }

    /// 应用新配置。学习语言变了仍需重启（要换释义表 / 等级表）。
    pub fn apply_config(&mut self, config: &Config) {
        self.engine.set_fuzzy(config.fuzzy);
        self.engine.set_shuangpin(config.general.shuangpin());
        self.engine.set_zhuyin_mode(config.general.zhuyin);
        self.engine.set_mode_keys(config.shortcut.mode);
        self.engine
            .set_full_width_punctuation(config.general.full_width_punctuation);
        if let Err(error) = self
            .engine
            .set_custom_phrases(config.custom_phrases.clone())
        {
            tracing::warn!(%error, "自定义短语有冲突，没应用");
        }
        self.config = SessionConfig::from(config);
        self.apply_model_config(&config.model);

        let Some(reload) = &mut self.reload else {
            return;
        };
        if config.predict != reload.applied_predict {
            attach_cloud(&mut self.engine, &config.predict);
            reload.applied_predict = config.predict.clone();
        }
        if config.dictionaries != reload.applied_dictionaries {
            let user_dicts = reload.user_dir.as_ref().map(|dir| dir.join("dicts"));
            let dicts = extra_dictionaries::load(
                reload.bundled_dicts_dir.as_deref(),
                user_dicts.as_deref(),
                &config.dictionaries,
            );
            tracing::info!(count = dicts.len(), "附加词库已热重装");
            self.engine.set_extra_dictionaries(dicts);
            reload.applied_dictionaries = config.dictionaries.clone();
        }
    }

    /// 宿主随激活 / 重载下发的配置快照：键名即 `config.toml` 的字段路径
    /// （`page_size`、`shuangpin`、`zhuyin`、`english_candidates`、
    /// `full_width_punctuation`、`legacy_direct`、`cloud`），认识的覆盖、
    /// 不认识的记下日志忽略。快照只改会话层参数与引擎模式开关，
    /// 不改数据文件来源。
    pub(super) fn apply_config_snapshot(&mut self, entries: &[crate::ime::message::ConfigEntry]) {
        for entry in entries {
            let value = entry.value.trim();
            match entry.key.as_str() {
                "page_size" => match value.parse::<usize>() {
                    Ok(size) if size > 0 => self.config.page_size = size.min(9),
                    _ => tracing::warn!(%value, "配置项 page_size 不是正整数，忽略"),
                },
                "shuangpin" => {
                    let scheme = value.parse().ok();
                    self.engine.set_shuangpin(scheme);
                    self.config.shuangpin = scheme;
                }
                "zhuyin" => {
                    let on = truthy(value);
                    self.engine.set_zhuyin_mode(on);
                    self.config.zhuyin = on;
                }
                "english_candidates" => self.config.english_candidates = truthy(value),
                "full_width_punctuation" => {
                    let on = truthy(value);
                    self.config.full_width = on;
                    self.engine.set_full_width_punctuation(on);
                }
                "english_full_width_punctuation" => self.config.english_full_width = truthy(value),
                "legacy_direct" => self.legacy_direct = truthy(value),
                "cloud" => {
                    self.cloud_override = match value {
                        "on" | "enable" | "true" | "1" => Some(true),
                        "off" | "disable" | "false" | "0" => Some(false),
                        _ => None,
                    };
                }
                other => tracing::debug!(key = other, "不认识的配置快照键，忽略"),
            }
        }
    }
}

/// 快照值里的布尔写法。
fn truthy(value: &str) -> bool {
    matches!(value, "on" | "true" | "yes" | "1")
}
