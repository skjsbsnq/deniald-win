//! Persistent native audio and monitor-brightness controls.
//!
//! Input callbacks only enqueue bounded, coalescible commands. PulseAudio and
//! DDC/CI traffic stays on dedicated workers because either native library can
//! block while reconnecting or waiting for hardware.

use std::collections::HashMap;
use std::error::Error;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use libloading::Library;
use tracing::{info, warn};
use zbus::blocking::connection::Builder as ConnectionBuilder;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::OwnedObjectPath;

const CONTROL_STEP: f64 = 0.05;
const MAX_AUDIO_LEVEL: f64 = 1.4;
const DDC_COALESCE_WINDOW: Duration = Duration::from_millis(24);
const COMMAND_QUEUE_CAPACITY: usize = 128;
const EVENT_QUEUE_CAPACITY: usize = 64;
const MAX_AUDIO_STREAMS: usize = 256;
const MAX_AUDIO_STREAM_NAME_BYTES: usize = 1024;
const MAX_BRIGHTNESS_CONNECTOR_BYTES: usize = 128;
const BACKLIGHT_CLASS_ROOT: &str = "/sys/class/backlight";
const DRM_CLASS_ROOT: &str = "/sys/class/drm";
const MIN_BACKLIGHT_RAW: u32 = 1;
const LOGIND_SERVICE: &str = "org.freedesktop.login1";
const LOGIND_MANAGER_OBJECT: &str = "/org/freedesktop/login1";
const LOGIND_MANAGER_INTERFACE: &str = "org.freedesktop.login1.Manager";
const LOGIND_SESSION_INTERFACE: &str = "org.freedesktop.login1.Session";
const LOGIND_DBUS_TIMEOUT: Duration = Duration::from_millis(500);
const DDC_RETRY_INTERVAL: Duration = Duration::from_secs(5);
const MAX_DDC_INIT_ATTEMPTS: usize = 5;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AudioStreamState {
    pub(super) id: u32,
    pub(super) name: String,
    pub(super) level_percent: u8,
    pub(super) muted: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum SystemControlEvent {
    AudioLevel { level: f64, request_serial: u32 },
    AudioStreams(Vec<AudioStreamState>),
    BrightnessLevel { monitor_id: i64, level: f64 },
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) enum AudioRequest {
    ReadLevel,
    SetLevel { level: f64, request_serial: u32 },
    RequestStreams,
    SetStreamLevel { stream_id: u32, level: f64 },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum AudioRequestDecodeError {
    InvalidSize(usize),
    UnsupportedCommand(u8),
}

impl fmt::Display for AudioRequestDecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSize(size) => write!(formatter, "invalid audio packet size {size}"),
            Self::UnsupportedCommand(command) => {
                write!(formatter, "unsupported audio command {command}")
            }
        }
    }
}

impl Error for AudioRequestDecodeError {}

pub(super) fn decode_audio_request(packet: &[u8]) -> Result<AudioRequest, AudioRequestDecodeError> {
    match packet {
        [0] => Ok(AudioRequest::ReadLevel),
        [1, percent, serial @ ..] if serial.len() == size_of::<u32>() => {
            let request_serial = u32::from_le_bytes(
                serial
                    .try_into()
                    .expect("audio request serial length was checked"),
            );
            Ok(AudioRequest::SetLevel {
                level: f64::from((*percent).min(100)) / 100.0,
                request_serial,
            })
        }
        [2] => Ok(AudioRequest::RequestStreams),
        [3, id @ ..] if id.len() == size_of::<u32>() + 1 => {
            let stream_id = u32::from_le_bytes(
                id[..size_of::<u32>()]
                    .try_into()
                    .expect("audio stream identity length was checked"),
            );
            Ok(AudioRequest::SetStreamLevel {
                stream_id,
                level: f64::from(id[size_of::<u32>()].min(100)) / 100.0,
            })
        }
        [command, ..] if matches!(*command, 0..=3) || packet.is_empty() => {
            Err(AudioRequestDecodeError::InvalidSize(packet.len()))
        }
        [command, ..] => Err(AudioRequestDecodeError::UnsupportedCommand(*command)),
        [] => Err(AudioRequestDecodeError::InvalidSize(0)),
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum BrightnessRequest {
    Read {
        connector: String,
        monitor_id: i64,
    },
    Set {
        connector: String,
        monitor_id: i64,
        level: f64,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum BrightnessRequestDecodeError {
    InvalidSize(usize),
    UnsupportedCommand(u8),
    InvalidMonitorId(i64),
    InvalidConnector,
}

impl fmt::Display for BrightnessRequestDecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSize(size) => write!(formatter, "invalid brightness packet size {size}"),
            Self::UnsupportedCommand(command) => {
                write!(formatter, "unsupported brightness command {command}")
            }
            Self::InvalidMonitorId(monitor_id) => {
                write!(formatter, "invalid brightness monitor id {monitor_id}")
            }
            Self::InvalidConnector => write!(formatter, "invalid brightness connector"),
        }
    }
}

impl Error for BrightnessRequestDecodeError {}

pub(super) fn decode_brightness_request(
    packet: &[u8],
) -> Result<BrightnessRequest, BrightnessRequestDecodeError> {
    const HEADER_BYTES: usize = 12;
    if packet.len() < HEADER_BYTES {
        return Err(BrightnessRequestDecodeError::InvalidSize(packet.len()));
    }
    let command = packet[0];
    if command > 1 {
        return Err(BrightnessRequestDecodeError::UnsupportedCommand(command));
    }
    let monitor_id = i64::from_le_bytes(
        packet[1..9]
            .try_into()
            .expect("brightness monitor id has a fixed packet width"),
    );
    if monitor_id < 0 {
        return Err(BrightnessRequestDecodeError::InvalidMonitorId(monitor_id));
    }
    let connector_length = usize::from(u16::from_le_bytes(
        packet[10..12]
            .try_into()
            .expect("brightness connector length has a fixed packet width"),
    ));
    if connector_length == 0
        || connector_length > MAX_BRIGHTNESS_CONNECTOR_BYTES
        || packet.len() != HEADER_BYTES + connector_length
    {
        return Err(BrightnessRequestDecodeError::InvalidSize(packet.len()));
    }
    let connector = std::str::from_utf8(&packet[HEADER_BYTES..])
        .ok()
        .filter(|value| !value.contains('\0'))
        .ok_or(BrightnessRequestDecodeError::InvalidConnector)?
        .to_owned();
    match command {
        0 => Ok(BrightnessRequest::Read {
            connector,
            monitor_id,
        }),
        1 => Ok(BrightnessRequest::Set {
            connector,
            monitor_id,
            level: f64::from(packet[9].min(100)) / 100.0,
        }),
        _ => unreachable!("brightness command was range checked"),
    }
}

enum AudioCommand {
    ReadLevel,
    SetLevel { level: f64, request_serial: u32 },
    Adjust(f64),
    ToggleMute,
    RequestStreams,
    SetStreamLevel { stream_id: u32, level: f64 },
    Stop,
}

enum BrightnessCommand {
    Read {
        connector: String,
        monitor_id: i64,
    },
    Set {
        connector: String,
        monitor_id: i64,
        level: f64,
    },
    Adjust {
        connector: String,
        monitor_id: i64,
        delta: f64,
    },
    Stop,
}

/// Process-lifetime handles used by the compositor input path.
pub(super) struct SystemControls {
    audio_commands: SyncSender<AudioCommand>,
    brightness_commands: SyncSender<BrightnessCommand>,
    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    events: Receiver<SystemControlEvent>,
    audio_worker: Option<JoinHandle<()>>,
    brightness_worker: Option<JoinHandle<()>>,
}

impl SystemControls {
    pub(super) fn new() -> io::Result<Self> {
        let (events_tx, events) = mpsc::sync_channel(EVENT_QUEUE_CAPACITY);
        let (audio_commands, audio_rx) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
        let audio_events = events_tx.clone();
        let subscription_commands = audio_commands.clone();
        let audio_worker = thread::Builder::new()
            .name("denial-audio".into())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("audio");
                run_audio_worker(audio_rx, audio_events, subscription_commands);
            })?;

        let (brightness_commands, brightness_rx) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
        let brightness_worker = match thread::Builder::new()
            .name("denial-brightness".into())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("brightness");
                run_brightness_worker(brightness_rx, events_tx);
            }) {
            Ok(worker) => worker,
            Err(error) => {
                let _ = audio_commands.send(AudioCommand::Stop);
                let _ = audio_worker.join();
                return Err(error);
            }
        };

        Ok(Self {
            audio_commands,
            brightness_commands,
            events,
            audio_worker: Some(audio_worker),
            brightness_worker: Some(brightness_worker),
        })
    }

    pub(super) fn volume_up(&self) {
        self.adjust_audio(CONTROL_STEP);
    }

    pub(super) fn volume_down(&self) {
        self.adjust_audio(-CONTROL_STEP);
    }

    pub(super) fn toggle_mute(&self) {
        let _ = self.audio_commands.try_send(AudioCommand::ToggleMute);
    }

    pub(super) fn handle_audio_request(&self, request: AudioRequest) {
        let command = match request {
            AudioRequest::ReadLevel => AudioCommand::ReadLevel,
            AudioRequest::SetLevel {
                level,
                request_serial,
            } => AudioCommand::SetLevel {
                level,
                request_serial,
            },
            AudioRequest::RequestStreams => AudioCommand::RequestStreams,
            AudioRequest::SetStreamLevel { stream_id, level } => {
                AudioCommand::SetStreamLevel { stream_id, level }
            }
        };
        let _ = self.audio_commands.try_send(command);
    }

    pub(super) fn handle_brightness_request(&self, request: BrightnessRequest) {
        let command = match request {
            BrightnessRequest::Read {
                connector,
                monitor_id,
            } => BrightnessCommand::Read {
                connector,
                monitor_id,
            },
            BrightnessRequest::Set {
                connector,
                monitor_id,
                level,
            } => BrightnessCommand::Set {
                connector,
                monitor_id,
                level,
            },
        };
        let _ = self.brightness_commands.try_send(command);
    }

    fn adjust_audio(&self, delta: f64) {
        let _ = self.audio_commands.try_send(AudioCommand::Adjust(delta));
    }

    pub(super) fn brightness_up(&self, connector: String, monitor_id: i64) {
        self.adjust_brightness(connector, monitor_id, CONTROL_STEP);
    }

    pub(super) fn brightness_down(&self, connector: String, monitor_id: i64) {
        self.adjust_brightness(connector, monitor_id, -CONTROL_STEP);
    }

    fn adjust_brightness(&self, connector: String, monitor_id: i64, delta: f64) {
        let _ = self
            .brightness_commands
            .try_send(BrightnessCommand::Adjust {
                connector,
                monitor_id,
                delta,
            });
    }

    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    pub(super) fn try_event(&self) -> Option<SystemControlEvent> {
        self.events.try_recv().ok()
    }
}

impl Drop for SystemControls {
    fn drop(&mut self) {
        let _ = self.audio_commands.send(AudioCommand::Stop);
        let _ = self.brightness_commands.send(BrightnessCommand::Stop);
        if self
            .audio_worker
            .take()
            .is_some_and(|worker| worker.join().is_err())
        {
            warn!("native audio worker panicked during shutdown");
        }
        if self
            .brightness_worker
            .take()
            .is_some_and(|worker| worker.join().is_err())
        {
            warn!("native brightness worker panicked during shutdown");
        }
    }
}

#[repr(C)]
struct PaThreadedMainloop {
    _private: [u8; 0],
}

#[repr(C)]
struct PaMainloopApi {
    _private: [u8; 0],
}

#[repr(C)]
struct PaContext {
    _private: [u8; 0],
}

