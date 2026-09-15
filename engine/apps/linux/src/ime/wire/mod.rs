//! FlatBuffers 线格式：信封 + 载荷的编解码。
//!
//! 没有 flatc 生成物：编码手写在 `flatbuffers` 运行时的 builder 上（[`encode`]），
//! 解码先跑同一个运行时的 `Verifier` 做结构性有界校验、再按规范逐项做语义校验
//! （[`decode`]）。schema 文档是本 crate 根下的 `ime.fbs`。

mod decode;
mod encode;
#[cfg(test)]
mod tests;
mod verify;

pub(crate) use decode::decode;
pub use decode::{Decoded, DecodedOut, WireError, decode_outbound};
pub use encode::encode_inbound;
pub(crate) use encode::{MAX_PACKET, encode, tag};

use flatbuffers::FlatBufferBuilder;

use crate::ime::message::Outbound;

/// 编码一条出站消息；`builder` 跨调用复用（每包一次 `reset`）。
pub fn encode_message<'a>(
    builder: &'a mut FlatBufferBuilder,
    message: &Outbound,
    sequence: u64,
) -> &'a [u8] {
    encode(builder, message, sequence)
}

/// 解码一个入站包；结构不合法、方向不对、字段越界都是 [`WireError`]。
pub fn decode_message(packet: &[u8]) -> Result<Decoded, WireError> {
    decode(packet)
}

/// 字符串字段上限内截断到字符边界；含 NUL 的整段不要（规范禁止 NUL）。
pub(crate) fn bounded_str(text: &str) -> &str {
    if text.contains('\0') {
        return "";
    }
    if text.len() <= encode::MAX_STRING {
        return text;
    }
    let mut end = encode::MAX_STRING;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    &text[..end]
}
