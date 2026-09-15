//! 青简 Linux 壳：常驻输入引擎服务进程。
//!
//! 装配平台无关的 `qingjian_core::Engine`（词库 / 学习 / 翻译 / 联想），
//! 作为 `input-engine-v1` 协议的客户端接宿主合成器的
//! `$XDG_RUNTIME_DIR/denial/ime.sock`（`SOCK_SEQPACKET`）。
//!
//! - [`ime`]：协议层——自撰 `ime.fbs` 契约文档 + 手写在 `flatbuffers`
//!   运行时上的有界编解码 + seqpacket 链路。与宿主仓库零代码共享，
//!   唯一共享物是协议规范文档。
//! - [`keys`]：evdev 键码 + 修饰掩码 → 字符 / 功能键（xkbcommon，兜底 US 表）。
//! - [`session`]：激活 / 按键 / 候选帧的分派，职责划分对应 Windows Server
//!   的 `dispatch`。
//! - [`assembly`]：Engine 装配（词库、学习数据、释义表、语言模型、云联想）。
//! - [`config`]：XDG 路径与 TOML 配置加载。

pub mod assembly;
pub mod config;
pub mod error;
pub mod ime;
pub mod keys;
pub mod session;

pub use error::LinuxError;
