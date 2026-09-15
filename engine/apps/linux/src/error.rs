//! 进程级错误类型：装配、配置、链路的失败都汇到这里。

use std::io;
use std::path::PathBuf;

/// Linux 壳的顶层错误。
#[derive(Debug, thiserror::Error)]
pub enum LinuxError {
    /// 配置文件读不了 / 解析失败。
    #[error("配置 {path}：{source}")]
    Config {
        /// 出错的文件。
        path: PathBuf,

        /// 底层错误（`toml::de::Error` 很大，装箱压 enum 尺寸）。
        source: Box<qingjian_platform::ConfigError>,
    },

    /// 主词库加载失败（没有词库没法干活，直接起不来）。
    #[error("词库 {path}：{source}")]
    Dictionary {
        /// 出错的文件。
        path: PathBuf,

        /// 底层错误。
        source: qingjian_dictionary::DictionaryError,
    },

    /// 语言模型加载失败。
    #[error("语言模型：{0}")]
    LanguageModel(#[from] qingjian_lm::LmError),

    /// 英文词表加载失败。
    #[error("英文词表 {path}：{source}")]
    WordList {
        /// 出错的文件。
        path: PathBuf,

        /// 底层错误。
        source: qingjian_dictionary::DictionaryError,
    },

    /// 释义表加载失败。
    #[error("释义表 {path}：{source}")]
    Glossary {
        /// 出错的文件。
        path: PathBuf,

        /// 底层错误。
        source: qingjian_translate::GlossaryError,
    },

    /// socket / IO。
    #[error("IO：{0}")]
    Io(#[from] io::Error),

    /// 自定义短语配置冲突。
    #[error("自定义短语：{0}")]
    CustomPhrases(String),
}