#[repr(C)]
struct PaOperation {
    _private: [u8; 0],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct PaSampleSpec {
    format: c_int,
    rate: u32,
    channels: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct PaChannelMap {
    channels: u8,
    map: [c_int; 32],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct PaCVolume {
    channels: u8,
    values: [u32; 32],
}

#[repr(C)]
struct PaServerInfo {
    user_name: *const c_char,
    host_name: *const c_char,
    server_version: *const c_char,
    server_name: *const c_char,
    sample_spec: PaSampleSpec,
    default_sink_name: *const c_char,
    default_source_name: *const c_char,
    cookie: u32,
    channel_map: PaChannelMap,
}

#[repr(C)]
struct PaSinkInfoPrefix {
    name: *const c_char,
    index: u32,
    description: *const c_char,
    sample_spec: PaSampleSpec,
    channel_map: PaChannelMap,
    owner_module: u32,
    volume: PaCVolume,
    mute: c_int,
}

#[repr(C)]
struct PaProplist {
    _private: [u8; 0],
}

#[repr(C)]
struct PaSinkInputInfoPrefix {
    index: u32,
    name: *const c_char,
    owner_module: u32,
    client: u32,
    sink: u32,
    sample_spec: PaSampleSpec,
    channel_map: PaChannelMap,
    volume: PaCVolume,
    buffer_usec: u64,
    sink_usec: u64,
    resample_method: *const c_char,
    driver: *const c_char,
    mute: c_int,
    proplist: *mut PaProplist,
}

type ContextStateCallback = Option<unsafe extern "C" fn(*mut PaContext, *mut c_void)>;
type ServerInfoCallback =
    Option<unsafe extern "C" fn(*mut PaContext, *const PaServerInfo, *mut c_void)>;
type SinkInfoCallback =
    Option<unsafe extern "C" fn(*mut PaContext, *const PaSinkInfoPrefix, c_int, *mut c_void)>;
type SinkInputInfoCallback =
    Option<unsafe extern "C" fn(*mut PaContext, *const PaSinkInputInfoPrefix, c_int, *mut c_void)>;
type SuccessCallback = Option<unsafe extern "C" fn(*mut PaContext, c_int, *mut c_void)>;
type SubscriptionCallback = Option<unsafe extern "C" fn(*mut PaContext, u32, u32, *mut c_void)>;

struct PulseApi {
    _library: Library,
    mainloop_new: unsafe extern "C" fn() -> *mut PaThreadedMainloop,
    mainloop_free: unsafe extern "C" fn(*mut PaThreadedMainloop),
    mainloop_start: unsafe extern "C" fn(*mut PaThreadedMainloop) -> c_int,
    mainloop_stop: unsafe extern "C" fn(*mut PaThreadedMainloop),
    mainloop_lock: unsafe extern "C" fn(*mut PaThreadedMainloop),
    mainloop_unlock: unsafe extern "C" fn(*mut PaThreadedMainloop),
    mainloop_wait: unsafe extern "C" fn(*mut PaThreadedMainloop),
    mainloop_signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    mainloop_get_api: unsafe extern "C" fn(*mut PaThreadedMainloop) -> *mut PaMainloopApi,
    context_new: unsafe extern "C" fn(*mut PaMainloopApi, *const c_char) -> *mut PaContext,
    context_unref: unsafe extern "C" fn(*mut PaContext),
    context_connect:
        unsafe extern "C" fn(*mut PaContext, *const c_char, u32, *const c_void) -> c_int,
    context_disconnect: unsafe extern "C" fn(*mut PaContext),
    context_get_state: unsafe extern "C" fn(*const PaContext) -> c_int,
    context_set_state_callback:
        unsafe extern "C" fn(*mut PaContext, ContextStateCallback, *mut c_void),
    context_set_subscribe_callback:
        unsafe extern "C" fn(*mut PaContext, SubscriptionCallback, *mut c_void),
    context_subscribe:
        unsafe extern "C" fn(*mut PaContext, u32, SuccessCallback, *mut c_void) -> *mut PaOperation,
    context_get_server_info:
        unsafe extern "C" fn(*mut PaContext, ServerInfoCallback, *mut c_void) -> *mut PaOperation,
    context_get_sink_info_by_name: unsafe extern "C" fn(
        *mut PaContext,
        *const c_char,
        SinkInfoCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_set_sink_volume_by_name: unsafe extern "C" fn(
        *mut PaContext,
        *const c_char,
        *const PaCVolume,
        SuccessCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_set_sink_mute_by_name: unsafe extern "C" fn(
        *mut PaContext,
        *const c_char,
        c_int,
        SuccessCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_get_sink_input_info_list: unsafe extern "C" fn(
        *mut PaContext,
        SinkInputInfoCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_get_sink_input_info: unsafe extern "C" fn(
        *mut PaContext,
        u32,
        SinkInputInfoCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_set_sink_input_volume: unsafe extern "C" fn(
        *mut PaContext,
        u32,
        *const PaCVolume,
        SuccessCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    context_set_sink_input_mute: unsafe extern "C" fn(
        *mut PaContext,
        u32,
        c_int,
        SuccessCallback,
        *mut c_void,
    ) -> *mut PaOperation,
    operation_unref: unsafe extern "C" fn(*mut PaOperation),
    cvolume_avg: unsafe extern "C" fn(*const PaCVolume) -> u32,
    cvolume_set: unsafe extern "C" fn(*mut PaCVolume, u32, u32) -> *mut PaCVolume,
    proplist_gets: unsafe extern "C" fn(*const PaProplist, *const c_char) -> *const c_char,
}

impl PulseApi {
    fn load() -> Result<Self, String> {
        // SAFETY: the library name is fixed and every copied symbol remains
        // valid because the Library is retained by PulseApi for its lifetime.
        unsafe {
            let library = Library::new("libpulse.so.0")
                .map_err(|error| format!("could not load libpulse.so.0: {error}"))?;
            macro_rules! symbol {
                ($name:literal) => {
                    *library
                        .get(concat!($name, "\0").as_bytes())
                        .map_err(|error| format!("missing libpulse symbol {}: {error}", $name))?
                };
            }
            Ok(Self {
                mainloop_new: symbol!("pa_threaded_mainloop_new"),
                mainloop_free: symbol!("pa_threaded_mainloop_free"),
                mainloop_start: symbol!("pa_threaded_mainloop_start"),
                mainloop_stop: symbol!("pa_threaded_mainloop_stop"),
                mainloop_lock: symbol!("pa_threaded_mainloop_lock"),
                mainloop_unlock: symbol!("pa_threaded_mainloop_unlock"),
                mainloop_wait: symbol!("pa_threaded_mainloop_wait"),
                mainloop_signal: symbol!("pa_threaded_mainloop_signal"),
                mainloop_get_api: symbol!("pa_threaded_mainloop_get_api"),
                context_new: symbol!("pa_context_new"),
                context_unref: symbol!("pa_context_unref"),
                context_connect: symbol!("pa_context_connect"),
                context_disconnect: symbol!("pa_context_disconnect"),
                context_get_state: symbol!("pa_context_get_state"),
                context_set_state_callback: symbol!("pa_context_set_state_callback"),
                context_set_subscribe_callback: symbol!("pa_context_set_subscribe_callback"),
                context_subscribe: symbol!("pa_context_subscribe"),
                context_get_server_info: symbol!("pa_context_get_server_info"),
                context_get_sink_info_by_name: symbol!("pa_context_get_sink_info_by_name"),
                context_set_sink_volume_by_name: symbol!("pa_context_set_sink_volume_by_name"),
                context_set_sink_mute_by_name: symbol!("pa_context_set_sink_mute_by_name"),
                context_get_sink_input_info_list: symbol!("pa_context_get_sink_input_info_list"),
                context_get_sink_input_info: symbol!("pa_context_get_sink_input_info"),
                context_set_sink_input_volume: symbol!("pa_context_set_sink_input_volume"),
                context_set_sink_input_mute: symbol!("pa_context_set_sink_input_mute"),
                operation_unref: symbol!("pa_operation_unref"),
                cvolume_avg: symbol!("pa_cvolume_avg"),
                cvolume_set: symbol!("pa_cvolume_set"),
                proplist_gets: symbol!("pa_proplist_gets"),
                _library: library,
            })
        }
    }
}

struct PulseSignal {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
}

struct PulseSubscription {
    commands: SyncSender<AudioCommand>,
}

const PA_SUBSCRIPTION_MASK_SINK: u32 = 1 << 0;
const PA_SUBSCRIPTION_MASK_SINK_INPUT: u32 = 1 << 2;
const PA_SUBSCRIPTION_MASK_SERVER: u32 = 1 << 7;
const PA_SUBSCRIPTION_EVENT_FACILITY_MASK: u32 = 0x0f;
const PA_SUBSCRIPTION_EVENT_SINK: u32 = 0;
const PA_SUBSCRIPTION_EVENT_SINK_INPUT: u32 = 2;
const PA_SUBSCRIPTION_EVENT_SERVER: u32 = 7;

unsafe extern "C" fn on_subscription_event(
    _context: *mut PaContext,
    event_type: u32,
    _index: u32,
    userdata: *mut c_void,
) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: PulseConnection retains the subscription allocation until the
    // callback is unregistered and the threaded mainloop has stopped.
    let subscription = unsafe { &*userdata.cast::<PulseSubscription>() };
    match event_type & PA_SUBSCRIPTION_EVENT_FACILITY_MASK {
        PA_SUBSCRIPTION_EVENT_SINK | PA_SUBSCRIPTION_EVENT_SERVER => {
            let _ = subscription.commands.try_send(AudioCommand::ReadLevel);
        }
        PA_SUBSCRIPTION_EVENT_SINK_INPUT => {
            let _ = subscription.commands.try_send(AudioCommand::RequestStreams);
        }
        _ => {}
    }
}

unsafe extern "C" fn on_context_state(_context: *mut PaContext, userdata: *mut c_void) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: PulseConnection pins this allocation until after the context is
    // disconnected and its threaded mainloop has stopped.
    let signal = unsafe { &*userdata.cast::<PulseSignal>() };
    // SAFETY: the callback is invoked by the live mainloop owning this handle.
    unsafe { (signal.signal)(signal.mainloop, 0) };
}

struct PulseConnection {
    mainloop: *mut PaThreadedMainloop,
    context: *mut PaContext,
    signal: Box<PulseSignal>,
    subscription: Box<PulseSubscription>,
    started: bool,
}

impl PulseConnection {
    fn connect(
        api: &PulseApi,
        subscription_commands: SyncSender<AudioCommand>,
    ) -> Result<Self, &'static str> {
        // SAFETY: all handles are created and destroyed through the matching
        // libpulse API and remain confined to the audio worker.
        unsafe {
            let mainloop = (api.mainloop_new)();
            if mainloop.is_null() {
                return Err("could not allocate PulseAudio mainloop");
            }
            let application = c"Denial Rust";
            let context = (api.context_new)((api.mainloop_get_api)(mainloop), application.as_ptr());
            if context.is_null() {
                (api.mainloop_free)(mainloop);
                return Err("could not allocate PulseAudio context");
            }
            let mut connection = Self {
                mainloop,
                context,
                signal: Box::new(PulseSignal {
                    mainloop,
                    signal: api.mainloop_signal,
                }),
                subscription: Box::new(PulseSubscription {
                    commands: subscription_commands,
                }),
                started: false,
            };
            (api.context_set_state_callback)(
                context,
                Some(on_context_state),
                (&mut *connection.signal as *mut PulseSignal).cast(),
            );
            (api.context_set_subscribe_callback)(
                context,
                Some(on_subscription_event),
                (&mut *connection.subscription as *mut PulseSubscription).cast(),
            );
            if (api.context_connect)(context, ptr::null(), 0, ptr::null()) < 0
                || (api.mainloop_start)(mainloop) < 0
            {
                connection.close(api);
                return Err("could not start PulseAudio connection");
            }
            connection.started = true;
            (api.mainloop_lock)(mainloop);
            while context_state_is_good((api.context_get_state)(context))
                && (api.context_get_state)(context) != PA_CONTEXT_READY
            {
                (api.mainloop_wait)(mainloop);
            }
            let ready = (api.context_get_state)(context) == PA_CONTEXT_READY;
            (api.mainloop_unlock)(mainloop);
            if !ready {
                connection.close(api);
                return Err("PulseAudio context did not become ready");
            }

            (api.mainloop_lock)(mainloop);
            let query = SuccessQuery {
                mainloop,
                signal: api.mainloop_signal,
                state: Mutex::new(SuccessQueryState {
                    done: false,
                    success: false,
                }),
            };
            let operation = (api.context_subscribe)(
                context,
                PA_SUBSCRIPTION_MASK_SINK
                    | PA_SUBSCRIPTION_MASK_SINK_INPUT
                    | PA_SUBSCRIPTION_MASK_SERVER,
                Some(on_success),
                (&query as *const SuccessQuery).cast_mut().cast(),
            );
            let subscribed = wait_for_success(api, &connection, operation, &query);
            (api.mainloop_unlock)(mainloop);
            if !subscribed {
                connection.close(api);
                return Err("could not subscribe to PulseAudio state changes");
            }
            info!("Denial Rust audio connected through native libpulse");
            Ok(connection)
        }
    }

    fn close(&mut self, api: &PulseApi) {
        // SAFETY: close is called at most once for handles owned by this value.
        unsafe {
            if !self.context.is_null() {
                if self.started {
                    (api.mainloop_lock)(self.mainloop);
                    (api.context_set_subscribe_callback)(self.context, None, ptr::null_mut());
                    (api.context_disconnect)(self.context);
                    (api.mainloop_unlock)(self.mainloop);
                }
                if self.started {
                    (api.mainloop_stop)(self.mainloop);
                }
                self.started = false;
                (api.context_unref)(self.context);
                self.context = ptr::null_mut();
            }
            if !self.mainloop.is_null() {
                (api.mainloop_free)(self.mainloop);
                self.mainloop = ptr::null_mut();
            }
        }
    }
}

const PA_CONTEXT_READY: c_int = 4;

fn context_state_is_good(state: c_int) -> bool {
    (0..=PA_CONTEXT_READY).contains(&state)
}

struct ServerQuery {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    state: Mutex<ServerQueryState>,
}

struct ServerQueryState {
    done: bool,
    sink: Option<CString>,
}

fn lock_unpoisoned<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

unsafe extern "C" fn on_server_info(
    _context: *mut PaContext,
    info: *const PaServerInfo,
    userdata: *mut c_void,
) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: query lives on the waiting worker stack until this callback has
    // completed and the operation is unreferenced.
    let query = unsafe { &*userdata.cast::<ServerQuery>() };
    let mut state = lock_unpoisoned(&query.state);
    if !info.is_null() {
        // SAFETY: libpulse owns a valid info record for this callback.
        let sink = unsafe { (*info).default_sink_name };
        if !sink.is_null() {
            // SAFETY: PulseAudio strings are NUL-terminated for callback life.
            state.sink = Some(unsafe { CStr::from_ptr(sink) }.to_owned());
        }
    }
    state.done = true;
    drop(state);
    // SAFETY: this is the live mainloop associated with the query.
    unsafe { (query.signal)(query.mainloop, 0) };
}

struct SinkQuery {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    state: Mutex<SinkQueryState>,
}

struct SinkQueryState {
    done: bool,
    sink: Option<PulseSinkState>,
}

struct PulseSinkState {
    volume: PaCVolume,
    channels: u8,
    muted: bool,
}

unsafe extern "C" fn on_sink_info(
    _context: *mut PaContext,
    info: *const PaSinkInfoPrefix,
    end_of_list: c_int,
    userdata: *mut c_void,
) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: query remains live until the operation completes.
    let query = unsafe { &*userdata.cast::<SinkQuery>() };
    let mut state = lock_unpoisoned(&query.state);
    if end_of_list != 0 {
        state.done = true;
    } else if !info.is_null() {
        // SAFETY: libpulse supplies a valid ABI-stable prefix for the callback.
        let info = unsafe { &*info };
        let channels = if info.channel_map.channels > 0 {
            info.channel_map.channels
        } else {
            info.volume.channels
        };
        if channels > 0 {
            state.sink = Some(PulseSinkState {
                volume: info.volume,
                channels,
                muted: info.mute != 0,
            });
        }
    }
    let done = state.done;
    drop(state);
    if done {
        // SAFETY: this is the live mainloop associated with the query.
        unsafe { (query.signal)(query.mainloop, 0) };
    }
}

struct SinkInputQuery {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    state: Mutex<SinkInputQueryState>,
}

struct SinkInputQueryState {
    done: bool,
    input: Option<PulseSinkInputState>,
}

struct PulseSinkInputState {
    channels: u8,
    muted: bool,
}

unsafe extern "C" fn on_sink_input_info(
    _context: *mut PaContext,
    info: *const PaSinkInputInfoPrefix,
    end_of_list: c_int,
    userdata: *mut c_void,
) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: query remains live until the introspection operation completes.
    let query = unsafe { &*userdata.cast::<SinkInputQuery>() };
    let mut state = lock_unpoisoned(&query.state);
    if end_of_list != 0 {
        state.done = true;
    } else if !info.is_null() {
        // SAFETY: libpulse supplies the stable sink-input prefix for callback life.
        let info = unsafe { &*info };
        let channels = if info.channel_map.channels > 0 {
            info.channel_map.channels
        } else {
            info.volume.channels
        };
        if channels > 0 {
            state.input = Some(PulseSinkInputState {
                channels,
                muted: info.mute != 0,
            });
        }
    }
    let done = state.done;
    drop(state);
    if done {
        // SAFETY: this is the live mainloop associated with the query.
        unsafe { (query.signal)(query.mainloop, 0) };
    }
}

struct SinkInputListQuery {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    proplist_gets: unsafe extern "C" fn(*const PaProplist, *const c_char) -> *const c_char,
    cvolume_avg: unsafe extern "C" fn(*const PaCVolume) -> u32,
    state: Mutex<SinkInputListQueryState>,
}

struct SinkInputListQueryState {
    done: bool,
    success: bool,
    streams: Vec<AudioStreamState>,
}

unsafe extern "C" fn on_sink_input_list(
    _context: *mut PaContext,
    info: *const PaSinkInputInfoPrefix,
    end_of_list: c_int,
    userdata: *mut c_void,
) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: query remains live until the list operation completes.
    let query = unsafe { &*userdata.cast::<SinkInputListQuery>() };
    let mut state = lock_unpoisoned(&query.state);
    if end_of_list < 0 {
        state.done = true;
    } else if end_of_list > 0 {
        state.done = true;
        state.success = true;
    } else if !info.is_null() && state.streams.len() < MAX_AUDIO_STREAMS {
        // SAFETY: libpulse supplies the stable sink-input prefix for callback life.
        let info = unsafe { &*info };
        // SAFETY: volume is a complete pa_cvolume copied from libpulse.
        let average = unsafe { (query.cvolume_avg)(&info.volume) };
        state.streams.push(AudioStreamState {
            id: info.index,
            // SAFETY: every inspected string is owned by libpulse for callback life.
            name: unsafe { pulse_stream_name(query.proplist_gets, info) },
            level_percent: ((f64::from(average) / 65_536.0).clamp(0.0, 1.0) * 100.0).round() as u8,
            muted: info.mute != 0,
        });
    }
    let done = state.done;
    drop(state);
    if done {
        // SAFETY: this is the live mainloop associated with the query.
        unsafe { (query.signal)(query.mainloop, 0) };
    }
}

unsafe fn pulse_stream_name(
    proplist_gets: unsafe extern "C" fn(*const PaProplist, *const c_char) -> *const c_char,
    info: &PaSinkInputInfoPrefix,
) -> String {
    let mut selected = ptr::null();
    if !info.proplist.is_null() {
        for property in [c"application.name", c"media.name", c"application.id"] {
            // SAFETY: proplist and property are valid for the active callback.
            let value = unsafe { proplist_gets(info.proplist, property.as_ptr()) };
            if !value.is_null() {
                selected = value;
                break;
            }
        }
    }
    if selected.is_null() {
        selected = info.name;
    }
    let name = if selected.is_null() {
        "Unknown application".into()
    } else {
        // SAFETY: selected is a callback-lifetime NUL-terminated PulseAudio string.
        unsafe { CStr::from_ptr(selected) }
            .to_string_lossy()
            .into_owned()
    };
    truncate_utf8(name, MAX_AUDIO_STREAM_NAME_BYTES)
}

fn truncate_utf8(mut value: String, maximum: usize) -> String {
    if value.len() <= maximum {
        return value;
    }
    let mut boundary = maximum;
    while boundary > 0 && !value.is_char_boundary(boundary) {
        boundary -= 1;
    }
    value.truncate(boundary);
    value
}

struct SuccessQuery {
    mainloop: *mut PaThreadedMainloop,
    signal: unsafe extern "C" fn(*mut PaThreadedMainloop, c_int),
    state: Mutex<SuccessQueryState>,
}

struct SuccessQueryState {
    done: bool,
    success: bool,
}

unsafe extern "C" fn on_success(_context: *mut PaContext, success: c_int, userdata: *mut c_void) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: query remains live until the operation completes.
    let query = unsafe { &*userdata.cast::<SuccessQuery>() };
    let mut state = lock_unpoisoned(&query.state);
    state.success = success != 0;
    state.done = true;
    drop(state);
    // SAFETY: this is the live mainloop associated with the query.
    unsafe { (query.signal)(query.mainloop, 0) };
}

fn query_default_sink(api: &PulseApi, connection: &PulseConnection) -> Option<CString> {
    // SAFETY: the threaded mainloop lock serializes every context operation;
    // the stack query stays live until its operation is complete or the
    // context leaves a usable state.
    unsafe {
        let query = ServerQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            state: Mutex::new(ServerQueryState {
                done: false,
                sink: None,
            }),
        };
        (api.mainloop_lock)(connection.mainloop);
        let operation = (api.context_get_server_info)(
            connection.context,
            Some(on_server_info),
            (&query as *const ServerQuery).cast_mut().cast(),
        );
        if operation.is_null() {
            (api.mainloop_unlock)(connection.mainloop);
            return None;
        }
        while !lock_unpoisoned(&query.state).done
            && context_state_is_good((api.context_get_state)(connection.context))
        {
            (api.mainloop_wait)(connection.mainloop);
        }
        (api.operation_unref)(operation);
        (api.mainloop_unlock)(connection.mainloop);
        lock_unpoisoned(&query.state).sink.take()
    }
}

