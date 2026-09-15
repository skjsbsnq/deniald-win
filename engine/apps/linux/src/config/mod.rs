//! 配置与数据路径：XDG 目录约定 + TOML 配置加载。
//!
//! - 配置：`$XDG_CONFIG_HOME/qingjian/config.toml`（缺省 `~/.config`）。
//! - 用户数据（学习 / 日志 / 用户词库）：`$XDG_DATA_HOME/qingjian`
//!   （缺省 `~/.local/share`）。
//! - 运行日志：`$XDG_STATE_HOME/qingjian/logs`（缺省 `~/.local/state`）。
//! - 随包数据：环境变量 `QINGJIAN_DATA_DIR`，否则依次找
//!   `exe/../share/qingjian`、`exe/../lib/qingjian`、`exe` 同级 `data/`、
//!   工作目录 `data/`。

mod paths;

pub use self::paths::*;

use std::path::PathBuf;

use qingjian_platform::Config;

use crate::error::LinuxError;

/// 读配置文件；不存在时写一份模板再按缺省配置跑（与 Windows / macOS 壳一致：
/// 配置文件是唯一事实源）。返回 `(配置, 路径)`。
pub fn load_config() -> Result<(Config, PathBuf), LinuxError> {
    let path = config_file();
    if let Some(dir) = path.parent()
        && let Err(error) = std::fs::create_dir_all(dir)
    {
        tracing::warn!(%error, dir = %dir.display(), "建配置目录失败");
    }
    match Config::write_template_if_missing(&path) {
        Ok(true) => tracing::info!(path = %path.display(), "已写入配置模板"),
        Ok(false) => {}
        Err(error) => tracing::warn!(%error, "写配置模板失败"),
    }
    let config = Config::load(&path).map_err(|source| LinuxError::Config {
        path: path.clone(),
        source: Box::new(source),
    })?;
    Ok((config, path))
}
