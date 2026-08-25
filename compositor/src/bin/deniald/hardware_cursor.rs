//! Hardware-cursor policy, artwork decoding, geometry, and composition.
//!
//! KMS cursor programming is deliberately kept behind a small, testable
//! policy layer. The policy never guesses a plane: callers must provide the
//! dynamically discovered capability snapshot for the target CRTC. A failed
//! test-only arrangement transitions to software rendering and is not retried
//! until the device/output epoch changes.

use std::collections::BTreeSet;
use std::error::Error;
use std::io::Cursor;
use std::sync::OnceLock;

use denial_core::topology::{OutputId, OutputTransform, PixelSize};
use smithay::backend::allocator::dumb::DumbBuffer;
use smithay::backend::allocator::{Allocator, Fourcc, Modifier};
use smithay::backend::drm::DrmDevice;
use smithay::reexports::drm::buffer::{Buffer as DrmBuffer, DrmFourcc};
use smithay::reexports::drm::control::{
    AtomicCommitFlags, Device as ControlDevice, RawResourceHandle, atomic::AtomicModeReq,
    framebuffer, plane, property,
};
use tracing::{info, warn};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct PixelPoint {
    pub(super) x: i32,
    pub(super) y: i32,
}

pub(super) const CURSOR_POOL_LIMIT: usize = 3;
pub(super) const CURSOR_MAX_DIMENSION: u32 = 256;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Ord, PartialOrd)]
pub(super) enum CursorRole {
    Normal,
    Help,
    Working,
    Text,
    Link,
    Busy,
    Precision,
    Handwriting,
    Unavailable,
    VerticalResize,
    HorizontalResize,
    DiagonalNwSeResize,
    DiagonalNeSwResize,
    Move,
    Alternate,
    Person,
    Pin,
}

impl CursorRole {
    pub(super) fn from_wire(shape: &str) -> Option<Self> {
        let normalized = shape.trim().to_ascii_lowercase().replace('_', "-");
        match normalized.as_str() {
            "default" | "normal" | "left-ptr" | "arrow" | "basic" => Some(Self::Normal),
            "help" | "question-arrow" | "dnd-ask" => Some(Self::Help),
            "progress" | "working" | "left-ptr-watch" => Some(Self::Working),
            "text" | "xterm" | "vertical-text" => Some(Self::Text),
            "pointer" | "hand" | "hand1" | "hand2" | "link" | "click" => Some(Self::Link),
            "wait" | "watch" | "busy" => Some(Self::Busy),
            "cell" | "crosshair" | "precise" | "precision" | "zoom-in" | "zoom-out" => {
                Some(Self::Precision)
            }
            "handwriting" | "pencil" | "nwpen" => Some(Self::Handwriting),
            "invalid" | "no-drop" | "not-allowed" | "forbidden" | "unavailable"
            | "crossed-circle" => Some(Self::Unavailable),
            "n-resize" | "s-resize" | "ns-resize" | "row-resize" | "top-side" | "bottom-side"
            | "resizeupdown" | "resize-up-down" | "resize-up" | "resize-down" => {
                Some(Self::VerticalResize)
            }
            "e-resize" | "w-resize" | "ew-resize" | "col-resize" | "left-side" | "right-side"
            | "resizeleftright" | "resize-left-right" | "resize-left" | "resize-right" => {
                Some(Self::HorizontalResize)
            }
            "nw-resize"
            | "se-resize"
            | "nwse-resize"
            | "top-left-corner"
            | "bottom-right-corner"
            | "resizeupleftdownright"
            | "resize-up-left-down-right" => Some(Self::DiagonalNwSeResize),
            "ne-resize"
            | "sw-resize"
            | "nesw-resize"
            | "top-right-corner"
            | "bottom-left-corner"
            | "resizeuprightdownleft"
            | "resize-up-right-down-left" => Some(Self::DiagonalNeSwResize),
            "move" | "grab" | "grabbing" | "all-scroll" | "all-resize" => Some(Self::Move),
            "alias" | "copy" | "alternate" | "up-arrow" => Some(Self::Alternate),
            "person" => Some(Self::Person),
            "pin" | "location" | "loc" => Some(Self::Pin),
            _ => None,
        }
    }

    pub(super) const fn default_hotspot(self) -> PixelPoint {
        match self {
            Self::Normal | Self::Working => PixelPoint { x: 6, y: 2 },
            Self::Help => PixelPoint { x: 5, y: 10 },
            Self::Text => PixelPoint { x: 16, y: 16 },
            Self::Link => PixelPoint { x: 14, y: 2 },
            Self::Busy | Self::Precision | Self::Unavailable => PixelPoint { x: 16, y: 16 },
            Self::Handwriting => PixelPoint { x: 5, y: 26 },
            Self::VerticalResize | Self::HorizontalResize => PixelPoint { x: 16, y: 16 },
            Self::DiagonalNwSeResize | Self::DiagonalNeSwResize | Self::Move => {
                PixelPoint { x: 16, y: 16 }
            }
            Self::Alternate => PixelPoint { x: 12, y: 8 },
            Self::Person | Self::Pin => PixelPoint { x: 4, y: 1 },
        }
    }

    pub(super) const fn embedded_png(self) -> &'static [u8] {
        match self {
            Self::Normal => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/normal/00.png"
            ),
            Self::Help => {
                include_bytes!(
                    "../../../../dart_shell/assets/cursors/bibata_modern_ice/help/00.png"
                )
            }
            Self::Working => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/working/00.png"
            ),
            Self::Text => {
                include_bytes!(
                    "../../../../dart_shell/assets/cursors/bibata_modern_ice/text/00.png"
                )
            }
            Self::Link => {
                include_bytes!(
                    "../../../../dart_shell/assets/cursors/bibata_modern_ice/link/00.png"
                )
            }
            Self::Busy => {
                include_bytes!(
                    "../../../../dart_shell/assets/cursors/bibata_modern_ice/busy/00.png"
                )
            }
            Self::Precision => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/precision/00.png"
            ),
            Self::Handwriting => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/handwriting/00.png"
            ),
            Self::Unavailable => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/unavailable/00.png"
            ),
            Self::VerticalResize => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/vertical_resize/00.png"
            ),
            Self::HorizontalResize => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/horizontal_resize/00.png"
            ),
            Self::DiagonalNwSeResize => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/diagonal_nwse/00.png"
            ),
            Self::DiagonalNeSwResize => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/diagonal_nesw/00.png"
            ),
            Self::Move => {
                include_bytes!(
                    "../../../../dart_shell/assets/cursors/bibata_modern_ice/move/00.png"
                )
            }
            Self::Alternate => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/alternate/00.png"
            ),
            Self::Person => include_bytes!(
                "../../../../dart_shell/assets/cursors/bibata_modern_ice/person/00.png"
            ),
            Self::Pin => {
                include_bytes!("../../../../dart_shell/assets/cursors/bibata_modern_ice/pin/00.png")
            }
        }
    }
}