fn query_sink(api: &PulseApi, connection: &PulseConnection, sink: &CStr) -> Option<PulseSinkState> {
    // SAFETY: see query_default_sink; the same ownership and locking rules
    // apply to this introspection operation.
    unsafe {
        let query = SinkQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            state: Mutex::new(SinkQueryState {
                done: false,
                sink: None,
            }),
        };
        (api.mainloop_lock)(connection.mainloop);
        let operation = (api.context_get_sink_info_by_name)(
            connection.context,
            sink.as_ptr(),
            Some(on_sink_info),
            (&query as *const SinkQuery).cast_mut().cast(),
        );
        if operation.is_null() {
            (api.mainloop_unlock)(connection.mainloop);
            return None;
        }
        while !lock_unpoisoned(&query.state).done
            && context_state_is_good((api.context_get_state)(connection.context))
        {
            (api.mainloop_wait)(connection.mainloop);
        }
        (api.operation_unref)(operation);
        (api.mainloop_unlock)(connection.mainloop);
        lock_unpoisoned(&query.state).sink.take()
    }
}

fn query_sink_input(
    api: &PulseApi,
    connection: &PulseConnection,
    stream_id: u32,
) -> Option<PulseSinkInputState> {
    // SAFETY: the threaded-mainloop lock serializes this operation and the
    // stack query stays live through the terminal callback.
    unsafe {
        let query = SinkInputQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            state: Mutex::new(SinkInputQueryState {
                done: false,
                input: None,
            }),
        };
        (api.mainloop_lock)(connection.mainloop);
        let operation = (api.context_get_sink_input_info)(
            connection.context,
            stream_id,
            Some(on_sink_input_info),
            (&query as *const SinkInputQuery).cast_mut().cast(),
        );
        if operation.is_null() {
            (api.mainloop_unlock)(connection.mainloop);
            return None;
        }
        while !lock_unpoisoned(&query.state).done
            && context_state_is_good((api.context_get_state)(connection.context))
        {
            (api.mainloop_wait)(connection.mainloop);
        }
        (api.operation_unref)(operation);
        (api.mainloop_unlock)(connection.mainloop);
        lock_unpoisoned(&query.state).input.take()
    }
}

