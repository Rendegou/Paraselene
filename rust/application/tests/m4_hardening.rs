//! Real SQLite faults and review drift tests; only generated synthetic data.
use paraselene_application::Session;
use rusqlite::{params, Connection};
fn setup() -> (tempfile::TempDir, Session, String, String) {
    let dir = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    std::fs::write(
        dir.path().join("M1_SYNTHETIC_ONLY"),
        b"paraselene-m1-synthetic-v1\n",
    )
    .unwrap();
    let s = Session::open_synthetic(dir.path().to_string_lossy().into()).unwrap();
    let w = s.create_work("Synthetic".into()).unwrap().id;
    let d = s.create_chapter(w.clone(), "Chapter".into()).unwrap().id;
    (dir, s, w, d)
}
fn connection(dir: &tempfile::TempDir) -> Connection {
    Connection::open(dir.path().join("synthetic.sqlite3")).unwrap()
}
#[test]
fn chapter_directory_failure_rolls_back_insert_and_retry_is_single() {
    let (dir, s, w, _) = setup();
    let c = connection(&dir);
    c.execute_batch("CREATE TRIGGER fail_position BEFORE UPDATE OF order_index ON novel_documents BEGIN SELECT RAISE(ABORT,'synthetic position fault'); END;").unwrap();
    assert_eq!(
        s.create_chapter(w.clone(), "Retry".into())
            .unwrap_err()
            .code,
        "storage_error"
    );
    assert_eq!(s.list_chapters(w.clone()).unwrap().len(), 1);
    c.execute_batch("DROP TRIGGER fail_position").unwrap();
    assert_eq!(
        s.create_chapter(w.clone(), "Retry".into())
            .unwrap()
            .order_index,
        1
    );
    assert_eq!(s.list_chapters(w).unwrap().len(), 2);
}
#[test]
fn actual_sqlite_write_lock_keeps_revision_and_retry_succeeds() {
    let (dir, s, w, d) = setup();
    s.save(w.clone(), d.clone(), None, "before".into()).unwrap();
    let c = connection(&dir);
    c.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert_eq!(
        s.save(w.clone(), d.clone(), Some(1), "after".into())
            .unwrap_err()
            .code,
        "storage_error"
    );
    assert_eq!(s.load(w.clone(), d.clone()).unwrap().revision, Some(1));
    c.execute_batch("ROLLBACK").unwrap();
    assert_eq!(
        s.save(w, d, Some(1), "after".into()).unwrap().revision,
        Some(2)
    );
}
#[test]
fn prepared_review_rejects_revision_hash_identity_and_head_drift() {
    let (dir, s, w, d) = setup();
    let raw = "  e\u{301}\r\n😀\t尾  ";
    s.save(w.clone(), d.clone(), None, raw.into()).unwrap();
    let r = s
        .prepare_confirmation(w.clone(), d.clone(), None, 1)
        .unwrap();
    assert_eq!(r.body, raw);
    assert_eq!(
        s.confirm_chapter("foreign".into(), d.clone(), r.token.clone())
            .unwrap_err()
            .code,
        "identity_mismatch"
    );
    let c = connection(&dir);
    c.execute(
        "UPDATE working_copies SET body='changed without revision' WHERE document_id=?1",
        [&d],
    )
    .unwrap();
    assert_eq!(
        s.confirm_chapter(w.clone(), d.clone(), r.token.clone())
            .unwrap_err()
            .code,
        "revision_conflict"
    );
    c.execute(
        "UPDATE working_copies SET body=?2 WHERE document_id=?1",
        params![d, raw],
    )
    .unwrap();
    c.execute("INSERT INTO novel_versions(id,document_id,body,origin,created_at) VALUES('external',?1,'external','user','t')",[&d]).unwrap();
    c.execute(
        "UPDATE novel_documents SET head_version_id='external' WHERE id=?1",
        [&d],
    )
    .unwrap();
    assert_eq!(
        s.confirm_chapter(w.clone(), d.clone(), r.token)
            .unwrap_err()
            .code,
        "head_conflict"
    );
    assert_eq!(
        s.prepare_confirmation(w.clone(), d.clone(), Some("external".into()), 1)
            .unwrap_err()
            .code,
        "base_conflict"
    );
    c.execute(
        "UPDATE novel_documents SET head_version_id=NULL WHERE id=?1",
        [&d],
    )
    .unwrap();
    let r = s
        .prepare_confirmation(w.clone(), d.clone(), None, 1)
        .unwrap();
    c.execute(
        "UPDATE working_copies SET base_head_version='external' WHERE document_id=?1",
        [&d],
    )
    .unwrap();
    assert_eq!(
        s.confirm_chapter(w.clone(), d.clone(), r.token.clone())
            .unwrap_err()
            .code,
        "base_conflict"
    );
    c.execute(
        "UPDATE working_copies SET base_head_version=NULL WHERE document_id=?1",
        [&d],
    )
    .unwrap();
    s.save(w.clone(), d.clone(), Some(1), "new".into()).unwrap();
    assert_eq!(
        s.confirm_chapter(w, d, r.token).unwrap_err().code,
        "revision_conflict"
    );
}
#[test]
fn review_context_is_bound_before_decision() {
    let (_dir, s, w, d) = setup();
    let other = s.create_chapter(w.clone(), "Other".into()).unwrap().id;
    s.save(w.clone(), d.clone(), None, "review me".into())
        .unwrap();
    let review = s
        .prepare_confirmation(w.clone(), d.clone(), None, 1)
        .unwrap();
    s.save(w.clone(), other.clone(), None, "context addition".into())
        .unwrap();
    let other_review = s
        .prepare_confirmation(w.clone(), other.clone(), None, 1)
        .unwrap();
    s.confirm_chapter(w.clone(), other, other_review.token)
        .unwrap();
    assert_eq!(
        s.confirm_chapter(w.clone(), d.clone(), review.token)
            .unwrap_err()
            .code,
        "context_conflict"
    );
    assert!(s.list_versions(w.clone(), d.clone()).unwrap().is_empty());
    let fresh = s
        .prepare_confirmation(w.clone(), d.clone(), None, 1)
        .unwrap();
    s.confirm_chapter(w, d, fresh.token).unwrap();
}
#[test]
fn reorder_preserves_lore_absolute_position() {
    let (dir, s, w, d) = setup();
    let c = connection(&dir);
    c.execute("INSERT INTO novel_documents(id,work_id,kind,title,created_at,updated_at,order_index) VALUES('lore',?1,'character','Lore','t','t',1)",[&w]).unwrap();
    let last = s.create_chapter(w.clone(), "Last".into()).unwrap().id;
    s.reorder_chapters(w, vec![last.clone(), d.clone()])
        .unwrap();
    let rows: Vec<String> = c
        .prepare("SELECT id FROM novel_documents ORDER BY order_index")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(rows, vec![last, "lore".into(), d]);
}
#[test]
fn ui_session_optional_fields_and_fractional_scroll() {
    let (_dir, s, w, _) = setup();
    for raw in [
        r#"{"schemaVersion":1.0,"scrollTop":0.25}"#,
        r#"{"schemaVersion":1}"#,
        r#"{"schemaVersion":1,"chapterId":"","wide":false}"#,
    ] {
        s.set_ui_session(w.clone(), raw.into()).unwrap();
    }
    for raw in [
        r#"{"schemaVersion":1,"scrollTop":null}"#,
        r#"{"schemaVersion":1,"chapterId":null}"#,
        r#"{"schemaVersion":1,"chapterId":5}"#,
        r#"{"schemaVersion":1,"wide":"true"}"#,
        r#"{"schemaVersion":1,"scrollTop":1e999}"#,
    ] {
        assert_eq!(
            s.set_ui_session(w.clone(), raw.into()).unwrap_err().code,
            "invalid_input"
        );
    }
}
