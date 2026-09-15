//! 激活分组：协议规定 `ImeActivate` 与每段连续 `ImeEditorUpdate` 各成一组，
//! `ImeDone` 落地才原子生效——组没关之前编辑器状态只暂存在这里，不进 Engine。

use crate::ime::message::{ConfigEntry, EditorState, Endpoint};

/// 一次打开的激活（当前 serial + 端点能力 + 最新编辑器状态）。
#[derive(Debug)]
pub(crate) struct Active {
    /// 激活世代。
    pub serial: u64,

    /// 端点能力。
    pub endpoint: Endpoint,

    /// 最近一次组生效后的编辑器状态。
    pub editor: EditorState,
}

/// 还没等到 `ImeDone` 的一组状态消息。
#[derive(Debug)]
pub(crate) enum Pending {
    /// `ImeActivate` 开的组（`ImeEditorUpdate` 在组内更新暂存的编辑器状态）。
    Activate {
        /// 激活世代。
        serial: u64,

        /// 端点能力。
        endpoint: Endpoint,

        /// 暂存的编辑器状态。
        editor: EditorState,

        /// 配置快照。
        config: Vec<ConfigEntry>,
    },

    /// 一段连续 `ImeEditorUpdate` 组成的组：后到的整体替换先到的。
    Updates {
        /// 激活世代。
        serial: u64,

        /// 暂存的编辑器状态。
        editor: EditorState,
    },
}

impl Pending {
    /// 组属于的激活世代。
    pub(crate) fn serial(&self) -> u64 {
        match self {
            Self::Activate { serial, .. } | Self::Updates { serial, .. } => *serial,
        }
    }
}