fn query_sink_inputs(
    api: &PulseApi,
    connection: &PulseConnection,
) -> Option<Vec<AudioStreamState>> {
    // SAFETY: the threaded-mainloop lock serializes this operation and the
    // callback never retains any server-owned pointers.
    unsafe {
        let query = SinkInputListQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            proplist_gets: api.proplist_gets,
            cvolume_avg: api.cvolume_avg,
            state: Mutex::new(SinkInputListQueryState {
                done: false,
                success: false,
                streams: Vec::with_capacity(16),
            }),
        };
        (api.mainloop_lock)(connection.mainloop);
        let operation = (api.context_get_sink_input_info_list)(
            connection.context,
            Some(on_sink_input_list),
            (&query as *const SinkInputListQuery).cast_mut().cast(),
        );
        if operation.is_null() {
            (api.mainloop_unlock)(connection.mainloop);
            return None;
        }
        while !lock_unpoisoned(&query.state).done
            && context_state_is_good((api.context_get_state)(connection.context))
        {
            (api.mainloop_wait)(connection.mainloop);
        }
        (api.operation_unref)(operation);
        (api.mainloop_unlock)(connection.mainloop);
        let mut state = lock_unpoisoned(&query.state);
        state.success.then(|| std::mem::take(&mut state.streams))
    }
}

fn wait_for_success(
    api: &PulseApi,
    connection: &PulseConnection,
    operation: *mut PaOperation,
    query: &SuccessQuery,
) -> bool {
    if operation.is_null() {
        return false;
    }
    // SAFETY: caller holds the threaded mainloop lock; query stays alive until
    // the operation callback finishes or the context fails.
    unsafe {
        while !lock_unpoisoned(&query.state).done
            && context_state_is_good((api.context_get_state)(connection.context))
        {
            (api.mainloop_wait)(connection.mainloop);
        }
        (api.operation_unref)(operation);
    }
    lock_unpoisoned(&query.state).success
}

fn read_pulse_level(api: &PulseApi, connection: &PulseConnection) -> Option<f64> {
    let sink = query_default_sink(api, connection)?;
    let state = query_sink(api, connection, &sink)?;
    // SAFETY: state.volume is a complete pa_cvolume copied from libpulse.
    let current = unsafe { (api.cvolume_avg)(&state.volume) } as f64 / 65_536.0;
    Some(current.clamp(0.0, 1.0))
}

fn set_pulse_level(api: &PulseApi, connection: &PulseConnection, target: f64) -> Option<f64> {
    let sink = query_default_sink(api, connection)?;
    let state = query_sink(api, connection, &sink)?;
    let target = target.clamp(0.0, MAX_AUDIO_LEVEL);
    let pulse_level = (target * 65_536.0).round() as u32;
    let mut volume = PaCVolume::default();
    // SAFETY: volume is a complete pa_cvolume and channels came from the
    // validated server record. The context stays locked through completion.
    unsafe {
        (api.cvolume_set)(&mut volume, u32::from(state.channels), pulse_level);
        (api.mainloop_lock)(connection.mainloop);
    }
    let volume_query = SuccessQuery {
        mainloop: connection.mainloop,
        signal: api.mainloop_signal,
        state: Mutex::new(SuccessQueryState {
            done: false,
            success: false,
        }),
    };
    // SAFETY: sink and volume remain live through the synchronous wait.
    let volume_operation = unsafe {
        (api.context_set_sink_volume_by_name)(
            connection.context,
            sink.as_ptr(),
            &volume,
            Some(on_success),
            (&volume_query as *const SuccessQuery).cast_mut().cast(),
        )
    };
    let volume_applied = wait_for_success(api, connection, volume_operation, &volume_query);
    // SAFETY: balances the lock acquired above.
    unsafe { (api.mainloop_unlock)(connection.mainloop) };
    if !volume_applied {
        return None;
    }

    if target > 0.0 && state.muted {
        // Raising a level is an explicit request to hear that output.
        // SAFETY: the context operation is serialized by the mainloop lock.
        unsafe { (api.mainloop_lock)(connection.mainloop) };
        let mute_query = SuccessQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            state: Mutex::new(SuccessQueryState {
                done: false,
                success: false,
            }),
        };
        // SAFETY: sink remains live through the synchronous wait.
        let mute_operation = unsafe {
            (api.context_set_sink_mute_by_name)(
                connection.context,
                sink.as_ptr(),
                0,
                Some(on_success),
                (&mute_query as *const SuccessQuery).cast_mut().cast(),
            )
        };
        let unmuted = wait_for_success(api, connection, mute_operation, &mute_query);
        // SAFETY: balances the lock acquired above.
        unsafe { (api.mainloop_unlock)(connection.mainloop) };
        if !unmuted {
            return None;
        }
    }

    Some(target.clamp(0.0, 1.0))
}

fn adjust_pulse_level(api: &PulseApi, connection: &PulseConnection, delta: f64) -> Option<f64> {
    let sink = query_default_sink(api, connection)?;
    let state = query_sink(api, connection, &sink)?;
    // SAFETY: state.volume is a valid pa_cvolume copied from libpulse.
    let current = unsafe { (api.cvolume_avg)(&state.volume) } as f64 / 65_536.0;
    let target = (current + delta).clamp(0.0, MAX_AUDIO_LEVEL);
    set_pulse_level(api, connection, target)
}

fn toggle_pulse_mute(api: &PulseApi, connection: &PulseConnection) -> Option<f64> {
    let sink = query_default_sink(api, connection)?;
    let state = query_sink(api, connection, &sink)?;
    // SAFETY: the context operation is serialized by the threaded-mainloop lock.
    unsafe { (api.mainloop_lock)(connection.mainloop) };
    let query = SuccessQuery {
        mainloop: connection.mainloop,
        signal: api.mainloop_signal,
        state: Mutex::new(SuccessQueryState {
            done: false,
            success: false,
        }),
    };
    // SAFETY: sink remains live through the synchronous wait.
    let operation = unsafe {
        (api.context_set_sink_mute_by_name)(
            connection.context,
            sink.as_ptr(),
            if state.muted { 0 } else { 1 },
            Some(on_success),
            (&query as *const SuccessQuery).cast_mut().cast(),
        )
    };
    let applied = wait_for_success(api, connection, operation, &query);
    // SAFETY: balances the lock acquired above.
    unsafe { (api.mainloop_unlock)(connection.mainloop) };
    if !applied {
        return None;
    }
    // SAFETY: state.volume is a valid server-provided pa_cvolume.
    let level = unsafe { (api.cvolume_avg)(&state.volume) } as f64 / 65_536.0;
    Some(level.clamp(0.0, 1.0))
}

fn set_pulse_stream_level(
    api: &PulseApi,
    connection: &PulseConnection,
    stream_id: u32,
    target: f64,
) -> Option<()> {
    let state = query_sink_input(api, connection, stream_id)?;
    let target = target.clamp(0.0, 1.0);
    let mut volume = PaCVolume::default();
    // SAFETY: volume is a complete pa_cvolume and the channel count came from
    // the queried sink-input record.
    unsafe {
        (api.cvolume_set)(
            &mut volume,
            u32::from(state.channels),
            (target * 65_536.0).round() as u32,
        );
        (api.mainloop_lock)(connection.mainloop);
    }
    let volume_query = SuccessQuery {
        mainloop: connection.mainloop,
        signal: api.mainloop_signal,
        state: Mutex::new(SuccessQueryState {
            done: false,
            success: false,
        }),
    };
    // SAFETY: volume remains live through the synchronous wait.
    let operation = unsafe {
        (api.context_set_sink_input_volume)(
            connection.context,
            stream_id,
            &volume,
            Some(on_success),
            (&volume_query as *const SuccessQuery).cast_mut().cast(),
        )
    };
    let applied = wait_for_success(api, connection, operation, &volume_query);
    // SAFETY: balances the lock acquired above.
    unsafe { (api.mainloop_unlock)(connection.mainloop) };
    if !applied {
        return None;
    }

    if target > 0.0 && state.muted {
        // SAFETY: the context operation is serialized by the mainloop lock.
        unsafe { (api.mainloop_lock)(connection.mainloop) };
        let mute_query = SuccessQuery {
            mainloop: connection.mainloop,
            signal: api.mainloop_signal,
            state: Mutex::new(SuccessQueryState {
                done: false,
                success: false,
            }),
        };
        // SAFETY: no borrowed callback data escapes the wait.
        let operation = unsafe {
            (api.context_set_sink_input_mute)(
                connection.context,
                stream_id,
                0,
                Some(on_success),
                (&mute_query as *const SuccessQuery).cast_mut().cast(),
            )
        };
        let unmuted = wait_for_success(api, connection, operation, &mute_query);
        // SAFETY: balances the lock acquired above.
        unsafe { (api.mainloop_unlock)(connection.mainloop) };
        if !unmuted {
            return None;
        }
    }
    Some(())
}

fn run_audio_worker(
    commands: Receiver<AudioCommand>,
    events: SyncSender<SystemControlEvent>,
    subscription_commands: SyncSender<AudioCommand>,
) {
    let api = match PulseApi::load() {
        Ok(api) => api,
        Err(error) => {
            warn!(%error, "native audio controls are unavailable");
            while !matches!(commands.recv(), Ok(AudioCommand::Stop) | Err(_)) {}
            return;
        }
    };
    let mut connection: Option<PulseConnection> = None;
    let mut failure_latched = false;
    'worker: while let Ok(first) = commands.recv() {
        let mut level = None;
        let mut delta = 0.0;
        let mut toggle_mute = false;
        let mut state_requested = false;
        let mut request_serial = 0;
        let mut streams_requested = false;
        let mut stream_levels = HashMap::<u32, f64>::new();

        let mut absorb = |command: AudioCommand| -> bool {
            match command {
                AudioCommand::ReadLevel => state_requested = true,
                AudioCommand::SetLevel {
                    level: next,
                    request_serial: serial,
                } => {
                    level = Some(next.clamp(0.0, 1.0));
                    delta = 0.0;
                    request_serial = serial;
                    state_requested = true;
                }
                AudioCommand::Adjust(next) => {
                    if let Some(current) = level.as_mut() {
                        *current = (*current + next).clamp(0.0, MAX_AUDIO_LEVEL);
                    } else {
                        delta = (delta + next).clamp(-MAX_AUDIO_LEVEL, MAX_AUDIO_LEVEL);
                    }
                    request_serial = 0;
                    state_requested = true;
                }
                AudioCommand::ToggleMute => {
                    toggle_mute = !toggle_mute;
                    state_requested = true;
                    request_serial = 0;
                }
                AudioCommand::RequestStreams => streams_requested = true,
                AudioCommand::SetStreamLevel { stream_id, level } => {
                    stream_levels.insert(stream_id, level.clamp(0.0, 1.0));
                    streams_requested = true;
                }
                AudioCommand::Stop => return false,
            }
            true
        };

        if !absorb(first) {
            break;
        }
        while let Ok(command) = commands.try_recv() {
            if !absorb(command) {
                break 'worker;
            }
        }
        if connection.is_none() {
            match PulseConnection::connect(&api, subscription_commands.clone()) {
                Ok(active) => connection = Some(active),
                Err(error) => {
                    if !std::mem::replace(&mut failure_latched, true) {
                        warn!(%error, "native audio connection failed");
                    }
                    continue;
                }
            }
        }
        let Some(active) = connection.as_ref() else {
            continue;
        };
        let mut operation_failed = false;
        if let Some(level) = level {
            operation_failed |= set_pulse_level(&api, active, level).is_none();
        }
        if !operation_failed && delta != 0.0 {
            operation_failed |= adjust_pulse_level(&api, active, delta).is_none();
        }
        if !operation_failed && toggle_mute {
            operation_failed |= toggle_pulse_mute(&api, active).is_none();
        }
        if !operation_failed {
            for (stream_id, stream_level) in stream_levels {
                if set_pulse_stream_level(&api, active, stream_id, stream_level).is_none() {
                    // A stream can legitimately disappear between the UI
                    // snapshot and this write. Refresh the list without
                    // discarding the otherwise healthy Pulse connection.
                    streams_requested = true;
                }
            }
        }
        if !operation_failed && state_requested {
            if let Some(level) = read_pulse_level(&api, active) {
                let _ = events.try_send(SystemControlEvent::AudioLevel {
                    level,
                    request_serial,
                });
            } else {
                operation_failed = true;
            }
        }
        if !operation_failed && streams_requested {
            if let Some(streams) = query_sink_inputs(&api, active) {
                let _ = events.try_send(SystemControlEvent::AudioStreams(streams));
            } else {
                operation_failed = true;
            }
        }
        if operation_failed {
            if !std::mem::replace(&mut failure_latched, true) {
                warn!("native PulseAudio operation failed; reconnecting");
            }
            if let Some(mut active) = connection.take() {
                active.close(&api);
            }
        } else {
            failure_latched = false;
        }
    }
    if let Some(mut active) = connection {
        active.close(&api);
    }
}

