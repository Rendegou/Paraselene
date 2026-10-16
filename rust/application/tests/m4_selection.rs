//! Selection and snapshot operations share one critical section with close.
use paraselene_application::Session;
use std::sync::{Arc, Barrier};
fn setup() -> (tempfile::TempDir, Session, Vec<String>) {
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
    let works = (0..3)
        .map(|i| s.create_work(format!("Synthetic {i}")).unwrap().id)
        .collect::<Vec<_>>();
    s.select_work(works[0].clone()).unwrap();
    (dir, s, works)
}
#[test]
fn concurrent_selection_snapshots_keep_selected_and_recent_consistent() {
    let (_dir, s, works) = setup();
    let barrier = Arc::new(Barrier::new(6));
    std::thread::scope(|scope| {
        for work in &works {
            let barrier = barrier.clone();
            let s = s.clone();
            scope.spawn(move || {
                barrier.wait();
                for _ in 0..40 {
                    s.select_work(work.clone()).unwrap();
                }
            });
        }
        for _ in 0..3 {
            let barrier = barrier.clone();
            let s = s.clone();
            scope.spawn(move || {
                barrier.wait();
                for _ in 0..80 {
                    let view = s.workspace_state().unwrap();
                    assert_eq!(
                        view.selected_work_id.as_deref(),
                        Some(view.recent_works[0].id.as_str())
                    );
                }
            });
        }
    });
    let view = s.workspace_state().unwrap();
    assert_eq!(
        view.selected_work_id.as_deref(),
        Some(view.recent_works[0].id.as_str())
    );
}
#[test]
fn failed_selection_preserves_state_and_calls_after_close_fail() {
    let (dir, s, works) = setup();
    let c = rusqlite::Connection::open(dir.path().join("synthetic.sqlite3")).unwrap();
    c.execute_batch("CREATE TRIGGER fail_recent BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT,'synthetic recent fault'); END;").unwrap();
    assert_eq!(
        s.select_work(works[1].clone()).unwrap_err().code,
        "storage_error"
    );
    let view = s.workspace_state().unwrap();
    assert_eq!(view.selected_work_id.as_deref(), Some(works[0].as_str()));
    assert_eq!(view.recent_works[0].id, works[0]);
    c.execute_batch("DROP TRIGGER fail_recent").unwrap();
    s.close().unwrap();
    assert_eq!(
        s.select_work(works[1].clone()).unwrap_err().code,
        "session_closed"
    );
    assert_eq!(s.workspace_state().unwrap_err().code, "session_closed");
}