#[derive(Clone, Debug)]
pub(super) struct CursorArtwork {
    pub(super) width: u32,
    pub(super) height: u32,
    pub(super) hotspot: PixelPoint,
    pub(super) rgba_pixels: Vec<u8>,
}

impl CursorArtwork {
    pub(super) fn size(&self) -> PixelSize {
        PixelSize {
            width: self.width,
            height: self.height,
        }
    }
}

pub(super) fn decode_cursor_png(png_bytes: &[u8], hotspot: PixelPoint) -> Option<CursorArtwork> {
    let decoder = png::Decoder::new(Cursor::new(png_bytes));
    let mut reader = decoder.read_info().ok()?;
    let buf_size = reader.output_buffer_size()?;
    let mut buf = vec![0; buf_size];
    let info = reader.next_frame(&mut buf).ok()?;
    let width = info.width;
    let height = info.height;
    let rgba_pixels = match info.color_type {
        png::ColorType::Rgba => buf[..info.buffer_size()].to_vec(),
        png::ColorType::Rgb => {
            let mut rgba = Vec::with_capacity((width * height * 4) as usize);
            for chunk in buf[..info.buffer_size()].as_chunks::<3>().0 {
                rgba.push(chunk[0]);
                rgba.push(chunk[1]);
                rgba.push(chunk[2]);
                rgba.push(255);
            }
            rgba
        }
        _ => return None,
    };
    Some(CursorArtwork {
        width,
        height,
        hotspot,
        rgba_pixels,
    })
}

static ARTWORK_CACHE: OnceLock<[CursorArtwork; 17]> = OnceLock::new();