trait BrightnessProvider {
    fn name(&self) -> &'static str;
    fn controls(&mut self, connector: &str) -> bool;
    fn read(&mut self, connector: &str) -> Result<f64, String>;
    fn set(&mut self, connector: &str, level: f64) -> Result<(), String>;
}

struct BrightnessProviders {
    providers: Vec<Box<dyn BrightnessProvider>>,
    desired: HashMap<String, f64>,
    failure_latched: HashMap<String, bool>,
}

impl BrightnessProviders {
    fn start() -> Result<Self, String> {
        let mut providers: Vec<Box<dyn BrightnessProvider>> = Vec::new();
        let mut failures = Vec::new();

        match BacklightWorker::start() {
            Ok(provider) => providers.push(Box::new(provider)),
            Err(error) => failures.push(format!("kernel backlight: {error}")),
        }
        providers.push(Box::new(DdcWorker::new(PathBuf::from(DRM_CLASS_ROOT))));

        if providers.is_empty() {
            return Err(failures.join("; "));
        }
        if !failures.is_empty() {
            info!(unavailable = %failures.join("; "), "some brightness providers are unavailable");
        }
        Ok(Self {
            providers,
            desired: HashMap::new(),
            failure_latched: HashMap::new(),
        })
    }

    fn read(&mut self, connector: &str, monitor_id: i64, events: &SyncSender<SystemControlEvent>) {
        self.control(connector, monitor_id, None, events);
    }

    fn set(
        &mut self,
        connector: &str,
        monitor_id: i64,
        level: f64,
        events: &SyncSender<SystemControlEvent>,
    ) {
        self.control(
            connector,
            monitor_id,
            Some(BrightnessChange::Set(level)),
            events,
        );
    }

    fn adjust(
        &mut self,
        connector: &str,
        monitor_id: i64,
        delta: f64,
        events: &SyncSender<SystemControlEvent>,
    ) {
        self.control(
            connector,
            monitor_id,
            Some(BrightnessChange::Adjust(delta)),
            events,
        );
    }

    fn control(
        &mut self,
        connector: &str,
        monitor_id: i64,
        change: Option<BrightnessChange>,
        events: &SyncSender<SystemControlEvent>,
    ) {
        let Some(provider) = self
            .providers
            .iter_mut()
            .find_map(|provider| provider.controls(connector).then_some(provider))
        else {
            self.log_failure_once(connector, "no registered provider controls this output");
            return;
        };
        let provider_name = provider.name();
        let actual = match provider.read(connector) {
            Ok(level) => level.clamp(0.0, 1.0),
            Err(error) => {
                self.log_failure_once(
                    connector,
                    &format!("{provider_name} could not read brightness: {error}"),
                );
                return;
            }
        };
        let Some(change) = change else {
            self.desired.insert(connector.to_owned(), actual);
            self.failure_latched.insert(connector.to_owned(), false);
            let _ = events.try_send(SystemControlEvent::BrightnessLevel {
                monitor_id,
                level: actual,
            });
            return;
        };
        let target = match change {
            BrightnessChange::Set(level) => level.clamp(0.0, 1.0),
            BrightnessChange::Adjust(delta) => {
                (self.desired.get(connector).copied().unwrap_or(actual) + delta).clamp(0.0, 1.0)
            }
        };
        let _ = events.try_send(SystemControlEvent::BrightnessLevel {
            monitor_id,
            level: target,
        });
        if let Err(error) = provider.set(connector, target) {
            self.log_failure_once(
                connector,
                &format!("{provider_name} could not write brightness: {error}"),
            );
            let _ = events.try_send(SystemControlEvent::BrightnessLevel {
                monitor_id,
                level: actual,
            });
            self.desired.insert(connector.to_owned(), actual);
            return;
        }
        self.desired.insert(connector.to_owned(), target);
        self.failure_latched.insert(connector.to_owned(), false);
    }

    fn log_failure_once(&mut self, connector: &str, message: &str) {
        if !self
            .failure_latched
            .insert(connector.to_owned(), true)
            .unwrap_or(false)
        {
            warn!(connector, %message, "native brightness adjustment failed");
        }
    }
}

fn read_sysfs_u32(path: &Path) -> Option<u32> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn is_internal_panel(connector: &str) -> bool {
    const INTERNAL_PREFIXES: [&str; 4] = ["edp", "lvds", "dsi", "dpi"];
    let lowered = connector.to_ascii_lowercase();
    INTERNAL_PREFIXES
        .iter()
        .any(|prefix| lowered.starts_with(prefix))
}

#[cfg(test)]
fn internal_connector(name: &str) -> bool {
    is_internal_panel(name)
}

fn connected_internal_connector(name: &str, status: &str) -> bool {
    let s = status.trim();
    is_internal_panel(name) && (s == "connected" || s == "unknown" || s.is_empty())
}

fn backlight_kind_priority(kind: &str) -> u8 {
    match kind {
        "raw" => 3,
        "platform" => 2,
        "firmware" => 1,
        _ => 0,
    }
}

fn paths_related(left: &Path, right: &Path) -> bool {
    left == right || left.starts_with(right) || right.starts_with(left)
}

#[derive(Clone, Debug)]
struct BacklightDevice {
    name: String,
    path: PathBuf,
    device_path: PathBuf,
    kind: String,
    maximum: u32,
}

impl BacklightDevice {
    fn level(&self) -> Option<f64> {
        let raw = read_sysfs_u32(&self.path.join("actual_brightness"))
            .or_else(|| read_sysfs_u32(&self.path.join("brightness")))?;
        (self.maximum > 0).then(|| f64::from(raw.min(self.maximum)) / f64::from(self.maximum))
    }

    fn raw_for(&self, level: f64) -> u32 {
        let level = if level.is_nan() {
            0.0
        } else {
            level.clamp(0.0, 1.0)
        };
        let scaled = (level * f64::from(self.maximum)).round();
        if scaled.is_nan() || scaled < MIN_BACKLIGHT_RAW as f64 {
            MIN_BACKLIGHT_RAW
        } else if scaled > self.maximum as f64 {
            self.maximum
        } else {
            (scaled as u32).clamp(MIN_BACKLIGHT_RAW, self.maximum)
        }
    }
}

struct LogindBrightness {
    connection: Connection,
    session: OwnedObjectPath,
}

impl LogindBrightness {
    fn connect() -> Result<Self, String> {
        let connection = ConnectionBuilder::system()
            .map_err(|e| format!("system bus error: {e}"))?
            .method_timeout(LOGIND_DBUS_TIMEOUT)
            .build()
            .map_err(|e| format!("system bus connection build error: {e}"))?;
        let manager = Proxy::new(
            &connection,
            LOGIND_SERVICE,
            LOGIND_MANAGER_OBJECT,
            LOGIND_MANAGER_INTERFACE,
        )
        .map_err(|e| format!("logind manager proxy error: {e}"))?;
        let session: OwnedObjectPath = match manager.call("GetSessionByPID", &(std::process::id(),))
        {
            Ok(session) => session,
            Err(error) => match std::env::var("XDG_SESSION_ID") {
                Ok(id) => manager
                    .call("GetSession", &(id.as_str(),))
                    .map_err(|e| format!("GetSession error: {e}"))?,
                Err(_) => match manager.call("GetSession", &("auto",)) {
                    Ok(s) => s,
                    Err(_) => return Err(format!("could not determine logind session: {error}")),
                },
            },
        };
        Ok(Self {
            connection,
            session,
        })
    }

    fn set(&self, device: &str, raw: u32) -> Result<(), String> {
        let proxy = Proxy::new(
            &self.connection,
            LOGIND_SERVICE,
            self.session.as_str(),
            LOGIND_SESSION_INTERFACE,
        )
        .map_err(|e| format!("logind session proxy error: {e}"))?;
        proxy
            .call("SetBrightness", &("backlight", device, raw))
            .map_err(|e| format!("logind SetBrightness failed: {e}"))
    }
}

fn discover_backlights(backlight_root: &Path, drm_root: &Path) -> HashMap<String, BacklightDevice> {
    let mut backlights = fs::read_dir(backlight_root)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            let maximum =
                read_sysfs_u32(&path.join("max_brightness")).filter(|value| *value > 0)?;
            let device_path = fs::canonicalize(path.join("device")).ok()?;
            let kind = fs::read_to_string(path.join("type"))
                .unwrap_or_default()
                .trim()
                .to_owned();
            Some(BacklightDevice {
                name: entry.file_name().to_string_lossy().into_owned(),
                path,
                device_path,
                kind,
                maximum,
            })
        })
        .collect::<Vec<_>>();
    backlights.sort_by(|left, right| left.name.cmp(&right.name));

    let all_connectors = drm_connector_identities(drm_root);
    let connectors = all_connectors
        .into_iter()
        .filter(|connector| {
            connected_internal_connector(
                &connector.name,
                connector.status.as_deref().unwrap_or_default(),
            )
        })
        .collect::<Vec<_>>();

    let mut displays = HashMap::new();
    for connector in &connectors {
        let mut related = backlights
            .iter()
            .filter(|backlight| {
                if let Some(canonical) = connector.canonical.as_ref()
                    && (canonical.starts_with(&backlight.device_path)
                        || backlight.device_path.starts_with(canonical))
                {
                    return true;
                }
                if let Some(device) = connector.device_path.as_ref()
                    && paths_related(&backlight.device_path, device)
                {
                    return true;
                }
                false
            })
            .collect::<Vec<_>>();
        if related.is_empty() && connectors.len() == 1 && backlights.len() == 1 {
            info!(
                connector = %connector.name,
                backlight = %backlights[0].name,
                "single internal connector and single backlight; using conservative fallback match"
            );
            related.push(&backlights[0]);
        }
        related
            .sort_by_key(|backlight| std::cmp::Reverse(backlight_kind_priority(&backlight.kind)));
        let Some(selected) = related.first() else {
            continue;
        };
        if related.get(1).is_some_and(|other| {
            backlight_kind_priority(&other.kind) == backlight_kind_priority(&selected.kind)
        }) {
            warn!(
                connector = %connector.name,
                "multiple equally suitable kernel backlights; leaving output unclaimed"
            );
            continue;
        }
        displays.insert(connector.name.clone(), (*selected).clone());
    }
    displays
}

struct BacklightWorker {
    displays: HashMap<String, BacklightDevice>,
    logind: Option<LogindBrightness>,
    backlight_root: PathBuf,
    drm_root: PathBuf,
}

impl BacklightWorker {
    fn start() -> Result<Self, String> {
        Self::with_roots(
            PathBuf::from(BACKLIGHT_CLASS_ROOT),
            PathBuf::from(DRM_CLASS_ROOT),
        )
    }

    fn with_roots(backlight_root: PathBuf, drm_root: PathBuf) -> Result<Self, String> {
        let mut worker = Self {
            displays: HashMap::new(),
            logind: None,
            backlight_root,
            drm_root,
        };
        worker.refresh_displays();
        if worker.displays.is_empty() {
            return Err("no kernel backlight devices found".into());
        }
        info!(
            outputs = worker.displays.len(),
            "Denial brightness registered the kernel backlight provider"
        );
        Ok(worker)
    }

    fn refresh_displays(&mut self) {
        self.displays = discover_backlights(&self.backlight_root, &self.drm_root);
    }

    fn display(&mut self, connector: &str) -> Option<&BacklightDevice> {
        if !self.displays.contains_key(connector) {
            self.refresh_displays();
        }
        self.displays.get(connector)
    }
}

