//! `input-engine-v1` 协议客户端：消息类型（[`message`]）、FlatBuffers 线格式
//! 编解码（[`wire`]）、seqpacket 链路（[`link`]）与服务循环（[`serve`]）。

mod link;
pub mod message;
mod serve;
pub mod wire;

pub use self::link::{Link, Listener, PACKET_BUF};
pub use self::message::{Inbound, Outbound};
pub use self::serve::{Service, socket_path};
