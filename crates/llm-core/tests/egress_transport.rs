//! SIMULATED model service on loopback; exercises real HTTP serialization and cancellation.
use std::io::{Read, Write};
use std::sync::mpsc;
use std::time::Duration;

use paraselene_llm_core::{
    AllowAll, CallPurpose, EgressError, EgressLedger, Message, ModelProposal, OpenAiCompatClient,
    RunScope, Space, StreamEvent,
};

fn authorized() -> (
    EgressLedger,
    String,
    String,
    String,
    paraselene_llm_core::AuthorizedCall,
) {
    let mut ledger = EgressLedger::default();
    let grant = ledger
        .begin(
            &AllowAll,
            RunScope {
                space: Space::Idea,
                work_id: None,
            },
            "fixture-model".into(),
        )
        .unwrap();
    let preview = ledger
        .prepare(
            &AllowAll,
            &grant.id,
            ModelProposal {
                model: "fixture-model".into(),
                messages: vec![Message::user("合成输入，仅测试")],
                max_tokens: Some(32),
                temperature: None,
                tools: None,
                purpose: CallPurpose::Conversation,
            },
        )
        .unwrap();
    let call = ledger.authorize(&AllowAll, &grant.id, &preview.id).unwrap();
    (ledger, grant.id, preview.id, preview.body_json, call)
}

fn server() -> (String, mpsc::Receiver<Vec<u8>>) {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut bytes = Vec::new();
        let (header_end, length) = loop {
            let mut chunk = [0u8; 2048];
            let read = socket.read(&mut chunk).unwrap();
            assert_ne!(read, 0);
            bytes.extend_from_slice(&chunk[..read]);
            if let Some(end) = bytes.windows(4).position(|b| b == b"\r\n\r\n") {
                let headers = std::str::from_utf8(&bytes[..end]).unwrap();
                let len = headers
                    .lines()
                    .find_map(|line| {
                        let (key, value) = line.split_once(':')?;
                        key.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().unwrap())
                    })
                    .unwrap();
                break (end + 4, len);
            }
        };
        while bytes.len() < header_end + length {
            let mut chunk = [0u8; 2048];
            let read = socket.read(&mut chunk).unwrap();
            assert_ne!(read, 0);
            bytes.extend_from_slice(&chunk[..read]);
        }
        tx.send(bytes[header_end..header_end + length].to_vec())
            .unwrap();
        let body = concat!(
            "data: {\"choices\":[{\"delta\":{\"content\":\"one\"},\"finish_reason\":null}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"two\"},\"finish_reason\":null}]}\n\n",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
            "data: [DONE]\n\n"
        );
        write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
    });
    (format!("http://{addr}/v1"), rx)
}

#[tokio::test]
async fn actual_http_body_is_byte_for_byte_the_native_approved_preview() {
    let (mut ledger, run_id, call_id, preview, call) = authorized();
    let (url, body) = server();
    let client = OpenAiCompatClient::new(url).unwrap();
    let mut events = Vec::new();
    call.execute(&client, "synthetic-not-a-credential", |event| {
        events.push(event);
        true
    })
    .await
    .unwrap();
    assert_eq!(
        body.recv_timeout(Duration::from_secs(2)).unwrap(),
        preview.as_bytes()
    );
    assert_eq!(
        events
            .iter()
            .filter(|event| matches!(event, StreamEvent::Delta { .. }))
            .count(),
        2
    );
    assert!(matches!(events.last(), Some(StreamEvent::Done { .. })));
    ledger.settle(&run_id, &call_id);
    assert!(matches!(
        ledger.authorize(&AllowAll, &run_id, &call_id),
        Err(EgressError::InvalidTicket)
    ));
}

#[tokio::test]
async fn native_cancel_stops_already_buffered_deltas_and_does_not_report_success() {
    let (mut ledger, run_id, _, _, call) = authorized();
    let (url, body) = server();
    let client = OpenAiCompatClient::new(url).unwrap();
    let mut events = 0;
    let result = call
        .execute(&client, "synthetic-not-a-credential", |_| {
            events += 1;
            ledger.end(&run_id).unwrap();
            true
        })
        .await;
    assert_eq!(result, Err(EgressError::Cancelled));
    assert_eq!(
        events, 1,
        "no late delta or done after confirmed cancellation"
    );
    assert!(!body
        .recv_timeout(Duration::from_secs(2))
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn disconnected_consumer_drops_stream_instead_of_continuing_in_background() {
    let (mut ledger, run_id, call_id, _, call) = authorized();
    let (url, body) = server();
    let client = OpenAiCompatClient::new(url).unwrap();
    assert_eq!(
        call.execute(&client, "synthetic-not-a-credential", |_| false)
            .await,
        Err(EgressError::Disconnected)
    );
    assert!(!body
        .recv_timeout(Duration::from_secs(2))
        .unwrap()
        .is_empty());
    ledger.settle(&run_id, &call_id);
}
