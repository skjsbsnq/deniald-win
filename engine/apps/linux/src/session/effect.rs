//! 一次按键对组句的影响。

/// 一次按键对组句的影响。
pub(crate) enum Effect {
    /// 缓冲变了，要重建组句展示状态；带本次要上屏的文本。
    Changed(Option<String>),

    /// 只挪了高亮 / 翻页。
    Navigated,

    /// 不吃，交还宿主回注给焦点端点。
    Passthrough,
}

/// 把先行上屏的文本接到本次结果前面：协议里放行是宿主回注原按键、上屏是
/// `ImeCommitText`，分两步会让端点先收这个键再收词，所以本该放行的键改由
/// 我们连同前缀一起上屏（与 Windows Server 的 `with_prefix` 同理）。
pub(crate) fn with_prefix(prefix: Option<String>, effect: Effect, c: char) -> Effect {
    let Some(mut prefix) = prefix else {
        return effect;
    };
    match effect {
        Effect::Changed(commit) => {
            prefix.push_str(commit.as_deref().unwrap_or_default());
        }
        Effect::Navigated => {}
        Effect::Passthrough => prefix.push(c),
    }
    Effect::Changed(Some(prefix))
}