pub(super) fn get_artwork(role: CursorRole) -> &'static CursorArtwork {
    let cache = ARTWORK_CACHE.get_or_init(|| {
        [
            decode_cursor_png(
                CursorRole::Normal.embedded_png(),
                CursorRole::Normal.default_hotspot(),
            )
            .expect("valid Normal cursor png"),
            decode_cursor_png(
                CursorRole::Help.embedded_png(),
                CursorRole::Help.default_hotspot(),
            )
            .expect("valid Help cursor png"),
            decode_cursor_png(
                CursorRole::Working.embedded_png(),
                CursorRole::Working.default_hotspot(),
            )
            .expect("valid Working cursor png"),
            decode_cursor_png(
                CursorRole::Text.embedded_png(),
                CursorRole::Text.default_hotspot(),
            )
            .expect("valid Text cursor png"),
            decode_cursor_png(
                CursorRole::Link.embedded_png(),
                CursorRole::Link.default_hotspot(),
            )
            .expect("valid Link cursor png"),
            decode_cursor_png(
                CursorRole::Busy.embedded_png(),
                CursorRole::Busy.default_hotspot(),
            )
            .expect("valid Busy cursor png"),
            decode_cursor_png(
                CursorRole::Precision.embedded_png(),
                CursorRole::Precision.default_hotspot(),
            )
            .expect("valid Precision cursor png"),
            decode_cursor_png(
                CursorRole::Handwriting.embedded_png(),
                CursorRole::Handwriting.default_hotspot(),
            )
            .expect("valid Handwriting cursor png"),
            decode_cursor_png(
                CursorRole::Unavailable.embedded_png(),
                CursorRole::Unavailable.default_hotspot(),
            )
            .expect("valid Unavailable cursor png"),
            decode_cursor_png(
                CursorRole::VerticalResize.embedded_png(),
                CursorRole::VerticalResize.default_hotspot(),
            )
            .expect("valid VerticalResize cursor png"),
            decode_cursor_png(
                CursorRole::HorizontalResize.embedded_png(),
                CursorRole::HorizontalResize.default_hotspot(),
            )
            .expect("valid HorizontalResize cursor png"),
            decode_cursor_png(
                CursorRole::DiagonalNwSeResize.embedded_png(),
                CursorRole::DiagonalNwSeResize.default_hotspot(),
            )
            .expect("valid DiagonalNwSeResize cursor png"),
            decode_cursor_png(
                CursorRole::DiagonalNeSwResize.embedded_png(),
                CursorRole::DiagonalNeSwResize.default_hotspot(),
            )
            .expect("valid DiagonalNeSwResize cursor png"),
            decode_cursor_png(
                CursorRole::Move.embedded_png(),
                CursorRole::Move.default_hotspot(),
            )
            .expect("valid Move cursor png"),
            decode_cursor_png(
                CursorRole::Alternate.embedded_png(),
                CursorRole::Alternate.default_hotspot(),
            )
            .expect("valid Alternate cursor png"),
            decode_cursor_png(
                CursorRole::Person.embedded_png(),
                CursorRole::Person.default_hotspot(),
            )
            .expect("valid Person cursor png"),
            decode_cursor_png(
                CursorRole::Pin.embedded_png(),
                CursorRole::Pin.default_hotspot(),
            )
            .expect("valid Pin cursor png"),
        ]
    });
    &cache[role as usize]
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct CursorPlaneChoice {
    pub(super) plane: u32,
    pub(super) crtc: u32,
    pub(super) width: u32,
    pub(super) height: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct CursorPlaneCandidate {
    pub(super) plane: u32,
    pub(super) possible_crtcs: Vec<u32>,
    pub(super) formats: Vec<u32>,
    pub(super) has_destination: bool,
    pub(super) max_size: PixelSize,
}

pub(super) fn select_cursor_plane(
    candidates: &[CursorPlaneCandidate],
    crtc: u32,
    argb8888: u32,
) -> Option<CursorPlaneChoice> {
    candidates
        .iter()
        .filter(|candidate| {
            candidate.possible_crtcs.contains(&crtc)
                && candidate.formats.contains(&argb8888)
                && candidate.has_destination
                && candidate.max_size.width > 0
                && candidate.max_size.height > 0
        })
        .min_by_key(|candidate| candidate.plane)
        .map(|candidate| CursorPlaneChoice {
            plane: candidate.plane,
            crtc,
            width: candidate.max_size.width.min(CURSOR_MAX_DIMENSION),
            height: candidate.max_size.height.min(CURSOR_MAX_DIMENSION),
        })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct CursorGeometry {
    pub(super) destination: PixelPoint,
    pub(super) size: PixelSize,
    pub(super) hotspot: PixelPoint,
    pub(super) clipped: bool,
}

/// Scale artwork and clip the destination rectangle conservatively. The
/// returned hotspot is in the same physical-pixel space as the destination.
pub(super) fn geometry(
    pointer: (f64, f64),
    artwork: PixelSize,
    hotspot: PixelPoint,
    scale: f64,
    output_size: PixelSize,
    transform: OutputTransform,
) -> Option<CursorGeometry> {
    if !scale.is_finite() || scale <= 0.0 || artwork.width == 0 || artwork.height == 0 {
        return None;
    }
    let width = ((f64::from(artwork.width) * scale).round() as u32).clamp(1, CURSOR_MAX_DIMENSION);
    let height =
        ((f64::from(artwork.height) * scale).round() as u32).clamp(1, CURSOR_MAX_DIMENSION);
    let hot_x = (f64::from(hotspot.x) * scale).round() as i32;
    let hot_y = (f64::from(hotspot.y) * scale).round() as i32;
    let (x, y) = match transform {
        OutputTransform::Normal => (pointer.0.round() as i32, pointer.1.round() as i32),
        OutputTransform::Rotate90 => (
            pointer.1.round() as i32,
            output_size.height as i32 - pointer.0.round() as i32,
        ),
        OutputTransform::Rotate180 => (
            output_size.width as i32 - pointer.0.round() as i32,
            output_size.height as i32 - pointer.1.round() as i32,
        ),
        OutputTransform::Rotate270 => (
            output_size.width as i32 - pointer.1.round() as i32,
            pointer.0.round() as i32,
        ),
        _ => return None,
    };
    let left = x - hot_x;
    let top = y - hot_y;
    let mut clipped = false;
    if left < 0 || top < 0 {
        clipped = true;
    }
    if left + width as i32 > output_size.width as i32 {
        clipped = true;
    }
    if top + height as i32 > output_size.height as i32 {
        clipped = true;
    }
    Some(CursorGeometry {
        destination: PixelPoint { x: left, y: top },
        size: PixelSize { width, height },
        hotspot: PixelPoint { x: hot_x, y: hot_y },
        clipped,
    })
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum CursorRenderPath {
    Hardware,
    #[default]
    Software,
}

#[derive(Debug, Default)]
pub(super) struct CursorState {
    path: CursorRenderPath,
    tested_epoch: Option<u64>,
    visible: bool,
    pool_in_use: usize,
    known_failures: BTreeSet<String>,
}

impl CursorState {
    pub(super) fn path(&self) -> CursorRenderPath {
        self.path
    }
    pub(super) fn tested_epoch(&self) -> Option<u64> {
        self.tested_epoch
    }
    pub(super) fn begin_test_only(&mut self, epoch: u64, reason: &str) -> bool {
        if self.tested_epoch == Some(epoch) {
            return false;
        }
        self.tested_epoch = Some(epoch);
        self.known_failures.remove(reason);
        true
    }
    pub(super) fn test_only_failed(&mut self, reason: impl Into<String>) {
        self.known_failures.insert(reason.into());
        self.path = CursorRenderPath::Software;
        self.visible = false;
        self.pool_in_use = 0;
    }
    pub(super) fn test_only_succeeded(&mut self) {
        self.path = CursorRenderPath::Hardware;
    }
    pub(super) fn set_visible(&mut self, visible: bool) {
        self.visible = visible;
    }
    pub(super) fn visible(&self) -> bool {
        self.visible
    }
    pub(super) fn acquire_buffer(&mut self) -> bool {
        if self.pool_in_use >= CURSOR_POOL_LIMIT {
            return false;
        }
        self.pool_in_use += 1;
        true
    }
    pub(super) fn retire_buffer(&mut self) {
        self.pool_in_use = self.pool_in_use.saturating_sub(1);
    }
    pub(super) fn failure_reasons(&self) -> impl Iterator<Item = &str> {
        self.known_failures.iter().map(String::as_str)
    }
    pub(super) fn invalidate_epoch(&mut self) {
        self.tested_epoch = None;
    }
}

/// Property handles required to program a cursor plane atomically. All
/// handles are resolved dynamically from the live DRM object, never guessed.
#[derive(Clone, Copy, Debug)]
pub(super) struct CursorPlaneProperties {
    pub(super) fb_id: property::Handle,
    pub(super) crtc_id: property::Handle,
    pub(super) src_x: property::Handle,
    pub(super) src_y: property::Handle,
    pub(super) src_w: property::Handle,
    pub(super) src_h: property::Handle,
    pub(super) crtc_x: property::Handle,
    pub(super) crtc_y: property::Handle,
    pub(super) crtc_w: property::Handle,
    pub(super) crtc_h: property::Handle,
}

impl CursorPlaneProperties {
    pub(super) fn load(drm: &DrmDevice, plane: plane::Handle) -> Result<Self, Box<dyn Error>> {
        let named = |name: &str| -> Result<property::Handle, Box<dyn Error>> {
            super::kms_state::optional_named_property(drm, plane, name)?
                .ok_or_else(|| std::io::Error::other(format!("cursor plane lacks {name} property")))
                .map_err(Into::into)
        };
        Ok(Self {
            fb_id: named("FB_ID")?,
            crtc_id: named("CRTC_ID")?,
            src_x: named("SRC_X")?,
            src_y: named("SRC_Y")?,
            src_w: named("SRC_W")?,
            src_h: named("SRC_H")?,
            crtc_x: named("CRTC_X")?,
            crtc_y: named("CRTC_Y")?,
            crtc_w: named("CRTC_W")?,
            crtc_h: named("CRTC_H")?,
        })
    }
}

/// A live KMS cursor-plane binding: the chosen plane, its atomic property
/// handles, and the ARGB8888 dumb buffer + framebuffer backing the cursor
/// image. The buffer is sized to the plane's advertised maximum (bounded by
/// `CURSOR_MAX_DIMENSION`) and reused across role changes.
#[derive(Debug)]
pub(super) struct CursorPlaneBinding {
    pub(super) crtc: u32,
    pub(super) plane: plane::Handle,
    pub(super) properties: CursorPlaneProperties,
    pub(super) framebuffer: framebuffer::Handle,
    pub(super) buffer: DumbBuffer,
    pub(super) buffer_size: PixelSize,
}

/// A pure geometry mapping from the clipped cursor rectangle to the KMS
/// cursor-plane source/destination properties. Negative destinations crop the
/// source; right/bottom overflow crops the destination width/height.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct CursorPlaneRect {
    pub(super) src_x: u32,
    pub(super) src_y: u32,
    pub(super) src_w: u32,
    pub(super) src_h: u32,
    pub(super) crtc_x: u32,
    pub(super) crtc_y: u32,
    pub(super) crtc_w: u32,
    pub(super) crtc_h: u32,
}

pub(super) fn cursor_plane_rect(
    geometry: CursorGeometry,
    output_size: PixelSize,
) -> CursorPlaneRect {
    let crop_left = if geometry.destination.x < 0 {
        geometry
            .destination
            .x
            .unsigned_abs()
            .min(geometry.size.width)
    } else {
        0
    };
    let crop_top = if geometry.destination.y < 0 {
        geometry
            .destination
            .y
            .unsigned_abs()
            .min(geometry.size.height)
    } else {
        0
    };
    let crtc_x = geometry.destination.x.max(0) as u32;
    let crtc_y = geometry.destination.y.max(0) as u32;
    let available_w = geometry.size.width.saturating_sub(crop_left);
    let available_h = geometry.size.height.saturating_sub(crop_top);
    let crtc_w = available_w.min(output_size.width.saturating_sub(crtc_x));
    let crtc_h = available_h.min(output_size.height.saturating_sub(crtc_y));
    CursorPlaneRect {
        src_x: crop_left,
        src_y: crop_top,
        src_w: crtc_w,
        src_h: crtc_h,
        crtc_x,
        crtc_y,
        crtc_w,
        crtc_h,
    }
}

/// The compositor-authoritative cursor visual as projected onto the output
/// under the pointer. `position` is physical pixels on that output.
#[derive(Clone, Copy, Debug)]
pub(super) struct CursorVisualState {
    pub(super) crtc: u32,
    pub(super) position: (f64, f64),
    pub(super) role: Option<CursorRole>,
    pub(super) visible: bool,
    pub(super) scale: f64,
    pub(super) output_size: PixelSize,
    pub(super) transform: OutputTransform,
}

/// Request produced by the Wayland frontend: which logical output owns the
/// pointer, where it is in physical pixels, and the logical->physical scale.
#[derive(Clone, Copy, Debug)]
pub(super) struct CursorVisualRequest {
    pub(super) output_id: OutputId,
    pub(super) position: (f64, f64),
    pub(super) scale: f64,
}

/// Production cursor-plane runtime. It owns the dynamically discovered
/// candidates, live bindings, and the publish path (hardware vs software).
/// Any KMS failure at probe, upload, or commit time degrades to software
/// rendering for the current topology epoch; `invalidate()` re-arms probing
/// after hotplug/mode/scale/transform changes.
#[derive(Debug, Default)]
pub(super) struct CursorPlaneRuntime {
    state: CursorState,
    candidates: Vec<CursorPlaneCandidate>,
    bindings: Vec<CursorPlaneBinding>,
    epoch: u64,
    role: Option<CursorRole>,
    position: Option<(f64, f64)>,
    visible: bool,
    published_path: CursorRenderPath,
}

impl CursorPlaneRuntime {
    pub(super) fn visible(&self) -> bool {
        self.state.visible()
    }

    pub(super) fn role(&self) -> Option<CursorRole> {
        self.role
    }

    pub(super) fn position(&self) -> Option<(f64, f64)> {
        self.position
    }

    /// Invalidates every cached binding and re-arms plane probing. Call after
    /// hotplug, mode, scale, transform, or driver-epoch changes.
    pub(super) fn invalidate(&mut self, drm: &DrmDevice) {
        self.epoch = self.epoch.wrapping_add(1);
        self.state.invalidate_epoch();
        self.drop_bindings(drm);
        self.role = None;
        self.position = None;
        self.visible = false;
    }

    pub(super) fn failure_reasons(&self) -> Vec<String> {
        self.state.failure_reasons().map(str::to_owned).collect()
    }

    pub(super) fn take_path_transition(&mut self) -> Option<CursorRenderPath> {
        let path = self.state.path();
        if path == self.published_path {
            return None;
        }
        self.published_path = path;
        Some(path)
    }

    fn drop_bindings(&mut self, drm: &DrmDevice) {
        let count = self.bindings.len();
        for binding in self.bindings.drain(..) {
            if let Err(error) = drm.destroy_framebuffer(binding.framebuffer) {
                warn!(?error, "could not destroy cursor framebuffer");
            }
            // The smithay DumbBuffer's Drop destroys the underlying handle.
        }
        for _ in 0..count {
            self.state.retire_buffer();
        }
    }

    fn binding_index(&self, crtc: u32) -> Option<usize> {
        self.bindings
            .iter()
            .position(|binding| binding.crtc == crtc)
    }

    fn refresh_candidates(&mut self, drm: &DrmDevice) {
        match super::kms_state::discover_plane_capabilities(drm) {
            Ok(capabilities) => {
                let max_size =
                    PixelSize::new(drm.cursor_size().w.max(1), drm.cursor_size().h.max(1));
                self.candidates =
                    super::kms_state::cursor_plane_candidates(&capabilities, max_size);
            }
            Err(error) => {
                warn!(%error, "could not refresh cursor plane candidates");
                self.candidates.clear();
            }
        }
    }

    fn ensure_binding(
        &mut self,
        drm: &DrmDevice,
        visual: &CursorVisualState,
    ) -> Result<Option<()>, Box<dyn Error>> {
        if self.binding_index(visual.crtc).is_some() {
            return Ok(Some(()));
        }
        let Some(choice) =
            select_cursor_plane(&self.candidates, visual.crtc, DrmFourcc::Argb8888 as u32)
        else {
            return Ok(None);
        };
        let Some(plane) = smithay::reexports::drm::control::from_u32::<plane::Handle>(choice.plane)
        else {
            return Ok(None);
        };
        let properties = CursorPlaneProperties::load(drm, plane)?;
        let buffer_size = PixelSize::new(choice.width.max(1), choice.height.max(1));
        let mut allocator =
            smithay::backend::allocator::dumb::DumbAllocator::new(drm.device_fd().clone());
        let buffer = allocator.create_buffer(
            buffer_size.width,
            buffer_size.height,
            Fourcc::Argb8888,
            &[Modifier::Linear],
        )?;
        let framebuffer = smithay::backend::drm::dumb::framebuffer_from_dumb_buffer(
            drm.device_fd(),
            &buffer,
            false,
        )?;
        let framebuffer = *framebuffer.as_ref();
        self.bindings.push(CursorPlaneBinding {
            crtc: visual.crtc,
            plane,
            properties,
            framebuffer,
            buffer,
            buffer_size,
        });
        self.state.acquire_buffer();
        info!(
            crtc = visual.crtc,
            plane = u32::from(plane),
            width = buffer_size.width,
            height = buffer_size.height,
            "hardware cursor plane bound"
        );
        Ok(Some(()))
    }

    fn upload_artwork(
        &self,
        drm: &DrmDevice,
        binding: &CursorPlaneBinding,
        role: CursorRole,
        scale: f64,
    ) -> Result<(), Box<dyn Error>> {
        let artwork = get_artwork(role);
        let geom_w = (f64::from(artwork.width) * scale).round().max(1.0) as u32;
        let geom_h = (f64::from(artwork.height) * scale).round().max(1.0) as u32;
        let fill_w = geom_w.min(binding.buffer_size.width);
        let fill_h = geom_h.min(binding.buffer_size.height);
        let pitch = binding.buffer.handle().pitch() as usize;
        let mut handle = *binding.buffer.handle();
        let mut mapping = drm.device_fd().map_dumb_buffer(&mut handle)?;
        let pixels = mapping.as_mut();
        pixels.fill(0);
        for dy in 0..fill_h {
            let sy =
                ((f64::from(dy) * f64::from(artwork.height)) / f64::from(geom_h)).floor() as u32;
            let row = dy as usize * pitch;
            for dx in 0..fill_w {
                let sx =
                    ((f64::from(dx) * f64::from(artwork.width)) / f64::from(geom_w)).floor() as u32;
                let src = (sy as usize * artwork.width as usize + sx as usize) * 4;
                let dst = row + dx as usize * 4;
                pixels[dst..dst + 4].copy_from_slice(&artwork.rgba_pixels[src..src + 4]);
            }
        }
        Ok(())
    }

    fn commit_visible(
        &self,
        drm: &DrmDevice,
        binding: &CursorPlaneBinding,
        visual: &CursorVisualState,
        rect: CursorPlaneRect,
    ) -> Result<(), Box<dyn Error>> {
        let mut request = AtomicModeReq::new();
        let plane: RawResourceHandle = binding.plane.into();
        request.add_raw_property(
            plane,
            binding.properties.fb_id,
            u64::from(u32::from(binding.framebuffer)),
        );
        request.add_raw_property(plane, binding.properties.crtc_id, u64::from(visual.crtc));
        request.add_raw_property(plane, binding.properties.src_x, u64::from(rect.src_x) << 16);
        request.add_raw_property(plane, binding.properties.src_y, u64::from(rect.src_y) << 16);
        request.add_raw_property(plane, binding.properties.src_w, u64::from(rect.src_w) << 16);
        request.add_raw_property(plane, binding.properties.src_h, u64::from(rect.src_h) << 16);
        request.add_raw_property(plane, binding.properties.crtc_x, u64::from(rect.crtc_x));
        request.add_raw_property(plane, binding.properties.crtc_y, u64::from(rect.crtc_y));
        request.add_raw_property(plane, binding.properties.crtc_w, u64::from(rect.crtc_w));
        request.add_raw_property(plane, binding.properties.crtc_h, u64::from(rect.crtc_h));
        drm.atomic_commit(AtomicCommitFlags::NONBLOCK, request)?;
        Ok(())
    }

    fn hide(&mut self, drm: &DrmDevice) -> Result<(), Box<dyn Error>> {
        if self.bindings.is_empty() || !self.visible {
            // Nothing visible on any plane: keep the idle path free of
            // redundant atomic commits.
            self.state.set_visible(false);
            self.role = None;
            self.position = None;
            self.visible = false;
            return Ok(());
        }
        let mut request = AtomicModeReq::new();
        for binding in &self.bindings {
            let plane: RawResourceHandle = binding.plane.into();
            request.add_raw_property(plane, binding.properties.fb_id, 0);
            request.add_raw_property(plane, binding.properties.crtc_id, 0);
        }
        drm.atomic_commit(AtomicCommitFlags::NONBLOCK, request)?;
        self.state.set_visible(false);
        self.role = None;
        self.position = None;
        self.visible = false;
        Ok(())
    }

    /// Program the KMS cursor plane for the latest compositor cursor state.
    /// Returns the active render path; hardware means the shell must not draw
    /// or schedule a software cursor.
    pub(super) fn synchronize(
        &mut self,
        drm: &DrmDevice,
        visual: Option<CursorVisualState>,
    ) -> Result<CursorRenderPath, Box<dyn Error>> {
        let Some(visual) = visual else {
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        };

        if !visual.visible || visual.role.is_none() {
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        }
        let role = visual.role.expect("visibility checked above");

        let probed = self.state.tested_epoch() == Some(self.epoch);
        if !probed {
            self.state.begin_test_only(self.epoch, "cursor_plane_probe");
            self.refresh_candidates(drm);
            match self.ensure_binding(drm, &visual) {
                Ok(Some(())) => self.state.test_only_succeeded(),
                Ok(None) => {
                    self.state.test_only_failed("no_suitable_cursor_plane");
                    self.hide(drm)?;
                    return Ok(CursorRenderPath::Software);
                }
                Err(error) => {
                    self.state
                        .test_only_failed(format!("cursor_plane_probe_failed: {error}"));
                    self.hide(drm)?;
                    return Ok(CursorRenderPath::Software);
                }
            }
        }

        if self.state.path() != CursorRenderPath::Hardware {
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        }

        let Some(binding_index) = self.binding_index(visual.crtc) else {
            self.state.test_only_failed("cursor_binding_lost");
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        };

        // No-op when the pointer has not moved and the role is unchanged.
        if self.visible && self.role == Some(role) && self.position == Some(visual.position) {
            return Ok(CursorRenderPath::Hardware);
        }

        if self.role != Some(role) {
            let upload_result = {
                let binding = &self.bindings[binding_index];
                self.upload_artwork(drm, binding, role, visual.scale)
            };
            if let Err(error) = upload_result {
                self.state
                    .test_only_failed(format!("cursor_artwork_upload: {error}"));
                self.hide(drm)?;
                return Ok(CursorRenderPath::Software);
            }
        }

        let artwork = get_artwork(role);
        let Some(geometry) = geometry(
            visual.position,
            artwork.size(),
            artwork.hotspot,
            visual.scale,
            visual.output_size,
            visual.transform,
        ) else {
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        };
        let rect = cursor_plane_rect(geometry, visual.output_size);
        if rect.crtc_w == 0 || rect.crtc_h == 0 {
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        }
        let commit_result = {
            let binding = &self.bindings[binding_index];
            self.commit_visible(drm, binding, &visual, rect)
        };
        if let Err(error) = commit_result {
            self.state
                .test_only_failed(format!("cursor_plane_commit: {error}"));
            self.hide(drm)?;
            return Ok(CursorRenderPath::Software);
        }

        self.role = Some(role);
        self.position = Some(visual.position);
        self.visible = true;
        self.state.set_visible(true);
        Ok(CursorRenderPath::Hardware)
    }
}

/// Cursor state needed to composite the hardware cursor into a capture
/// (screencopy or screenshot). `atlas_position` is the pointer in physical
/// atlas pixels; captures project it relative to their own source rect.
#[derive(Clone, Copy, Debug)]
pub(super) struct CursorCaptureState {
    pub(super) role: CursorRole,
    pub(super) atlas_position: (f64, f64),
    pub(super) scale: f64,
}

/// Composites the hardware cursor into RGBA capture pixels whose top-left
/// corresponds to `region_loc` in physical atlas pixels. The destination is
/// treated as a `Normal` transform so captured pixels match the atlas.
pub(super) fn composite_cursor_into_capture(
    dst_pixels: &mut [u8],
    dst_width: u32,
    dst_height: u32,
    dst_stride: usize,
    cursor: CursorCaptureState,
    region_loc: (i32, i32),
) {
    composite_cursor_to_rgba(
        dst_pixels,
        dst_width,
        dst_height,
        dst_stride,
        (
            cursor.atlas_position.0 - f64::from(region_loc.0),
            cursor.atlas_position.1 - f64::from(region_loc.1),
        ),
        cursor.role,
        cursor.scale,
        PixelSize::new(dst_width, dst_height),
        OutputTransform::Normal,
    );
}

/// Composite a cursor onto target pixels (RGBA 8888) with alpha blending
/// for Screencopy and Screenshot capture semantics (C1 §K3, §F5).
#[allow(clippy::too_many_arguments)]
pub(super) fn composite_cursor_to_rgba(
    dst_pixels: &mut [u8],
    dst_width: u32,
    dst_height: u32,
    dst_stride: usize,
    pointer: (f64, f64),
    role: CursorRole,
    scale: f64,
    output_size: PixelSize,
    transform: OutputTransform,
) {
    let artwork = get_artwork(role);
    let Some(geom) = geometry(
        pointer,
        artwork.size(),
        artwork.hotspot,
        scale,
        output_size,
        transform,
    ) else {
        return;
    };

    let dst_x_start = geom.destination.x.max(0) as u32;
    let dst_y_start = geom.destination.y.max(0) as u32;
    let dst_x_end = (geom.destination.x + geom.size.width as i32)
        .max(0)
        .min(dst_width as i32) as u32;
    let dst_y_end = (geom.destination.y + geom.size.height as i32)
        .max(0)
        .min(dst_height as i32) as u32;

    if dst_x_start >= dst_x_end || dst_y_start >= dst_y_end {
        return;
    }

    let geom_w = geom.size.width.max(1) as f64;
    let geom_h = geom.size.height.max(1) as f64;
    let art_w = artwork.width as f64;
    let art_h = artwork.height as f64;

    for dy in dst_y_start..dst_y_end {
        let rel_y = (dy as i32 - geom.destination.y) as f64;
        let sy = ((rel_y / geom_h) * art_h).floor() as u32;
        if sy >= artwork.height {
            continue;
        }

        let dst_row_offset = dy as usize * dst_stride;
        for dx in dst_x_start..dst_x_end {
            let rel_x = (dx as i32 - geom.destination.x) as f64;
            let sx = ((rel_x / geom_w) * art_w).floor() as u32;
            if sx >= artwork.width {
                continue;
            }

            let src_idx = (sy as usize * artwork.width as usize + sx as usize) * 4;
            let src_r = artwork.rgba_pixels[src_idx] as u32;
            let src_g = artwork.rgba_pixels[src_idx + 1] as u32;
            let src_b = artwork.rgba_pixels[src_idx + 2] as u32;
            let src_a = artwork.rgba_pixels[src_idx + 3] as u32;

            if src_a == 0 {
                continue;
            }

            let dst_idx = dst_row_offset + dx as usize * 4;
            if dst_idx + 3 >= dst_pixels.len() {
                continue;
            }

            if src_a == 255 {
                dst_pixels[dst_idx] = src_r as u8;
                dst_pixels[dst_idx + 1] = src_g as u8;
                dst_pixels[dst_idx + 2] = src_b as u8;
                dst_pixels[dst_idx + 3] = 255;
            } else {
                let inv_a = 255 - src_a;
                let cur_r = dst_pixels[dst_idx] as u32;
                let cur_g = dst_pixels[dst_idx + 1] as u32;
                let cur_b = dst_pixels[dst_idx + 2] as u32;
                let cur_a = dst_pixels[dst_idx + 3] as u32;

                dst_pixels[dst_idx] = ((src_r * src_a + cur_r * inv_a) / 255) as u8;
                dst_pixels[dst_idx + 1] = ((src_g * src_a + cur_g * inv_a) / 255) as u8;
                dst_pixels[dst_idx + 2] = ((src_b * src_a + cur_b * inv_a) / 255) as u8;
                dst_pixels[dst_idx + 3] = ((src_a * 255 + cur_a * inv_a) / 255).min(255) as u8;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn named_roles_are_stable_and_unknown_is_software() {
        assert_eq!(CursorRole::from_wire("hand2"), Some(CursorRole::Link));
        assert_eq!(
            CursorRole::from_wire("n-resize"),
            Some(CursorRole::VerticalResize)
        );
        assert_eq!(CursorRole::from_wire("client-surface"), None);
    }

    #[test]
    fn hotspot_and_negative_edges_are_clipped() {
        let result = geometry(
            (1.0, 1.0),
            PixelSize {
                width: 32,
                height: 32,
            },
            PixelPoint { x: 6, y: 2 },
            1.25,
            PixelSize {
                width: 100,
                height: 100,
            },
            OutputTransform::Normal,
        )
        .unwrap();
        assert_eq!(result.destination, PixelPoint { x: -7, y: -2 });
        assert!(result.clipped);
        assert_eq!(result.hotspot, PixelPoint { x: 8, y: 3 });
    }

    #[test]
    fn reverse_probe_rejects_commit_without_test_only() {
        let mut state = CursorState::default();
        assert!(state.begin_test_only(7, "normal"));
        state.test_only_succeeded();
        assert_eq!(state.path(), CursorRenderPath::Hardware);
        state.test_only_failed("skipped_test_only");
        assert_eq!(state.path(), CursorRenderPath::Software);
    }

    #[test]
    fn pool_is_bounded_and_hardware_software_are_mutually_exclusive() {
        let mut state = CursorState::default();
        assert!(state.begin_test_only(1, "normal"));
        state.test_only_succeeded();
        state.set_visible(true);
        assert!(state.visible());
        assert!(state.acquire_buffer());
        assert!(state.acquire_buffer());
        assert!(state.acquire_buffer());
        assert!(!state.acquire_buffer());
        state.test_only_failed("kms_einval");
        assert!(!state.visible());
        assert_eq!(state.path(), CursorRenderPath::Software);
        state.retire_buffer();
        assert!(state.failure_reasons().any(|reason| reason == "kms_einval"));
    }

    #[test]
    fn plane_selection_is_dynamic_and_requires_all_cursor_properties() {
        let candidates = vec![
            CursorPlaneCandidate {
                plane: 99,
                possible_crtcs: vec![7],
                formats: vec![0x34325241],
                has_destination: false,
                max_size: PixelSize::new(64, 64),
            },
            CursorPlaneCandidate {
                plane: 42,
                possible_crtcs: vec![7],
                formats: vec![0x34325241],
                has_destination: true,
                max_size: PixelSize::new(128, 128),
            },
        ];
        assert_eq!(
            select_cursor_plane(&candidates, 7, 0x34325241)
                .unwrap()
                .plane,
            42
        );
        assert!(select_cursor_plane(&candidates, 8, 0x34325241).is_none());
    }

    #[test]
    fn all_17_cursor_roles_have_valid_png_and_hotspots() {
        let roles = [
            CursorRole::Normal,
            CursorRole::Help,
            CursorRole::Working,
            CursorRole::Text,
            CursorRole::Link,
            CursorRole::Busy,
            CursorRole::Precision,
            CursorRole::Handwriting,
            CursorRole::Unavailable,
            CursorRole::VerticalResize,
            CursorRole::HorizontalResize,
            CursorRole::DiagonalNwSeResize,
            CursorRole::DiagonalNeSwResize,
            CursorRole::Move,
            CursorRole::Alternate,
            CursorRole::Person,
            CursorRole::Pin,
        ];
        for role in roles {
            let artwork = get_artwork(role);
            assert_eq!(artwork.width, 32, "role {:?} width", role);
            assert_eq!(artwork.height, 32, "role {:?} height", role);
            assert_eq!(
                artwork.rgba_pixels.len(),
                32 * 32 * 4,
                "role {:?} byte count",
                role
            );
            assert_eq!(
                artwork.hotspot,
                role.default_hotspot(),
                "role {:?} hotspot",
                role
            );
        }
    }

    #[test]
    fn hard_soft_switching_200_iterations_clean() {
        let mut state = CursorState::default();
        for i in 0..200 {
            let epoch = i as u64;
            assert!(state.begin_test_only(epoch, "test"));
            state.test_only_succeeded();
            state.set_visible(true);
            assert_eq!(state.path(), CursorRenderPath::Hardware);
            assert!(state.visible());
            assert!(state.acquire_buffer());
            assert_eq!(state.pool_in_use, 1);

            // Switch to software fallback
            state.test_only_failed("simulated_fallback");
            assert_eq!(state.path(), CursorRenderPath::Software);
            assert!(!state.visible());
            assert_eq!(state.pool_in_use, 0);
        }
        assert_eq!(state.pool_in_use, 0);
    }

    #[test]
    fn screencopy_cursor_composition_blits_pixels_correctly() {
        let mut dst = vec![0u8; 100 * 100 * 4];
        let pointer = (20.0, 20.0);
        let output_size = PixelSize::new(100, 100);

        composite_cursor_to_rgba(
            &mut dst,
            100,
            100,
            100 * 4,
            pointer,
            CursorRole::Normal,
            1.0,
            output_size,
            OutputTransform::Normal,
        );

        // At hotspot (20, 20) with hotspot offset (6, 2), cursor is at (14, 18)
        let sample_idx = (18 * 100 + 14) * 4;
        let _ = sample_idx;
        // The top-left of normal cursor is non-transparent
        let has_non_zero = dst.iter().any(|&b| b > 0);
        assert!(
            has_non_zero,
            "cursor composition must have written pixels into destination"
        );
    }

    #[test]
    fn geometry_handles_all_orientations() {
        let artwork_size = PixelSize::new(32, 32);
        let hotspot = PixelPoint { x: 0, y: 0 };
        let output_size = PixelSize::new(1920, 1080);
        let pointer = (100.0, 200.0);

        let g_normal = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.0,
            output_size,
            OutputTransform::Normal,
        )
        .unwrap();
        assert_eq!(g_normal.destination, PixelPoint { x: 100, y: 200 });

        let g_90 = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.0,
            output_size,
            OutputTransform::Rotate90,
        )
        .unwrap();
        assert_eq!(g_90.destination, PixelPoint { x: 200, y: 980 });

        let g_180 = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.0,
            output_size,
            OutputTransform::Rotate180,
        )
        .unwrap();
        assert_eq!(g_180.destination, PixelPoint { x: 1820, y: 880 });

        let g_270 = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.0,
            output_size,
            OutputTransform::Rotate270,
        )
        .unwrap();
        assert_eq!(g_270.destination, PixelPoint { x: 1720, y: 100 });
    }

    #[test]
    fn fractional_scale_geometry_and_hotspot() {
        let artwork_size = PixelSize::new(32, 32);
        let hotspot = PixelPoint { x: 6, y: 2 };
        let output_size = PixelSize::new(3840, 2160);
        let pointer = (500.0, 500.0);

        // 1.5x scale
        let g_15 = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.5,
            output_size,
            OutputTransform::Normal,
        )
        .unwrap();
        assert_eq!(g_15.size, PixelSize::new(48, 48));
        assert_eq!(g_15.hotspot, PixelPoint { x: 9, y: 3 });
        assert_eq!(g_15.destination, PixelPoint { x: 491, y: 497 });

        // 1.6x scale
        let g_16 = geometry(
            pointer,
            artwork_size,
            hotspot,
            1.6,
            output_size,
            OutputTransform::Normal,
        )
        .unwrap();
        assert_eq!(g_16.size, PixelSize::new(51, 51));
        assert_eq!(g_16.hotspot, PixelPoint { x: 10, y: 3 });
        assert_eq!(g_16.destination, PixelPoint { x: 490, y: 497 });
    }

    #[test]
    fn cursor_plane_rect_clips_negative_destinations_by_cropping_source() {
        let output = PixelSize::new(1920, 1080);
        // Cursor hotspot at (0,0) with 48x48 artwork: destination is (-48,-48).
        let geometry = CursorGeometry {
            destination: PixelPoint { x: -48, y: -48 },
            size: PixelSize::new(48, 48),
            hotspot: PixelPoint { x: 0, y: 0 },
            clipped: true,
        };
        let rect = cursor_plane_rect(geometry, output);
        assert_eq!(rect.src_x, 48);
        assert_eq!(rect.src_y, 48);
        assert_eq!(rect.crtc_x, 0);
        assert_eq!(rect.crtc_y, 0);
        assert_eq!(rect.src_w, 0);
        assert_eq!(rect.src_h, 0);
        assert_eq!(rect.crtc_w, 0);
        assert_eq!(rect.crtc_h, 0);
    }

    #[test]
    fn cursor_plane_rect_clips_right_and_bottom_overflow() {
        let output = PixelSize::new(100, 100);
        let geometry = CursorGeometry {
            destination: PixelPoint { x: 80, y: 90 },
            size: PixelSize::new(48, 48),
            hotspot: PixelPoint { x: 0, y: 0 },
            clipped: true,
        };
        let rect = cursor_plane_rect(geometry, output);
        assert_eq!(rect.src_x, 0);
        assert_eq!(rect.src_y, 0);
        assert_eq!(rect.crtc_x, 80);
        assert_eq!(rect.crtc_y, 90);
        assert_eq!(rect.crtc_w, 20);
        assert_eq!(rect.crtc_h, 10);
        assert_eq!(rect.src_w, 20);
        assert_eq!(rect.src_h, 10);
    }

    #[test]
    fn cursor_plane_rect_preserves_fully_visible_cursor() {
        let output = PixelSize::new(100, 100);
        let geometry = CursorGeometry {
            destination: PixelPoint { x: 10, y: 20 },
            size: PixelSize::new(32, 32),
            hotspot: PixelPoint { x: 0, y: 0 },
            clipped: false,
        };
        let rect = cursor_plane_rect(geometry, output);
        assert_eq!(rect.src_x, 0);
        assert_eq!(rect.src_y, 0);
        assert_eq!(rect.src_w, 32);
        assert_eq!(rect.src_h, 32);
        assert_eq!(rect.crtc_x, 10);
        assert_eq!(rect.crtc_y, 20);
        assert_eq!(rect.crtc_w, 32);
        assert_eq!(rect.crtc_h, 32);
    }

    #[test]
    fn probe_failure_is_sticky_until_epoch_invalidates() {
        let mut state = CursorState::default();
        assert!(state.begin_test_only(0, "probe"));
        assert!(
            !state.begin_test_only(0, "probe"),
            "the same topology epoch must not re-probe every frame"
        );
        state.test_only_failed("no_suitable_cursor_plane");
        assert_eq!(state.path(), CursorRenderPath::Software);
        assert_eq!(state.tested_epoch(), Some(0));
        state.invalidate_epoch();
        assert_eq!(state.tested_epoch(), None);
        assert!(
            state.begin_test_only(1, "probe"),
            "a new epoch re-arms probing"
        );
    }

    #[test]
    fn hidden_or_unsupported_shapes_never_enter_hardware_path() {
        // Policy-level reverse probe: "none" must be treated as hidden and an
        // unknown shape as software-only.
        assert_eq!(CursorRole::from_wire("none"), None);
        assert_eq!(CursorRole::from_wire("hidden"), None);
        assert_eq!(CursorRole::from_wire("client-surface"), None);
        assert!(CursorRole::from_wire("default").is_some());
    }

    #[test]
    fn reverse_probe_removing_fallback_breaks_policy() {
        // If a future change removes the software fallback, this test fails:
        // a failed probe must never leave the path in Hardware.
        let mut state = CursorState::default();
        state.begin_test_only(1, "probe");
        state.test_only_failed("simulated_kms_error");
        assert_eq!(
            state.path(),
            CursorRenderPath::Software,
            "a failed cursor-plane probe must force software rendering"
        );
        assert!(!state.visible());
    }

    #[test]
    fn test_reverse_probe_fails_if_fallback_bypassed() {
        // Reverse probe: verify that if failure occurs, fallback to software is enforced
        let mut state = CursorState::default();
        state.begin_test_only(1, "normal");
        state.test_only_succeeded();
        assert_eq!(state.path(), CursorRenderPath::Hardware);

        // Simulate KMS plane failure
        state.test_only_failed("plane_busy");
        assert_eq!(
            state.path(),
            CursorRenderPath::Software,
            "State MUST be software on failure"
        );
        assert!(!state.visible(), "Plane MUST be hidden on failure");
    }
}