impl BrightnessProvider for BacklightWorker {
    fn name(&self) -> &'static str {
        "kernel backlight"
    }

    fn controls(&mut self, connector: &str) -> bool {
        self.display(connector).is_some()
    }

    fn read(&mut self, connector: &str) -> Result<f64, String> {
        let display = self
            .display(connector)
            .ok_or_else(|| "output is not associated with a backlight device".to_owned())?;
        display
            .level()
            .ok_or_else(|| "could not read kernel backlight level".to_owned())
    }

    fn set(&mut self, connector: &str, level: f64) -> Result<(), String> {
        let display = self
            .display(connector)
            .cloned()
            .ok_or_else(|| "output is not associated with a backlight device".to_owned())?;
        let raw = display.raw_for(level);

        match fs::write(display.path.join("brightness"), raw.to_string()) {
            Ok(()) => return Ok(()),
            Err(error) if error.kind() != io::ErrorKind::PermissionDenied => {
                return Err(format!("could not write sysfs brightness: {error}"));
            }
            Err(_) => {}
        }

        if self.logind.is_none() {
            self.logind = LogindBrightness::connect().ok();
        }
        if let Some(logind) = self.logind.as_ref()
            && logind.set(&display.name, raw).is_ok()
        {
            return Ok(());
        }

        match LogindBrightness::connect() {
            Ok(logind) => {
                let res = logind.set(&display.name, raw);
                self.logind = Some(logind);
                res.map_err(|e| format!("logind SetBrightness failed: {e}"))
            }
            Err(error) => {
                self.logind = None;
                Err(format!("logind is unavailable: {error}"))
            }
        }
    }
}

type DdcDisplayRef = *mut c_void;
type DdcDisplayHandle = *mut c_void;

#[repr(C)]
struct DdcIoPath {
    io_mode: c_int,
    path: c_int,
}

#[repr(C)]
struct DdcDisplayInfo {
    marker: [c_char; 4],
    dispno: c_int,
    path: DdcIoPath,
    usb_bus: c_int,
    usb_device: c_int,
    mfg_id: [c_char; 4],
    model_name: [c_char; 14],
    serial: [c_char; 14],
    product_code: u16,
    edid_bytes: [u8; 128],
    vcp_version: [u8; 2],
    dref: DdcDisplayRef,
}

#[repr(C)]
struct DdcDisplayInfo2 {
    legacy: DdcDisplayInfo,
    drm_card_connector: [c_char; 32],
    drm_card_connector_found_by: c_int,
    drm_connector_id: i16,
    unused: [*mut c_void; 8],
}

#[repr(C)]
#[derive(Default)]
struct DdcNonTableValue {
    maximum_high: u8,
    maximum_low: u8,
    current_high: u8,
    current_low: u8,
}

#[derive(Clone, Copy)]
enum DdcDisplayInfoApi {
    ConnectorAware {
        get: unsafe extern "C" fn(DdcDisplayRef, *mut *mut DdcDisplayInfo2) -> c_int,
        free: unsafe extern "C" fn(*mut DdcDisplayInfo2),
    },
    Stable {
        get: unsafe extern "C" fn(DdcDisplayRef, *mut *mut DdcDisplayInfo) -> c_int,
        free: unsafe extern "C" fn(*mut DdcDisplayInfo),
    },
}

struct DdcApi {
    _library: Library,
    init: unsafe extern "C" fn(*const c_char, c_int, c_int, *mut *mut *mut c_char) -> c_int,
    redetect_displays: unsafe extern "C" fn() -> c_int,
    get_display_refs: unsafe extern "C" fn(bool, *mut *mut DdcDisplayRef) -> c_int,
    display_info: DdcDisplayInfoApi,
    open_display: unsafe extern "C" fn(DdcDisplayRef, bool, *mut DdcDisplayHandle) -> c_int,
    close_display: unsafe extern "C" fn(DdcDisplayHandle) -> c_int,
    get_value: unsafe extern "C" fn(DdcDisplayHandle, u8, *mut DdcNonTableValue) -> c_int,
    set_value: unsafe extern "C" fn(DdcDisplayHandle, u8, u8, u8) -> c_int,
    status_description: unsafe extern "C" fn(c_int) -> *const c_char,
}

impl DdcApi {
    fn load() -> Result<Self, String> {
        // SAFETY: fixed SONAMEs are tried in ABI order and copied symbols stay
        // live because this value owns the loaded library.
        unsafe {
            let library = Library::new("libddcutil.so.5")
                .or_else(|_| Library::new("libddcutil.so"))
                .map_err(|error| format!("could not load libddcutil: {error}"))?;
            macro_rules! symbol {
                ($name:literal) => {
                    *library
                        .get(concat!($name, "\0").as_bytes())
                        .map_err(|error| format!("missing libddcutil symbol {}: {error}", $name))?
                };
            }
            let display_info = match (
                library
                    .get::<unsafe extern "C" fn(DdcDisplayRef, *mut *mut DdcDisplayInfo2) -> c_int>(
                        b"ddca_get_display_info2\0",
                    ),
                library.get::<unsafe extern "C" fn(*mut DdcDisplayInfo2)>(
                    b"ddca_free_display_info2\0",
                ),
            ) {
                (Ok(get), Ok(free)) => DdcDisplayInfoApi::ConnectorAware {
                    get: *get,
                    free: *free,
                },
                _ => {
                    let get: unsafe extern "C" fn(
                        DdcDisplayRef,
                        *mut *mut DdcDisplayInfo,
                    ) -> c_int = symbol!("ddca_get_display_info");
                    let free: unsafe extern "C" fn(*mut DdcDisplayInfo) =
                        symbol!("ddca_free_display_info");
                    info!(
                        "libddcutil exposes its stable display metadata API; correlating displays through DRM sysfs"
                    );
                    DdcDisplayInfoApi::Stable { get, free }
                }
            };
            let set_value: unsafe extern "C" fn(DdcDisplayHandle, u8, u8, u8) -> c_int =
                match library.get(b"ddca_set_non_table_vcp_value2\0") {
                    Ok(symbol) => *symbol,
                    Err(preferred_error) => {
                        let symbol = library.get(b"ddca_set_non_table_vcp_value\0").map_err(
                            |legacy_error| {
                                format!(
                                    concat!(
                                        "missing libddcutil VCP setter: ",
                                        "ddca_set_non_table_vcp_value2: {}; ",
                                        "ddca_set_non_table_vcp_value: {}"
                                    ),
                                    preferred_error, legacy_error
                                )
                            },
                        )?;
                        info!(
                            "libddcutil does not expose the verification-free VCP setter; using its ABI-compatible legacy setter"
                        );
                        *symbol
                    }
                };
            Ok(Self {
                init: symbol!("ddca_init2"),
                redetect_displays: symbol!("ddca_redetect_displays"),
                get_display_refs: symbol!("ddca_get_display_refs"),
                display_info,
                open_display: symbol!("ddca_open_display2"),
                close_display: symbol!("ddca_close_display"),
                get_value: symbol!("ddca_get_non_table_vcp_value"),
                set_value,
                status_description: symbol!("ddca_rc_desc"),
                _library: library,
            })
        }
    }

    fn describe_status(&self, status: c_int) -> String {
        // SAFETY: libddcutil returns a process-lifetime NUL-terminated string.
        let description = unsafe { (self.status_description)(status) };
        if description.is_null() {
            format!("status {status}")
        } else {
            // SAFETY: checked for null and owned by the loaded library.
            unsafe { CStr::from_ptr(description) }
                .to_string_lossy()
                .into_owned()
        }
    }

    fn display_connector(
        &self,
        reference: DdcDisplayRef,
        drm_connectors: &[DrmConnectorIdentity],
    ) -> Option<String> {
        // SAFETY: the selected function/free pair belongs to the same loaded
        // ABI, and the display reference came from that library.
        unsafe {
            match self.display_info {
                DdcDisplayInfoApi::ConnectorAware { get, free } => {
                    let mut info = ptr::null_mut();
                    let status = get(reference, &mut info);
                    let connector = (status == 0 && !info.is_null()).then(|| {
                        let metadata = &*info;
                        let published = fixed_c_string(&metadata.drm_card_connector);
                        if published.is_empty() {
                            connector_for_stable_display(&metadata.legacy, drm_connectors)
                        } else {
                            Some(connector_from_ddc_name(&published))
                        }
                    });
                    if !info.is_null() {
                        free(info);
                    }
                    connector.flatten().filter(|name| !name.is_empty())
                }
                DdcDisplayInfoApi::Stable { get, free } => {
                    let mut info = ptr::null_mut();
                    let status = get(reference, &mut info);
                    let connector = (status == 0 && !info.is_null())
                        .then(|| connector_for_stable_display(&*info, drm_connectors));
                    if !info.is_null() {
                        free(info);
                    }
                    connector.flatten().filter(|name| !name.is_empty())
                }
            }
        }
    }
}

#[derive(Clone, Debug)]
struct DrmConnectorIdentity {
    name: String,
    i2c_bus: Option<c_int>,
    edid: Option<[u8; 128]>,
    canonical: Option<PathBuf>,
    device_path: Option<PathBuf>,
    status: Option<String>,
}

fn fixed_c_string(chars: &[c_char]) -> String {
    let bytes = chars
        .iter()
        .map(|character| *character as u8)
        .take_while(|character| *character != 0)
        .collect::<Vec<_>>();
    String::from_utf8_lossy(&bytes).into_owned()
}

fn drm_connector_identities(root: &Path) -> Vec<DrmConnectorIdentity> {
    let Ok(entries) = fs::read_dir(root) else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if !path.join("connector_id").is_file() {
                return None;
            }
            let name = connector_from_ddc_name(&entry.file_name().to_string_lossy());
            if name.is_empty() {
                return None;
            }
            let i2c_bus = fs::canonicalize(path.join("ddc"))
                .ok()
                .and_then(|path| {
                    path.file_name()
                        .map(|name| name.to_string_lossy().into_owned())
                })
                .and_then(|name| name.strip_prefix("i2c-").and_then(|bus| bus.parse().ok()));
            let edid = fs::read(path.join("edid"))
                .ok()
                .and_then(|bytes| bytes.get(..128).and_then(|prefix| prefix.try_into().ok()));
            let canonical = fs::canonicalize(&path).ok();
            let device_path = fs::canonicalize(path.join("device")).ok();
            let status = fs::read_to_string(path.join("status")).ok();
            Some(DrmConnectorIdentity {
                name,
                i2c_bus,
                edid,
                canonical,
                device_path,
                status,
            })
        })
        .collect()
}

fn connector_for_stable_display(
    info: &DdcDisplayInfo,
    drm_connectors: &[DrmConnectorIdentity],
) -> Option<String> {
    // I2C bus ownership is authoritative and distinguishes identical monitor
    // models. USB displays lack that relationship, so use their complete base
    // EDID only when it identifies exactly one DRM connector.
    if info.path.io_mode == 0
        && let Some(connector) = drm_connectors
            .iter()
            .find(|connector| connector.i2c_bus == Some(info.path.path))
    {
        return Some(connector.name.clone());
    }
    if info.edid_bytes.iter().all(|byte| *byte == 0) {
        return None;
    }
    let mut matches = drm_connectors
        .iter()
        .filter(|connector| connector.edid.as_ref() == Some(&info.edid_bytes));
    let connector = matches.next()?;
    matches.next().is_none().then(|| connector.name.clone())
}

struct DdcWorker {
    api: Option<DdcApi>,
    displays: HashMap<String, DdcDisplayRef>,
    init_error: Option<String>,
    last_init_attempt: Option<Instant>,
    init_attempts: usize,
    drm_root: PathBuf,
}

impl DdcWorker {
    fn new(drm_root: PathBuf) -> Self {
        Self {
            api: None,
            displays: HashMap::new(),
            init_error: None,
            last_init_attempt: None,
            init_attempts: 0,
            drm_root,
        }
    }

    #[cfg(test)]
    fn is_initialized(&self) -> bool {
        self.api.is_some()
    }

