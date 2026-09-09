#[cfg(feature = "flutter")]
use super::ensure_resident_jit_engine_matches;
use super::{DrmModeCloseFb, ScanoutIdentity, ScanoutIdentityError, validate_scanout_identities};

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

