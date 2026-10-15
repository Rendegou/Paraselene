use paraselene_application::Session;
use std::fs;
fn root() -> tempfile::TempDir {
    let root = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    fs::write(
        root.path().join("M1_SYNTHETIC_ONLY"),
        b"paraselene-m1-synthetic-v1\n",
    )
    .unwrap();
    root
}
fn open(root: &tempfile::TempDir) -> Result<Session, paraselene_application::AppError> {
    Session::open_synthetic(root.path().to_string_lossy().into())
}
#[test]
fn unknown_preexisting_database_and_hardlink_are_rejected_untouched() {
    let fixture = root();
    let outside = tempfile::tempdir().unwrap();
    let harmless = outside.path().join("harmless.bin");
    fs::write(&harmless, b"unregistered synthetic bytes").unwrap();
    fs::hard_link(&harmless, fixture.path().join("synthetic.sqlite3")).unwrap();
    assert!(open(&fixture).is_err());
    assert_eq!(
        fs::read(&harmless).unwrap(),
        b"unregistered synthetic bytes"
    );
    fs::remove_file(fixture.path().join("synthetic.sqlite3")).unwrap();
    fs::write(fixture.path().join("synthetic.sqlite3"), b"unregistered").unwrap();
    assert!(open(&fixture).is_err());
    assert_eq!(
        fs::read(fixture.path().join("synthetic.sqlite3")).unwrap(),
        b"unregistered"
    );
}
#[test]
fn registered_database_reopens_but_linked_alias_does_not() {
    let fixture = root();
    let session = open(&fixture).unwrap();
    let work = session.create_work("synthetic".into()).unwrap();
    session.close().unwrap();
    let reopened = open(&fixture).unwrap();
    assert_eq!(reopened.list_works().unwrap()[0].id, work.id);
    reopened.close().unwrap();
    drop(reopened);
    drop(session);
    let alias = root();
    fs::hard_link(
        fixture.path().join("synthetic.sqlite3"),
        alias.path().join("synthetic.sqlite3"),
    )
    .unwrap();
    assert!(open(&alias).is_err());
    assert!(open(&fixture).is_err());
    fs::remove_file(alias.path().join("synthetic.sqlite3")).unwrap();
    assert!(open(&fixture).is_ok());
}
#[test]
fn open_handles_pin_database_marker_and_root_against_replacement() {
    let fixture = root();
    let session = open(&fixture).unwrap();
    let db = fixture.path().join("synthetic.sqlite3");
    assert!(fs::rename(&db, fixture.path().join("replaced.sqlite3")).is_err());
    assert!(fs::remove_file(&db).is_err());
    assert!(fs::rename(
        fixture.path().join("M1_SYNTHETIC_ONLY"),
        fixture.path().join("marker-moved")
    )
    .is_err());
    assert!(fs::rename(fixture.path(), fixture.path().with_extension("moved")).is_err());
    session.close().unwrap();
    fs::rename(&db, fixture.path().join("former.sqlite3")).unwrap();
    fs::write(&db, b"replacement synthetic bytes").unwrap();
    assert!(open(&fixture).is_err());
    assert_eq!(fs::read(&db).unwrap(), b"replacement synthetic bytes");
}