    fn ensure_initialized(&mut self) -> Result<(), String> {
        if self.api.is_some() {
            return Ok(());
        }
        if self.init_attempts >= MAX_DDC_INIT_ATTEMPTS {
            return Err(self
                .init_error
                .clone()
                .unwrap_or_else(|| "DDC unavailable".into()));
        }
        if let Some(last) = self.last_init_attempt
            && last.elapsed() < DDC_RETRY_INTERVAL
        {
            return Err(self
                .init_error
                .clone()
                .unwrap_or_else(|| "DDC unavailable".into()));
        }
        self.last_init_attempt = Some(Instant::now());
        self.init_attempts += 1;

        let api = match DdcApi::load() {
            Ok(api) => api,
            Err(error) => {
                let msg = format!("could not load libddcutil: {error}");
                self.init_error = Some(msg.clone());
                return Err(msg);
            }
        };

        // DDCA_SYSLOG_NEVER=0 and DISABLE_CONFIG_FILE=1 keep this embedded
        // controller independent from global logging/configuration policy.
        // SAFETY: null optional arguments and flags follow ddca_init2's API.
        let status = unsafe { (api.init)(ptr::null(), 0, 1, ptr::null_mut()) };
        if status != 0 {
            let msg = format!("DDC initialization failed: {}", api.describe_status(status));
            self.init_error = Some(msg.clone());
            return Err(msg);
        }

        self.api = Some(api);
        self.init_error = None;
        let outputs = self
            .refresh_displays(false)
            .map_or(0, |()| self.displays.len());
        info!(
            outputs,
            "Denial brightness registered the native DDC/CI provider"
        );
        Ok(())
    }

    fn refresh_displays(&mut self, redetect: bool) -> Result<(), String> {
        let Some(api) = self.api.as_ref() else {
            return Err("DDC is not initialized".into());
        };
        if redetect {
            // SAFETY: called only on the dedicated DDC worker.
            let status = unsafe { (api.redetect_displays)() };
            if status != 0 {
                return Err(format!(
                    "DDC display redetection failed: {}",
                    api.describe_status(status)
                ));
            }
        }
        let mut references: *mut DdcDisplayRef = ptr::null_mut();
        // SAFETY: libddcutil returns its null-terminated reference array.
        let status = unsafe { (api.get_display_refs)(false, &mut references) };
        if status != 0 || references.is_null() {
            return Err(format!(
                "DDC display enumeration failed: {}",
                api.describe_status(status)
            ));
        }
        let mut displays = HashMap::new();
        let drm_connectors = drm_connector_identities(&self.drm_root);
        let mut index = 0usize;
        loop {
            // SAFETY: get_display_refs promises a null-terminated array.
            let reference = unsafe { *references.add(index) };
            if reference.is_null() {
                break;
            }
            if let Some(connector) = api.display_connector(reference, &drm_connectors) {
                displays.insert(connector, reference);
            }
            index += 1;
        }
        self.displays = displays;
        if self.displays.is_empty() {
            Err("DDC found no controllable displays".into())
        } else {
            Ok(())
        }
    }

    fn display(&mut self, connector: &str) -> Option<DdcDisplayRef> {
        if is_internal_panel(connector) {
            return None;
        }
        if self.ensure_initialized().is_err() {
            return None;
        }
        if let Some(reference) = self.displays.get(connector) {
            return Some(*reference);
        }
        self.refresh_displays(true).ok()?;
        self.displays.get(connector).copied()
    }
}

impl BrightnessProvider for DdcWorker {
    fn name(&self) -> &'static str {
        "DDC/CI"
    }

    fn controls(&mut self, connector: &str) -> bool {
        if is_internal_panel(connector) {
            return false;
        }
        self.display(connector).is_some()
    }

    fn read(&mut self, connector: &str) -> Result<f64, String> {
        let Some(reference) = self.display(connector) else {
            return Err("has no matching DDC display".into());
        };
        let Some(api) = self.api.as_ref() else {
            return Err("DDC is not initialized".into());
        };
        let mut handle = ptr::null_mut();
        // SAFETY: reference is owned by libddcutil and all use is serialized.
        let open_status = unsafe { (api.open_display)(reference, false, &mut handle) };
        if open_status != 0 || handle.is_null() {
            let detail = api.describe_status(open_status);
            return Err(format!("could not open DDC display: {detail}"));
        }

        let mut value = DdcNonTableValue::default();
        // SAFETY: handle is open and value is a complete response buffer.
        let read_status = unsafe { (api.get_value)(handle, 0x10, &mut value) };
        let maximum = u16::from_be_bytes([value.maximum_high, value.maximum_low]);
        let current = u16::from_be_bytes([value.current_high, value.current_low]);
        if read_status != 0 || maximum == 0 {
            // SAFETY: balances the successful open above.
            unsafe { (api.close_display)(handle) };
            let detail = api.describe_status(read_status);
            return Err(format!("could not read VCP 0x10: {detail}"));
        }
        // SAFETY: balances the successful open above.
        unsafe { (api.close_display)(handle) };
        Ok(f64::from(current) / f64::from(maximum))
    }

    fn set(&mut self, connector: &str, level: f64) -> Result<(), String> {
        let Some(reference) = self.display(connector) else {
            return Err("has no matching DDC display".into());
        };
        let Some(api) = self.api.as_ref() else {
            return Err("DDC is not initialized".into());
        };
        let mut handle = ptr::null_mut();
        // SAFETY: reference is owned by libddcutil and all use is serialized.
        let open_status = unsafe { (api.open_display)(reference, false, &mut handle) };
        if open_status != 0 || handle.is_null() {
            let detail = api.describe_status(open_status);
            return Err(format!("could not open DDC display: {detail}"));
        }
        let mut value = DdcNonTableValue::default();
        // SAFETY: handle is open and value is a complete response buffer.
        let read_status = unsafe { (api.get_value)(handle, 0x10, &mut value) };
        let maximum = u16::from_be_bytes([value.maximum_high, value.maximum_low]);
        if read_status != 0 || maximum == 0 {
            // SAFETY: balances the successful open above.
            unsafe { (api.close_display)(handle) };
            let detail = api.describe_status(read_status);
            return Err(format!("could not read VCP 0x10: {detail}"));
        }
        let target_value = (level.clamp(0.0, 1.0) * f64::from(maximum)).round() as u16;
        let [high, low] = target_value.to_be_bytes();
        // SAFETY: handle is open and the VCP payload is two scalar bytes.
        let write_status = unsafe { (api.set_value)(handle, 0x10, high, low) };
        // SAFETY: balances the successful open above.
        unsafe { (api.close_display)(handle) };
        if write_status != 0 {
            let detail = api.describe_status(write_status);
            return Err(format!("could not write VCP 0x10: {detail}"));
        }
        Ok(())
    }
}

#[derive(Clone, Copy)]
enum BrightnessChange {
    Set(f64),
    Adjust(f64),
}

