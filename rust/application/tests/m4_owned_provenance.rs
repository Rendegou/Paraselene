#![cfg(feature = "test-support")]
//! Attacks use fresh fixtures only; no production root or unknown files are cleaned.
use paraselene_application::Session;
use std::os::windows::fs::{symlink_dir, symlink_file};

#[test]
fn owned_files_reject_hardlinks_without_modifying_target() {
    for name in ["snapshot.dpapi", "snapshot.pending", "session.lock"] {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("store");
        std::fs::create_dir(&root).unwrap();
        let target = dir.path().join("external");
        std::fs::write(&target, b"preserve me").unwrap();
        std::fs::hard_link(&target, root.join(name)).unwrap();
        assert!(Session::open_owned_at_for_test(&root).is_err(), "{name}");
        assert_eq!(std::fs::read(&target).unwrap(), b"preserve me");
        assert_eq!(std::fs::read(root.join(name)).unwrap(), b"preserve me");
    }
}

#[test]
fn owned_files_reject_reparse_points_without_modifying_target() {
    for name in ["snapshot.dpapi", "snapshot.pending", "session.lock"] {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("store");
        std::fs::create_dir(&root).unwrap();
        let target = dir.path().join("external");
        std::fs::write(&target, b"preserve me").unwrap();
        if let Err(e) = symlink_file(&target, root.join(name)) {
            panic!("NOT_RUN: file symlink creation unavailable ({name}): {e}");
        }
        assert!(Session::open_owned_at_for_test(&root).is_err(), "{name}");
        assert_eq!(std::fs::read(&target).unwrap(), b"preserve me");
        std::fs::remove_file(root.join(name)).unwrap();
    }
}

#[test]
fn owned_directory_chain_rejects_reparse_points() {
    let dir = tempfile::tempdir().unwrap();
    let actual = dir.path().join("actual");
    std::fs::create_dir(&actual).unwrap();
    let link = dir.path().join("link");
    if let Err(e) = symlink_dir(&actual, &link) {
        panic!("NOT_RUN: directory symlink creation unavailable: {e}");
    }
    assert!(Session::open_owned_at_for_test(&link).is_err());
    std::fs::create_dir(actual.join("store")).unwrap();
    assert!(Session::open_owned_at_for_test(&link.join("store")).is_err());
    assert_eq!(std::fs::read_dir(actual.join("store")).unwrap().count(), 0);
    std::fs::remove_dir(link).unwrap();
}
