//! Real SQLite author snapshot isolation/CAS/reopen. No model or credential calls.
use paraselene_application::Session;
use serde_json::{json, Value};

fn snapshot(chapter: &str) -> Value {
    json!({"schemaVersion":1,"id":"thread","chapterId":chapter,"draft":"next\r\né é 👩‍💻",
        "target":null,"anchor":null,"attached":[],"requests":[],"candidate":null,
        "versions":[],"view":"discussion","compare":false})
}

#[test]
fn author_snapshot_cas_scope_reopen_and_server_projection_isolation() {
    let dir = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    std::fs::write(
        dir.path().join("M1_SYNTHETIC_ONLY"),
        b"paraselene-m1-synthetic-v1\n",
    )
    .unwrap();
    let path = dir.path().to_string_lossy().into_owned();
    let session = Session::open_synthetic(path.clone()).unwrap();
    let work = session.create_work("synthetic M5".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "one".into())
        .unwrap();
    let other = session.create_work("other".into()).unwrap();
    let author = snapshot(&chapter.id);
    let saved: Value = serde_json::from_str(
        &session
            .save_thread(
                work.id.clone(),
                chapter.id.clone(),
                "thread".into(),
                None,
                author.to_string(),
            )
            .unwrap(),
    )
    .unwrap();
    assert_eq!(saved["revision"], 1);
    assert!(session
        .save_thread(
            work.id.clone(),
            chapter.id.clone(),
            "thread".into(),
            None,
            author.to_string()
        )
        .is_err());
    assert!(session.list_threads(other.id, chapter.id.clone()).is_err());
    let mut derived = author.clone();
    derived["requests"] = json!([{"operationId":"server","id":"r","text":"derived"}]);
    assert_eq!(
        session
            .save_thread(
                work.id.clone(),
                chapter.id.clone(),
                "thread".into(),
                Some(1),
                derived.to_string()
            )
            .unwrap_err()
            .code,
        "derived_thread_content"
    );
    assert_eq!(
        session
            .list_operations(work.id.clone(), chapter.id.clone())
            .unwrap(),
        "[]"
    );
    session.close().unwrap();
    let reopened = Session::open_synthetic(path).unwrap();
    let rows: Value =
        serde_json::from_str(&reopened.list_threads(work.id, chapter.id).unwrap()).unwrap();
    assert_eq!(rows[0]["snapshot"], author);
    reopened.close().unwrap();
}
