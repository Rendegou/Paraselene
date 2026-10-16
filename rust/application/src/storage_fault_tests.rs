//! SQLITE_FULL is exercised on the application-owned connection, not mocked.
use crate::{core_error, Session};
#[test]
fn sqlite_full_does_not_advance_revision_and_can_retry() {
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
    s.save(w.clone(), d.clone(), None, "before".into()).unwrap();
    s.with_db(|db| {
        db.with_conn(|c| {
            let pages: i64 = c.query_row("PRAGMA page_count", [], |r| r.get(0))?;
            c.pragma_update(None, "max_page_count", pages)?;
            Ok(())
        })
        .map_err(core_error)
    })
    .unwrap();
    assert_eq!(
        s.save(w.clone(), d.clone(), Some(1), "😀".repeat(200000))
            .unwrap_err()
            .code,
        "storage_error"
    );
    let loaded = s.load(w.clone(), d.clone()).unwrap();
    assert_eq!(loaded.body, "before");
    assert_eq!(loaded.revision, Some(1));
    s.with_db(|db| {
        db.with_conn(|c| {
            c.pragma_update(None, "max_page_count", 1_000_000)?;
            Ok(())
        })
        .map_err(core_error)
    })
    .unwrap();
    assert_eq!(
        s.save(w, d, Some(1), "after".into()).unwrap().revision,
        Some(2)
    );
}