fn connector_from_ddc_name(name: &str) -> String {
    let name = name.trim_matches(char::from(0));
    if let Some(rest) = name.strip_prefix("card")
        && let Some((_, connector)) = rest.split_once('-')
    {
        return connector.to_owned();
    }
    name.to_owned()
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PendingBrightnessCommand {
    Read,
    Set(f64),
    Adjust(f64),
}

fn brightness_command_parts(
    command: BrightnessCommand,
) -> Option<(String, i64, PendingBrightnessCommand)> {
    match command {
        BrightnessCommand::Read {
            connector,
            monitor_id,
        } => Some((connector, monitor_id, PendingBrightnessCommand::Read)),
        BrightnessCommand::Set {
            connector,
            monitor_id,
            level,
        } => Some((connector, monitor_id, PendingBrightnessCommand::Set(level))),
        BrightnessCommand::Adjust {
            connector,
            monitor_id,
            delta,
        } => Some((
            connector,
            monitor_id,
            PendingBrightnessCommand::Adjust(delta),
        )),
        BrightnessCommand::Stop => None,
    }
}

fn merge_brightness_command(
    pending: &mut HashMap<String, (i64, PendingBrightnessCommand)>,
    connector: String,
    monitor_id: i64,
    incoming: PendingBrightnessCommand,
) {
    let Some((saved_monitor_id, saved)) = pending.get_mut(&connector) else {
        pending.insert(connector, (monitor_id, incoming));
        return;
    };
    *saved_monitor_id = monitor_id;
    *saved = match (*saved, incoming) {
        (saved, PendingBrightnessCommand::Read) => saved,
        (_, PendingBrightnessCommand::Set(level)) => PendingBrightnessCommand::Set(level),
        (PendingBrightnessCommand::Set(level), PendingBrightnessCommand::Adjust(delta)) => {
            PendingBrightnessCommand::Set((level + delta).clamp(0.0, 1.0))
        }
        (PendingBrightnessCommand::Adjust(delta), PendingBrightnessCommand::Adjust(next)) => {
            PendingBrightnessCommand::Adjust((delta + next).clamp(-1.0, 1.0))
        }
        (PendingBrightnessCommand::Read, PendingBrightnessCommand::Adjust(delta)) => {
            PendingBrightnessCommand::Adjust(delta)
        }
    };
}

fn receive_brightness_batch(
    first: BrightnessCommand,
    commands: &Receiver<BrightnessCommand>,
) -> Option<HashMap<String, (i64, PendingBrightnessCommand)>> {
    let (connector, monitor_id, command) = brightness_command_parts(first)?;
    let mut pending = HashMap::new();
    merge_brightness_command(&mut pending, connector, monitor_id, command);
    let deadline = Instant::now() + DDC_COALESCE_WINDOW;
    loop {
        let timeout = deadline.saturating_duration_since(Instant::now());
        match commands.recv_timeout(timeout) {
            Ok(command) => {
                let (connector, monitor_id, command) = brightness_command_parts(command)?;
                merge_brightness_command(&mut pending, connector, monitor_id, command);
            }
            Err(RecvTimeoutError::Disconnected) => return None,
            Err(RecvTimeoutError::Timeout) => return Some(pending),
        }
    }
}

fn run_brightness_worker(
    commands: Receiver<BrightnessCommand>,
    events: SyncSender<SystemControlEvent>,
) {
    let mut worker = match BrightnessProviders::start() {
        Ok(worker) => worker,
        Err(error) => {
            warn!(%error, "native brightness controls are unavailable");
            while !matches!(commands.recv(), Ok(BrightnessCommand::Stop) | Err(_)) {}
            return;
        }
    };
    while let Ok(first) = commands.recv() {
        let Some(batch) = receive_brightness_batch(first, &commands) else {
            break;
        };
        for (connector, (monitor_id, command)) in batch {
            match command {
                PendingBrightnessCommand::Read => worker.read(&connector, monitor_id, &events),
                PendingBrightnessCommand::Set(level) => {
                    worker.set(&connector, monitor_id, level, &events);
                }
                PendingBrightnessCommand::Adjust(delta) => {
                    worker.adjust(&connector, monitor_id, delta, &events);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::{offset_of, size_of};

    struct FakeBrightnessProvider {
        provider_name: &'static str,
        connector: &'static str,
        level: f64,
    }

    impl BrightnessProvider for FakeBrightnessProvider {
        fn name(&self) -> &'static str {
            self.provider_name
        }

        fn controls(&mut self, connector: &str) -> bool {
            connector == self.connector
        }

        fn read(&mut self, connector: &str) -> Result<f64, String> {
            self.controls(connector)
                .then_some(self.level)
                .ok_or_else(|| "unclaimed output".into())
        }

        fn set(&mut self, connector: &str, level: f64) -> Result<(), String> {
            if !self.controls(connector) {
                return Err("unclaimed output".into());
            }
            self.level = level;
            Ok(())
        }
    }

    #[test]
    fn native_control_ffi_prefixes_match_the_installed_stable_abi() {
        assert_eq!(size_of::<PaSampleSpec>(), 12);
        assert_eq!(size_of::<PaChannelMap>(), 132);
        assert_eq!(size_of::<PaCVolume>(), 132);
        assert_eq!(offset_of!(PaServerInfo, default_sink_name), 48);
        assert_eq!(offset_of!(PaSinkInfoPrefix, volume), 172);
        assert_eq!(offset_of!(PaSinkInfoPrefix, mute), 304);
        assert_eq!(offset_of!(PaSinkInputInfoPrefix, volume), 172);
        assert_eq!(offset_of!(PaSinkInputInfoPrefix, mute), 336);
        assert_eq!(offset_of!(PaSinkInputInfoPrefix, proplist), 344);

        assert_eq!(offset_of!(DdcDisplayInfo, dref), 192);
        assert_eq!(size_of::<DdcDisplayInfo>(), 200);
        assert_eq!(offset_of!(DdcDisplayInfo2, drm_card_connector), 200);
        assert_eq!(size_of::<DdcDisplayInfo2>(), 304);
        assert_eq!(size_of::<DdcNonTableValue>(), 4);
    }

    #[test]
    fn stable_ddc_metadata_prefers_i2c_identity_and_rejects_ambiguous_edids() {
        let edid = [7; 128];
        let connectors = [
            DrmConnectorIdentity {
                name: "DP-1".into(),
                i2c_bus: Some(8),
                edid: Some(edid),
                canonical: None,
                device_path: None,
                status: None,
            },
            DrmConnectorIdentity {
                name: "DP-2".into(),
                i2c_bus: Some(9),
                edid: Some(edid),
                canonical: None,
                device_path: None,
                status: None,
            },
        ];
        let display = DdcDisplayInfo {
            marker: [0; 4],
            dispno: 1,
            path: DdcIoPath {
                io_mode: 0,
                path: 9,
            },
            usb_bus: 0,
            usb_device: 0,
            mfg_id: [0; 4],
            model_name: [0; 14],
            serial: [0; 14],
            product_code: 0,
            edid_bytes: edid,
            vcp_version: [0; 2],
            dref: ptr::null_mut(),
        };
        assert_eq!(
            connector_for_stable_display(&display, &connectors).as_deref(),
            Some("DP-2")
        );

        let usb_display = DdcDisplayInfo {
            path: DdcIoPath {
                io_mode: 1,
                path: 0,
            },
            ..display
        };
        assert_eq!(
            connector_for_stable_display(&usb_display, &connectors),
            None
        );
        assert_eq!(
            connector_for_stable_display(&usb_display, &connectors[..1]).as_deref(),
            Some("DP-1")
        );
    }

    #[test]
    fn brightness_providers_coexist_and_claim_outputs_independently() {
        let mut controls = BrightnessProviders {
            providers: vec![
                Box::new(FakeBrightnessProvider {
                    provider_name: "kernel backlight",
                    connector: "eDP-1",
                    level: 0.5,
                }),
                Box::new(FakeBrightnessProvider {
                    provider_name: "DDC/CI",
                    connector: "DP-1",
                    level: 0.8,
                }),
            ],
            desired: HashMap::new(),
            failure_latched: HashMap::new(),
        };
        let (sender, receiver) = mpsc::sync_channel(8);

        controls.set("eDP-1", 1, 0.35, &sender);
        assert_eq!(
            receiver.recv().unwrap(),
            SystemControlEvent::BrightnessLevel {
                monitor_id: 1,
                level: 0.35,
            }
        );
        controls.read("eDP-1", 1, &sender);
        assert_eq!(
            receiver.recv().unwrap(),
            SystemControlEvent::BrightnessLevel {
                monitor_id: 1,
                level: 0.35,
            }
        );

        controls.set("DP-1", 2, 0.65, &sender);
        assert_eq!(
            receiver.recv().unwrap(),
            SystemControlEvent::BrightnessLevel {
                monitor_id: 2,
                level: 0.65,
            }
        );
        controls.read("DP-1", 2, &sender);
        assert_eq!(
            receiver.recv().unwrap(),
            SystemControlEvent::BrightnessLevel {
                monitor_id: 2,
                level: 0.65,
            }
        );
    }

    #[test]
    fn kernel_backlights_are_limited_to_internal_connectors() {
        assert!(internal_connector("eDP-1"));
        assert!(internal_connector("LVDS-1"));
        assert!(internal_connector("DSI-1"));
        assert!(internal_connector("DPI-1"));
        assert!(!internal_connector("DP-1"));
        assert!(!internal_connector("HDMI-A-1"));
        assert!(connected_internal_connector("eDP-1", "connected\n"));
        assert!(!connected_internal_connector("eDP-2", "disconnected\n"));
        assert!(!connected_internal_connector("DP-1", "connected\n"));
    }

    #[test]
    fn internal_panel_connectors_are_classified_by_type() {
        for connector in [
            "eDP-1", "edp-2", "LVDS-1", "lvds-2", "DSI-1", "dsi-2", "DPI-1", "dpi-2",
        ] {
            assert!(is_internal_panel(connector), "{connector} is internal");
        }
        for connector in ["DP-1", "HDMI-A-1", "DVI-D-1", "Writeback-1", "VGA-1"] {
            assert!(!is_internal_panel(connector), "{connector} is external");
        }
    }

    #[test]
    fn sysfs_backlight_never_writes_a_dark_panel() {
        let device = BacklightDevice {
            name: "nvidia_0".into(),
            path: PathBuf::from("/nonexistent"),
            device_path: PathBuf::from("/nonexistent"),
            kind: "raw".into(),
            maximum: 100,
        };
        assert_eq!(device.raw_for(0.0), 1);
        assert_eq!(device.raw_for(-1.0), 1);
        assert_eq!(device.raw_for(0.5), 50);
        assert_eq!(device.raw_for(1.0), 100);
        assert_eq!(device.raw_for(4.0), 100);
    }

    /// Reproduces this class of laptop: a discrete GPU carrying the panel and
    /// an external output, plus an integrated GPU with its own unused eDP. Only
    /// the discrete panel may claim the backlight.
    #[test]
    fn sysfs_backlights_match_only_the_internal_panel_on_the_owning_gpu() {
        let suffix = std::process::id();
        let root = std::env::temp_dir().join(format!("denial-backlight-test-{suffix}"));
        let _ = fs::remove_dir_all(&root);
        let discrete = root.join("devices/pci0000:00/0000:01:00.0");
        let integrated = root.join("devices/pci0000:00/0000:05:00.0");
        let backlight_device = discrete.join("backlight/nvidia_0");
        fs::create_dir_all(&backlight_device).expect("create backlight device");
        fs::write(backlight_device.join("max_brightness"), "100\n").expect("write maximum");
        fs::write(backlight_device.join("actual_brightness"), "40\n").expect("write level");

        let class_root = root.join("class/backlight");
        let drm_root = root.join("class/drm");
        fs::create_dir_all(&class_root).expect("create backlight class");
        fs::create_dir_all(&drm_root).expect("create drm class");
        std::os::unix::fs::symlink(&backlight_device, class_root.join("nvidia_0"))
            .expect("link backlight");
        std::os::unix::fs::symlink(&discrete, backlight_device.join("device"))
            .expect("link backlight owner");

        for (connector, gpu) in [
            ("card1-eDP-1", &discrete),
            ("card1-HDMI-A-1", &discrete),
            ("card2-eDP-2", &integrated),
        ] {
            let target = gpu.join(format!("drm/{connector}"));
            fs::create_dir_all(&target).expect("create connector");
            fs::write(target.join("connector_id"), "1\n").expect("write connector id");
            std::os::unix::fs::symlink(&target, drm_root.join(connector)).expect("link connector");
        }

        let backlights = discover_backlights(&class_root, &drm_root);
        assert_eq!(
            backlights.keys().cloned().collect::<Vec<_>>(),
            vec!["eDP-1"]
        );
        let panel = &backlights["eDP-1"];
        assert_eq!(panel.name, "nvidia_0");
        assert_eq!(panel.maximum, 100);
        assert_eq!(panel.level(), Some(0.4));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lazy_ddc_is_not_initialized_for_internal_panel_requests() {
        let mut worker = DdcWorker::new(PathBuf::from("/nonexistent/drm"));
        assert!(!worker.is_initialized());
        // Internal panel requests must be rejected immediately without initializing DDC
        assert!(!worker.controls("eDP-1"));
        assert!(!worker.controls("edp-2"));
        assert!(!worker.controls("LVDS-1"));
        assert!(!worker.controls("DSI-1"));
        assert!(!worker.controls("DPI-1"));
        assert!(!worker.is_initialized());
    }

    #[test]
    fn logind_brightness_constants_and_timeout() {
        assert_eq!(LOGIND_SERVICE, "org.freedesktop.login1");
        assert_eq!(LOGIND_MANAGER_OBJECT, "/org/freedesktop/login1");
        assert_eq!(LOGIND_MANAGER_INTERFACE, "org.freedesktop.login1.Manager");
        assert_eq!(LOGIND_SESSION_INTERFACE, "org.freedesktop.login1.Session");
        assert_eq!(LOGIND_DBUS_TIMEOUT, Duration::from_millis(500));
        assert_eq!(MIN_BACKLIGHT_RAW, 1);
    }

    #[test]
    fn flutter_audio_packets_decode_strictly_and_clamp_percentages() {
        assert_eq!(decode_audio_request(&[0]).unwrap(), AudioRequest::ReadLevel);
        assert_eq!(
            decode_audio_request(&[1, 140, 0x78, 0x56, 0x34, 0x12]).unwrap(),
            AudioRequest::SetLevel {
                level: 1.0,
                request_serial: 0x1234_5678,
            }
        );
        assert_eq!(
            decode_audio_request(&[2]).unwrap(),
            AudioRequest::RequestStreams
        );
        assert_eq!(
            decode_audio_request(&[3, 7, 0, 0, 0, 25]).unwrap(),
            AudioRequest::SetStreamLevel {
                stream_id: 7,
                level: 0.25,
            }
        );
        assert_eq!(
            decode_audio_request(&[1, 50]).unwrap_err(),
            AudioRequestDecodeError::InvalidSize(2)
        );
        assert_eq!(
            decode_audio_request(&[9]).unwrap_err(),
            AudioRequestDecodeError::UnsupportedCommand(9)
        );
    }

    #[test]
    fn flutter_brightness_packets_target_one_monitor_strictly() {
        let mut packet = vec![1, 0, 0, 0, 0, 0, 0, 0, 0, 125, 4, 0];
        packet.extend_from_slice(b"DP-4");
        assert_eq!(
            decode_brightness_request(&packet).unwrap(),
            BrightnessRequest::Set {
                connector: "DP-4".into(),
                monitor_id: 0,
                level: 1.0,
            }
        );

        packet[0] = 0;
        assert_eq!(
            decode_brightness_request(&packet).unwrap(),
            BrightnessRequest::Read {
                connector: "DP-4".into(),
                monitor_id: 0,
            }
        );
        assert_eq!(
            decode_brightness_request(&packet[..12]).unwrap_err(),
            BrightnessRequestDecodeError::InvalidSize(12)
        );
        packet[0] = 9;
        assert_eq!(
            decode_brightness_request(&packet).unwrap_err(),
            BrightnessRequestDecodeError::UnsupportedCommand(9)
        );
    }

    #[test]
    fn audio_stream_names_truncate_only_at_utf8_boundaries() {
        assert_eq!(truncate_utf8("Denial".into(), 16), "Denial");
        assert_eq!(truncate_utf8("Denia 🌊".into(), 9), "Denia ");
    }

    #[test]
    fn ddc_connector_names_drop_only_the_card_prefix() {
        assert_eq!(connector_from_ddc_name("card2-DP-4"), "DP-4");
        assert_eq!(connector_from_ddc_name("DP-4"), "DP-4");
        assert_eq!(connector_from_ddc_name("card2-HDMI-A-1"), "HDMI-A-1");
    }

    #[test]
    fn brightness_batch_coalesces_detents_per_connector() {
        let (sender, receiver) = mpsc::channel();
        sender
            .send(BrightnessCommand::Adjust {
                connector: "DP-4".into(),
                monitor_id: 4,
                delta: CONTROL_STEP,
            })
            .unwrap();
        sender
            .send(BrightnessCommand::Adjust {
                connector: "DP-4".into(),
                monitor_id: 4,
                delta: CONTROL_STEP,
            })
            .unwrap();
        let first = receiver.recv().unwrap();
        let batch = receive_brightness_batch(first, &receiver).unwrap();
        assert_eq!(batch["DP-4"], (4, PendingBrightnessCommand::Adjust(0.10)));
    }

    #[test]
    fn brightness_read_cannot_discard_a_pending_write() {
        let mut pending = HashMap::new();
        merge_brightness_command(
            &mut pending,
            "DP-4".into(),
            4,
            PendingBrightnessCommand::Set(0.61),
        );
        merge_brightness_command(
            &mut pending,
            "DP-4".into(),
            4,
            PendingBrightnessCommand::Read,
        );
        assert_eq!(pending["DP-4"], (4, PendingBrightnessCommand::Set(0.61)));
    }
}
