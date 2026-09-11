#[cfg(feature = "flutter")]
use super::ensure_resident_jit_engine_matches;
use super::{
    DrmModeCloseFb, MAX_SCANOUT_POOL_BYTES, PixelSize, ScanoutIdentity, ScanoutIdentityError,
    parse_scanout_pool_budget, validate_scanout_identities, validate_scanout_pool_allocation,
};
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;

#[cfg(feature = "flutter")]
#[test]
fn a_changed_resident_jit_engine_requires_a_session_restart() {
    let first = [0x11; 32];
    let same = [0x11; 32];
    let changed = [0x22; 32];

    assert!(ensure_resident_jit_engine_matches(None, &first).is_ok());
    assert!(ensure_resident_jit_engine_matches(Some(&first), &same).is_ok());
    let error = ensure_resident_jit_engine_matches(Some(&first), &changed)
        .expect_err("changed native JIT engine must be rejected");
    assert!(error.to_string().contains("Restart the Denial session"));
}

#[test]
fn scanout_identity_validation_rejects_every_alias_class() {
    let identity = |output, connector, crtc, plane| ScanoutIdentity {
        output,
        connector,
        crtc,
        plane,
    };
    let baseline = identity(1, 1, 10, 20);
    assert!(validate_scanout_identities([baseline]).is_ok());
    assert_eq!(
        validate_scanout_identities([baseline, identity(1, 2, 11, 21)]),
        Err(ScanoutIdentityError::DuplicateOutput(1))
    );
    assert_eq!(
        validate_scanout_identities([baseline, identity(2, 1, 11, 21)]),
        Err(ScanoutIdentityError::DuplicateConnector(1))
    );
    assert_eq!(
        validate_scanout_identities([baseline, identity(2, 2, 10, 21)]),
        Err(ScanoutIdentityError::DuplicateCrtc(10))
    );
    assert_eq!(
        validate_scanout_identities([baseline, identity(2, 2, 11, 20)]),
        Err(ScanoutIdentityError::DuplicatePlane(20))
    );
    assert_eq!(
        validate_scanout_identities([identity(9, 1, 10, 20)]),
        Err(ScanoutIdentityError::OutputConnectorMismatch {
            output: 9,
            connector: 1,
        })
    );
    for zeroed in [
        identity(0, 1, 10, 20),
        identity(1, 0, 10, 20),
        identity(1, 1, 0, 20),
        identity(1, 1, 10, 0),
    ] {
        assert!(matches!(
            validate_scanout_identities([zeroed]),
            Err(ScanoutIdentityError::Zero(_))
        ));
    }
}

#[test]
fn drm_mode_close_fb_layout_and_fields() {
    assert_eq!(std::mem::size_of::<DrmModeCloseFb>(), 8);
    assert_eq!(std::mem::align_of::<DrmModeCloseFb>(), 4);
    let closefb = DrmModeCloseFb {
        fb_id: 42,
        pad: 0,
    };
    assert_eq!(closefb.fb_id, 42);
    assert_eq!(closefb.pad, 0);
}

#[test]
fn scanout_pool_budget_counts_offscreen_linear_targets() {
    // An 8192x8192 XR24 buffer is 268435456 bytes; a pool of 3 needs
    // 805306368 bytes of scanout storage, which fits the default budget
    // only until the per-buffer linear render target is counted too.
    let size = PixelSize::new(8192, 8192);
    assert!(validate_scanout_pool_allocation(size, 3, false, MAX_SCANOUT_POOL_BYTES).is_ok());
    let error = validate_scanout_pool_allocation(size, 3, true, MAX_SCANOUT_POOL_BYTES)
        .expect_err("offscreen linear render targets must count toward the pool budget");
    let message = error.to_string();
    assert!(message.contains("805306368"));
    assert!(message.contains("1610612736"));
    assert!(message.contains("1073741824"));
    assert!(message.contains("linear"));
}

#[test]
fn scanout_pool_budget_honours_an_explicit_limit() {
    let size = PixelSize::new(1920, 1080);
    // 1920x1080x4x3 = 24883200 bytes of scanout; a limit just below that
    // rejects even without linear targets.
    assert!(validate_scanout_pool_allocation(size, 3, false, 24_883_200).is_ok());
    assert!(validate_scanout_pool_allocation(size, 3, false, 24_883_199).is_err());
    // A limit between the scanout-only and doubled totals rejects only the
    // offscreen-blit configuration.
    assert!(validate_scanout_pool_allocation(size, 3, false, 40_000_000).is_ok());
    assert!(validate_scanout_pool_allocation(size, 3, true, 40_000_000).is_err());
}

#[test]
fn scanout_pool_budget_environment_parsing() {
    assert_eq!(
        parse_scanout_pool_budget(None),
        Some(MAX_SCANOUT_POOL_BYTES)
    );
    assert_eq!(parse_scanout_pool_budget(Some(OsStr::new(""))), None);
    assert_eq!(parse_scanout_pool_budget(Some(OsStr::new("  "))), None);
    assert_eq!(
        parse_scanout_pool_budget(Some(OsStr::new("  536870912 "))),
        Some(536870912)
    );
    assert_eq!(
        parse_scanout_pool_budget(Some(OsStr::from_bytes(b"\xff"))),
        None
    );
    assert_eq!(parse_scanout_pool_budget(Some(OsStr::new("junk"))), None);
    assert_eq!(parse_scanout_pool_budget(Some(OsStr::new("-1"))), None);
    assert_eq!(parse_scanout_pool_budget(Some(OsStr::new("0"))), None);
}
