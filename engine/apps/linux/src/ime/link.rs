//! `SOCK_SEQPACKET` Unix socket 客户端：一收一发正好一个协议包。
//!
//! 用 `libc` 直连而不引第三方 socket crate：全程三个 syscall（socket /
//! connect / recv / send），`MSG_TRUNC` 探测截断。没有运行时依赖。

use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::io::RawFd;
use std::path::Path;

/// 一条包边界的连接。
pub struct Link {
    /// 拥有权的 fd，Drop 时关。
    fd: RawFd,
}

/// 收包缓冲固定 1 MiB（协议包上限）；`recv` 带 `MSG_TRUNC`，
/// 返回长度超过缓冲就是协议错误。
pub const PACKET_BUF: usize = super::wire::MAX_PACKET;

/// 拼 `sockaddr_un`；路径（不含结尾 NUL）超过 107 字节报错。
fn socket_addr(path: &Path) -> io::Result<(libc::sockaddr_un, u32)> {
    let path = path.as_os_str().as_bytes();
    if path.len() >= 107 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "socket 路径超过 sun_path 上限",
        ));
    }
    let mut addr = libc::sockaddr_un {
        sun_family: libc::AF_UNIX as libc::sa_family_t,
        sun_path: [0; 108],
    };
    unsafe {
        std::ptr::copy_nonoverlapping(
            path.as_ptr() as *const libc::c_char,
            addr.sun_path.as_mut_ptr(),
            path.len(),
        );
    }
    let len = (std::mem::offset_of!(libc::sockaddr_un, sun_path) + path.len() + 1) as u32;
    Ok((addr, len))
}

fn seqpacket() -> io::Result<RawFd> {
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET | libc::SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(fd)
}

/// seqpacket 监听端：给 `mock_deniald` 开发工具与测试用；服务进程自己只做客户端。
pub struct Listener {
    /// 拥有权的 fd，Drop 时关。
    fd: RawFd,

    /// 监听的文件路径，Drop 时删掉。
    path: std::path::PathBuf,
}

impl Listener {
    /// 在 `path` 上 bind + listen：已存在的同名 **socket** 先删（stale
    /// socket）；同名但不是 socket 的文件不删，报错。socket 建为 0600
    /// （与宿主侧策略一致）。父目录须已存在。
    pub fn bind(path: &Path) -> io::Result<Self> {
        let (addr, len) = socket_addr(path)?;
        if let Ok(meta) = std::fs::metadata(path) {
            use std::os::unix::fs::FileTypeExt;
            if !meta.file_type().is_socket() {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    format!("{} 已存在且不是 socket，不覆盖", path.display()),
                ));
            }
            std::fs::remove_file(path)?;
        }
        let fd = seqpacket()?;
        let bound = Listener {
            fd,
            path: path.to_path_buf(),
        };
        let ret = unsafe {
            libc::bind(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                len,
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        // same-user only：与宿主目录策略一致，socket 0600。
        unsafe { libc::fchmod(fd, 0o600) };
        if unsafe { libc::listen(fd, 4) } < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(bound)
    }

    /// 接受一个连接；`timeout` 内没人来返回 `Ok(None)`。
    pub fn accept_timeout(&self, timeout: std::time::Duration) -> io::Result<Option<Link>> {
        let mut pfd = libc::pollfd {
            fd: self.fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let ret = unsafe { libc::poll(&mut pfd, 1, timeout.as_millis() as libc::c_int) };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        if ret == 0 {
            return Ok(None);
        }
        self.accept().map(Some)
    }

    /// 接受一个连接。
    pub fn accept(&self) -> io::Result<Link> {
        let fd = unsafe {
            libc::accept4(
                self.fd,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                libc::SOCK_CLOEXEC,
            )
        };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Link { fd })
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        unsafe { libc::close(self.fd) };
        let _ = std::fs::remove_file(&self.path);
    }
}

impl Link {
    /// 连 `path` 上的 seqpacket 监听端。
    pub fn connect(path: &Path) -> io::Result<Self> {
        let (addr, len) = socket_addr(path)?;
        let fd = seqpacket()?;
        let link = Self { fd };
        let ret = unsafe {
            libc::connect(
                fd,
                &addr as *const libc::sockaddr_un as *const libc::sockaddr,
                len,
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(link)
    }

    /// 收超时（`SO_RCVTIMEO`）：主循环靠它空转做联想轮询与学习落盘的节拍。
    pub fn set_read_timeout(&self, timeout: std::time::Duration) -> io::Result<()> {
        let tv = libc::timeval {
            tv_sec: timeout.as_secs() as libc::time_t,
            tv_usec: timeout.subsec_micros() as libc::suseconds_t,
        };
        let ret = unsafe {
            libc::setsockopt(
                self.fd,
                libc::SOL_SOCKET,
                libc::SO_RCVTIMEO,
                &tv as *const libc::timeval as *const libc::c_void,
                std::mem::size_of::<libc::timeval>() as u32,
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    /// 发一个完整包；seqpacket 要么整包发出要么报错，没有部分写。
    pub fn send(&self, packet: &[u8]) -> io::Result<()> {
        let sent = unsafe {
            libc::send(
                self.fd,
                packet.as_ptr() as *const libc::c_void,
                packet.len(),
                libc::MSG_NOSIGNAL,
            )
        };
        if sent < 0 {
            return Err(io::Error::last_os_error());
        }
        if sent as usize != packet.len() {
            return Err(io::Error::new(
                io::ErrorKind::WriteZero,
                "seqpacket 包没发全",
            ));
        }
        Ok(())
    }

    /// 收一个完整包：返回包长；带 `MSG_TRUNC`，对端发的包超过缓冲返回的长度
    /// 仍是被丢掉的原始包长，调用方据此判协议错误。
    /// `Ok(0)` 是对端正常关连接。超时 / 无包返回 `WouldBlock`。
    pub fn recv(&self, buf: &mut [u8]) -> io::Result<usize> {
        let got = unsafe {
            libc::recv(
                self.fd,
                buf.as_mut_ptr() as *mut libc::c_void,
                buf.len(),
                libc::MSG_TRUNC,
            )
        };
        if got < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(got as usize)
    }
}

impl Drop for Link {
    fn drop(&mut self) {
        unsafe { libc::close(self.fd) };
    }
}
