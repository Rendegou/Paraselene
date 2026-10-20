//! Local loopback SSE + fake credential only. Never instantiate the keyring.
//!
//! 测试范围：在本地 loopback SSE 与临时合成根上验证生成预览/发送/取消/失败落库契约。
//! 不代表真实 DeepSeek 端点、生产 FFI 或 Windows 凭据存储已通过。
use super::*;
use paraselene_llm_core::OpenAiCompatClient;
use serde_json::{json, Value};
use std::{
    io::{Read, Write},
    net::TcpListener,
    time::Duration,
};

struct Fixture {
    _root: tempfile::TempDir,
    session: Session,
    work: String,
    chapter: String,
    body: String,
}
impl Fixture {
    fn new() -> Self {
        let root = tempfile::Builder::new()
            .prefix("paraselene-m1-")
            .tempdir()
            .unwrap();
        std::fs::write(
            root.path().join("M1_SYNTHETIC_ONLY"),
            b"paraselene-m1-synthetic-v1\n",
        )
        .unwrap();
        let session = Session::open_synthetic(root.path().to_string_lossy().into_owned()).unwrap();
        let work = session.create_work("M7 synthetic".into()).unwrap().id;
        let chapter = session
            .create_chapter(work.clone(), "one".into())
            .unwrap()
            .id;
        let body = "👩‍💻 old\r\né é مرحبا".to_owned();
        session
            .save(work.clone(), chapter.clone(), None, body.clone())
            .unwrap();
        let snapshot = json!({"schemaVersion":1,"id":"thread","chapterId":chapter,"draft":"rewrite",
            "target":{"chapterId":chapter,"from":6,"to":9,"text":"old","baseBody":body},
            "anchor":{"from":6,"to":9,"valid":true},"attached":[],"requests":[],
            "candidate":null,"versions":[],"view":"discussion","compare":false});
        session
            .save_thread(
                work.clone(),
                chapter.clone(),
                "thread".into(),
                None,
                snapshot.to_string(),
            )
            .unwrap();
        session
            .activate_generation_scope(Some(work.clone()), Some(chapter.clone()))
            .unwrap();
        session.set_cloud_enabled(true).unwrap();
        Self {
            _root: root,
            session,
            work,
            chapter,
            body,
        }
    }
    fn preview(&self, operation: &str) -> String {
        let document = self
            .session
            .load(self.work.clone(), self.chapter.clone())
            .unwrap();
        let request = json!({"workId":self.work,"documentId":self.chapter,"threadId":"thread",
            "operationId":operation,"expectedRevision":document.revision,"baseBody":document.body,
            "from":6,"to":9,"selectedText":"old","instruction":"rewrite","referenceIds":[]});
        let preview: Value = serde_json::from_str(
            &self
                .session
                .prepare_generation(request.to_string())
                .unwrap(),
        )
        .unwrap();
        assert!(preview["prepared"]["messages"].is_array());
        preview["id"].as_str().unwrap().into()
    }
}

fn server(
    delay: Duration,
    complete: bool,
) -> (
    String,
    tokio::sync::oneshot::Receiver<()>,
    std::thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/v1", listener.local_addr().unwrap());
    let (ready, received) = tokio::sync::oneshot::channel();
    let handle = std::thread::spawn(move || {
        listener.set_nonblocking(true).unwrap();
        let started = std::time::Instant::now();
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(started.elapsed() < Duration::from_secs(30));
                    std::thread::sleep(Duration::from_millis(5));
                }
                Err(e) => panic!("loopback accept: {e}"),
            }
        };
        // Windows accepted sockets can inherit the listener's nonblocking mode.
        // Reads below deliberately use a blocking stream with an explicit bound.
        socket.set_nonblocking(false).unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(15)))
            .unwrap();
        let mut request = Vec::new();
        let mut bytes = [0u8; 2048];
        loop {
            let count = socket.read(&mut bytes).unwrap();
            assert!(count > 0);
            request.extend_from_slice(&bytes[..count]);
            if let Some(end) = request.windows(4).position(|b| b == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..end]).to_lowercase();
                let length: usize = headers
                    .lines()
                    .find_map(|line| line.strip_prefix("content-length:"))
                    .unwrap()
                    .trim()
                    .parse()
                    .unwrap();
                if request.len() >= end + 4 + length {
                    assert!(headers.contains("authorization: bearer synthetic-fake-key"));
                    break;
                }
            }
        }
        let _ = ready.send(());
        std::thread::sleep(delay);
        let events = if complete {
            "data: {\"choices\":[{\"delta\":{\"content\":\"new\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        } else {
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n"
        };
        if socket.write_all(format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", events.len()).as_bytes()).is_ok() {
            // Split every byte to cover arbitrary HTTP/SSE transport boundaries.
            for byte in events.bytes() { if socket.write_all(&[byte]).is_err() { break; } }
        }
    });
    (url, received, handle)
}

