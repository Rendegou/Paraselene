//! G13 scoped-CSP probe. Fixed assets only; no user code or private data.
//! Run scripts/prepare-webview2-probe.ps1 before building.

use std::time::Duration;
use tauri::http::{Response, StatusCode};
use tauri::{WebviewUrl, WebviewWindowBuilder};

const LEARNING_CSP: &str = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src blob:; connect-src 'self'; style-src 'self' 'unsafe-inline'";

#[tauri::command]
fn probe_ping() -> &'static str {
    "pong"
}

fn asset(request_path: &str) -> Option<(Vec<u8>, &'static str)> {
    let (relative, content_type) = match request_path {
        "/probe.html" => return Some((b"<!doctype html><html><head><meta charset=\"utf-8\"><title>PROBE:scoped</title></head><body><script src=\"/sandbox-probe.js\"></script></body></html>".to_vec(), "text/html; charset=utf-8")),
        "/probe-result.html" => ("probe-result.html", "text/html; charset=utf-8"),
        "/sandbox-probe.js" => ("sandbox-probe.js", "text/javascript"),
        "/sandbox-probe-worker.js" => ("sandbox-probe-worker.js", "text/javascript"),
        "/pyodide/pyodide.mjs" => ("pyodide/pyodide.mjs", "text/javascript"),
        "/pyodide/pyodide.asm.mjs" => ("pyodide/pyodide.asm.mjs", "text/javascript"),
        "/pyodide/pyodide.asm.wasm" => ("pyodide/pyodide.asm.wasm", "application/wasm"),
        "/pyodide/pyodide-lock.json" => ("pyodide/pyodide-lock.json", "application/json"),
        "/pyodide/python_stdlib.zip" => ("pyodide/python_stdlib.zip", "application/zip"),
        _ => return None,
    };
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../dist")
        .join(relative);
    let mut bytes = std::fs::read(path).ok()?;
    if request_path == "/sandbox-probe.js" || request_path == "/sandbox-probe-worker.js" {
        let source = String::from_utf8(bytes).ok()?
            .replace("http://tauri.localhost", "http://learning-sandbox.localhost")
            .replace("http://probe-assets.localhost", "http://learning-sandbox.localhost");
        bytes = source.into_bytes();
    }
    Some((bytes, content_type))
}

fn main() {
    tauri::Builder::default()
        .register_uri_scheme_protocol("learning-sandbox", |context, request| {
            if context.webview_label() != "scoped-sandbox-probe" {
                return Response::builder().status(StatusCode::FORBIDDEN).body(Vec::new()).unwrap();
            }
            let Some((bytes, content_type)) = asset(request.uri().path()) else {
                return Response::builder().status(StatusCode::NOT_FOUND).body(Vec::new()).unwrap();
            };
            Response::builder()
                .header("Content-Type", content_type)
                .header("Content-Security-Policy", LEARNING_CSP)
                .header("X-Content-Type-Options", "nosniff")
                .body(bytes)
                .unwrap()
        })
        .invoke_handler(tauri::generate_handler![probe_ping])
        .setup(|app| {
            let url = "learning-sandbox://localhost/probe.html".parse().unwrap();
            WebviewWindowBuilder::new(app, "scoped-sandbox-probe", WebviewUrl::CustomProtocol(url))
                .title("PROBE:scoped-starting")
                .visible(false)
                .on_page_load(|window, payload| {
                    let Ok(url) = window.url() else { return };
                    println!("SCOPED_PAGE_LOAD:{:?}:{}", payload.event(), url.path());
                    if payload.event() == tauri::webview::PageLoadEvent::Finished && url.path() == "/probe-result.html" {
                        let report = url.query_pairs().find(|(name, _)| name == "report").map(|(_, value)| value.into_owned());
                        let parsed = report.as_deref().and_then(|value| serde_json::from_str::<serde_json::Value>(value).ok());
                        let valid = parsed.as_ref().is_some_and(|value| {
                            let worker = &value["worker"];
                            let violations = worker["cspViolations"].as_array();
                            let blocked = |uri: &str| violations.is_some_and(|items| items.iter().any(|item| item["blockedUri"].as_str().is_some_and(|s| s.contains(uri))));
                            value["main"]["ping"] == "pong"
                                && worker["final"] == true
                                && worker["pyodideLoaded"] == true
                                && worker["workerTauriBridge"] == false
                                && worker["workerIpcGlobal"] == false
                                && worker["workerWebviewBridge"] == false
                                && worker["pythonFileExists"] == false
                                && worker["pythonJsBridge"] == false
                                && worker["externalFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
                                && worker["fileFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
                                && worker["ipcFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
                                && worker["pythonExternalFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
                                && blocked("example.com") && blocked("file") && blocked("ipc.localhost")
                        });
                        println!("SCOPED_ASSERT:{}", if valid { "PASS" } else { "FAIL" });
                        if !valid { println!("SCOPED_REPORT:{:?}", parsed); }
                        std::process::exit(if valid { 0 } else { 1 });
                    }
                })
                .build()?;
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(60));
                eprintln!("SCOPED_TIMEOUT");
                std::process::exit(2);
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("scoped WebView2 probe failed");
}
