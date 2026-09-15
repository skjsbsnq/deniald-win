//! XDG 目录解析：`XDG_*` 环境变量缺省时按规范回落 `~/.config` 等。

use std::path::PathBuf;

/// `$XDG_CONFIG_HOME/qingjian/config.toml`。
pub fn config_file() -> PathBuf {
    config_home().join("qingjian/config.toml")
}

/// `$XDG_DATA_HOME/qingjian`：学习数据、用户词库、词汇记录等。
pub fn user_dir() -> PathBuf {
    data_home().join("qingjian")
}

/// `$XDG_STATE_HOME/qingjian/logs`：运行日志目录。
pub fn log_dir() -> PathBuf {
    state_home().join("qingjian/logs")
}

/// 随包数据根目录（词库 / 释义表 / 语言模型 / emoji / 领域词库）。
/// `QINGJIAN_DATA_DIR` 优先（开发与打包都能覆盖），否则找 exe 旁的标准位置。
pub fn bundled_root() -> PathBuf {
    if let Some(dir) = std::env::var_os("QINGJIAN_DATA_DIR") {
        return PathBuf::from(dir);
    }
    if let Ok(exe) = std::env::current_exe()
        && let Some(prefix) = exe.parent().and_then(|dir| dir.parent())
    {
        for share in ["share/qingjian", "lib/qingjian"] {
            let dir = prefix.join(share);
            if dir.is_dir() {
                return dir;
            }
        }
        let sibling = exe.with_file_name("data");
        if sibling.is_dir() {
            return sibling;
        }
    }
    // 开发布局：从仓库根跑时 `data/` 就在工作目录下。
    PathBuf::from("data")
}

/// `$XDG_*` 环境变量：存在且为绝对路径才用。
fn xdg(var: &str) -> Option<PathBuf> {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|dir| dir.is_absolute())
}

fn config_home() -> PathBuf {
    xdg("XDG_CONFIG_HOME").unwrap_or_else(|| {
        home().map_or_else(|| PathBuf::from(".config"), |home| home.join(".config"))
    })
}

fn data_home() -> PathBuf {
    xdg("XDG_DATA_HOME").unwrap_or_else(|| {
        home().map_or_else(
            || PathBuf::from(".local/share"),
            |home| home.join(".local/share"),
        )
    })
}

fn state_home() -> PathBuf {
    xdg("XDG_STATE_HOME").unwrap_or_else(|| {
        home().map_or_else(
            || PathBuf::from(".local/state"),
            |home| home.join(".local/state"),
        )
    })
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}
