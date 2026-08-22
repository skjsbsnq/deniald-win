//! Hardware-cursor policy and geometry.
//!
//! KMS cursor programming is deliberately kept behind a small, testable
//! policy layer.  The policy never guesses a plane: callers must provide the
//! dynamically discovered capability snapshot for the target CRTC.  A failed
//! test-only arrangement transitions to software rendering and is not retried
//! until the device/output epoch changes.

#![allow(dead_code)]

use std::collections::BTreeSet;

use denial_core::topology::{OutputTransform, PixelSize};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct PixelPoint {
    pub(super) x: i32,
    pub(super) y: i32,
}

pub(super) const CURSOR_POOL_LIMIT: usize = 3;
pub(super) const CURSOR_MAX_DIMENSION: u32 = 256;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum CursorRole {
    Normal,
    Text,
    Link,
    Wait,
    Progress,
    Resize,
    Move,
    Unavailable,
}

impl CursorRole {
    pub(super) fn from_wire(shape: &str) -> Option<Self> {
        match shape.trim().to_ascii_lowercase().as_str() {
            "default" | "normal" | "left-ptr" => Some(Self::Normal),
            "text" | "xterm" => Some(Self::Text),
            "pointer" | "hand2" | "link" => Some(Self::Link),
            "wait" | "busy" => Some(Self::Wait),
            "progress" | "working" => Some(Self::Progress),
            "move" | "grab" | "grabbing" => Some(Self::Move),
            "not-allowed" | "unavailable" | "crossed-circle" => Some(Self::Unavailable),
            value if value.contains("resize") || value.ends_with("-side") => Some(Self::Resize),
            _ => None,
        }
    }
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

/// Scale artwork and clip the destination rectangle conservatively.  The
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
    let mut hot_x = (f64::from(hotspot.x) * scale).round() as i32;
    let mut hot_y = (f64::from(hotspot.y) * scale).round() as i32;
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
    let mut left = x - hot_x;
    let mut top = y - hot_y;
    let mut clipped = false;
    if left < 0 {
        hot_x += left;
        left = 0;
        clipped = true;
    }
    if top < 0 {
        hot_y += top;
        top = 0;
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
        hotspot: PixelPoint {
            x: hot_x.max(0),
            y: hot_y.max(0),
        },
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn named_roles_are_stable_and_unknown_is_software() {
        assert_eq!(CursorRole::from_wire("hand2"), Some(CursorRole::Link));
        assert_eq!(CursorRole::from_wire("n-resize"), Some(CursorRole::Resize));
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
        assert_eq!(result.destination, PixelPoint { x: 0, y: 0 });
        assert!(result.clipped);
        assert_eq!(result.hotspot, PixelPoint { x: 1, y: 1 });
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
}