#[tokio::test]
async fn local_sse_candidate_atomic_failure_undo_and_duplicate_ticket() {
    let fixture = Fixture::new();
    let preview = fixture.preview("op");
    let (url, _, handle) = server(Duration::ZERO, true);
    fixture
        .session
        .run_generation(
            fixture.work.clone(),
            preview.clone(),
            OpenAiCompatClient::new(url).unwrap(),
            || Ok("synthetic-fake-key".into()),
        )
        .await
        .unwrap();
    handle.join().unwrap();
    assert_eq!(
        fixture
            .session
            .load(fixture.work.clone(), fixture.chapter.clone())
            .unwrap()
            .body,
        fixture.body
    );
    let repeated = fixture
        .session
        .run_generation(
            fixture.work.clone(),
            preview,
            OpenAiCompatClient::new("http://127.0.0.1:1").unwrap(),
            || panic!("duplicate must not read key"),
        )
        .await;
    assert!(repeated.is_err());
    fixture.session.with_db(|db| db.with_conn(|c| {
        c.execute_batch("CREATE TEMP TRIGGER fail_candidate BEFORE UPDATE ON novel_patches BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;")?; Ok(())
    }).map_err(core_error)).unwrap();
    assert!(fixture
        .session
        .apply_operation(
            fixture.work.clone(),
            fixture.chapter.clone(),
            "op".into(),
            Some(1)
        )
        .is_err());
    assert_eq!(
        fixture
            .session
            .load(fixture.work.clone(), fixture.chapter.clone())
            .unwrap()
            .body,
        fixture.body
    );
    fixture
        .session
        .with_db(|db| {
            db.with_conn(|c| {
                c.execute_batch("DROP TRIGGER fail_candidate")?;
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    fixture
        .session
        .apply_operation(
            fixture.work.clone(),
            fixture.chapter.clone(),
            "op".into(),
            Some(1),
        )
        .unwrap();
    let applied = fixture
        .session
        .load(fixture.work.clone(), fixture.chapter.clone())
        .unwrap();
    assert_eq!(applied.body, fixture.body.replace("old", "new"));
    assert!(fixture
        .session
        .apply_operation(
            fixture.work.clone(),
            fixture.chapter.clone(),
            "op".into(),
            Some(2)
        )
        .is_err());
    fixture
        .session
        .save(
            fixture.work.clone(),
            fixture.chapter.clone(),
            Some(2),
            fixture.body.clone(),
        )
        .unwrap();
    let operations: Value = serde_json::from_str(
        &fixture
            .session
            .list_operations(fixture.work.clone(), fixture.chapter.clone())
            .unwrap(),
    )
    .unwrap();
    assert_eq!(operations[0]["patchStatus"], "applied");
    fixture.session.close().unwrap();
}

#[tokio::test]
async fn cancellation_or_disconnect_never_publishes_partial_candidate() {
    for cancel in [false, true] {
        let fixture = Fixture::new();
        let preview = fixture.preview("op");
        let (url, ready, handle) = server(Duration::from_millis(100), false);
        let session = fixture.session.clone();
        let work = fixture.work.clone();
        let request = tokio::spawn(async move {
            session
                .run_generation(work, preview, OpenAiCompatClient::new(url).unwrap(), || {
                    Ok("synthetic-fake-key".into())
                })
                .await
        });
        ready.await.unwrap();
        if cancel {
            fixture
                .session
                .cancel_generation(fixture.work.clone(), "op".into())
                .unwrap();
        }
        assert!(request.await.unwrap().is_err());
        handle.join().unwrap();
        let rows: Value = serde_json::from_str(
            &fixture
                .session
                .list_operations(fixture.work.clone(), fixture.chapter.clone())
                .unwrap(),
        )
        .unwrap();
        assert!(rows[0]["patchId"].is_null());
        assert_eq!(
            rows[0]["status"],
            if cancel { "cancelled" } else { "failed" }
        );
        assert_eq!(
            fixture
                .session
                .load(fixture.work.clone(), fixture.chapter.clone())
                .unwrap()
                .body,
            fixture.body
        );
        fixture.session.close().unwrap();
    }
}

#[tokio::test]
async fn abandoned_future_and_cloud_disable_release_thread_without_candidate() {
    for disable in [false, true] {
        let fixture = Fixture::new();
        let preview = fixture.preview("abandon");
        let (url, ready, handle) = server(Duration::from_millis(150), true);
        let session = fixture.session.clone();
        let work = fixture.work.clone();
        let task = tokio::spawn(async move {
            session
                .run_generation(work, preview, OpenAiCompatClient::new(url).unwrap(), || {
                    Ok("synthetic-fake-key".into())
                })
                .await
        });
        ready.await.unwrap();
        if disable {
            fixture.session.set_cloud_enabled(false).unwrap();
            assert!(task.await.unwrap().is_err());
        } else {
            task.abort();
            assert!(task.await.unwrap_err().is_cancelled());
        }
        handle.join().unwrap();
        let rows: Value = serde_json::from_str(
            &fixture
                .session
                .list_operations(fixture.work.clone(), fixture.chapter.clone())
                .unwrap(),
        )
        .unwrap();
        assert_eq!(rows[0]["status"], "cancelled");
        assert!(rows[0]["patchId"].is_null());
        fixture.session.set_cloud_enabled(true).unwrap();
        fixture.preview("next"); // The abandoned thread is no longer busy.
        fixture.session.close().unwrap();
    }
}

#[tokio::test]
async fn timed_out_complete_response_cannot_arrive_as_candidate() {
    let fixture = Fixture::new();
    let preview = fixture.preview("timeout");
    let (url, ready, handle) = server(Duration::from_secs(2), true);
    let session = fixture.session.clone();
    let work = fixture.work.clone();
    let task = tokio::spawn(async move {
        session
            .run_generation_with_timeout(
                work,
                preview,
                OpenAiCompatClient::new(url).unwrap(),
                || Ok("synthetic-fake-key".into()),
                Duration::from_secs(1),
            )
            .await
    });
    ready.await.unwrap(); // Prove transport started before testing a late response.
    let result = task.await.unwrap();
    assert!(result.is_err());
    handle.join().unwrap();
    let rows: Value = serde_json::from_str(
        &fixture
            .session
            .list_operations(fixture.work.clone(), fixture.chapter.clone())
            .unwrap(),
    )
    .unwrap();
    assert_eq!(rows[0]["status"], "failed");
    assert!(rows[0]["patchId"].is_null());
    assert_eq!(
        fixture
            .session
            .load(fixture.work.clone(), fixture.chapter.clone())
            .unwrap()
            .body,
        fixture.body
    );
    fixture.session.close().unwrap();
}

#[tokio::test]
async fn long_chapter_four_operations_reopen_keeps_next_author_draft_isolated() {
    let mut fixture = Fixture::new();
    fixture
        .body
        .push_str(&"文".repeat(200_000 - fixture.body.chars().count()));
    fixture
        .session
        .save(
            fixture.work.clone(),
            fixture.chapter.clone(),
            Some(1),
            fixture.body.clone(),
        )
        .unwrap();
    for index in 0..4 {
        let preview = fixture.preview(&format!("operation-{index}"));
        let (url, _, handle) = server(Duration::ZERO, true);
        fixture
            .session
            .run_generation(
                fixture.work.clone(),
                preview,
                OpenAiCompatClient::new(url).unwrap(),
                || Ok("synthetic-fake-key".into()),
            )
            .await
            .unwrap();
        handle.join().unwrap();
    }
    let threads: Value = serde_json::from_str(
        &fixture
            .session
            .list_threads(fixture.work.clone(), fixture.chapter.clone())
            .unwrap(),
    )
    .unwrap();
    let mut snapshot = threads[0]["snapshot"].clone();
    snapshot["draft"] = json!("next unsent 👩‍💻\r\né é");
    fixture
        .session
        .save_thread(
            fixture.work.clone(),
            fixture.chapter.clone(),
            "thread".into(),
            threads[0]["revision"].as_i64(),
            snapshot.to_string(),
        )
        .unwrap();
    fixture.session.close().unwrap();
    let reopened =
        Session::open_synthetic(fixture._root.path().to_string_lossy().into_owned()).unwrap();
    assert_eq!(
        reopened
            .load(fixture.work.clone(), fixture.chapter.clone())
            .unwrap()
            .body,
        fixture.body
    );
    let operations: Value = serde_json::from_str(
        &reopened
            .list_operations(fixture.work.clone(), fixture.chapter.clone())
            .unwrap(),
    )
    .unwrap();
    assert_eq!(operations.as_array().unwrap().len(), 4);
    let threads: Value = serde_json::from_str(
        &reopened
            .list_threads(fixture.work, fixture.chapter)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(threads[0]["snapshot"]["draft"], snapshot["draft"]);
    assert!(threads[0]["snapshot"]["requests"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(threads[0]["snapshot"]["candidate"].is_null());
    reopened.close().unwrap();
}
