//! G13 WebView2 probe. Hidden window, fixed source, no user code or private files.
//! Prepare dist assets using scripts/prepare-webview2-probe.ps1 before building.

use std::time::Duration;
use tauri::http::{Response, StatusCode};
use tauri::{WebviewUrl, WebviewWindowBuilder};

#[tauri::command]
fn probe_ping() -> &'static str {
    "pong"
}

fn main() {
    tauri::Builder::default()
        .register_uri_scheme_protocol("probe-assets", |_ctx, request| {
            let name = request.uri().path().strip_prefix("/pyodide/").unwrap_or("");
            let content_type = match name {
                "pyodide-lock.json" => "application/json",
                "pyodide.asm.mjs" | "pyodide.mjs" => "text/javascript",
                "pyodide.asm.wasm" => "application/wasm",
                "python_stdlib.zip" => "application/zip",
                _ => {
                    return Response::builder()
                        .status(StatusCode::NOT_FOUND)
                        .body(Vec::new())
                        .unwrap()
                }
            };
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../dist/pyodide")
                .join(name);
            match std::fs::read(path) {
                Ok(bytes) => Response::builder()
                    .header("Content-Type", content_type)
                    .header("Access-Control-Allow-Origin", "*")
                    .body(bytes)
                    .unwrap(),
                Err(_) => Response::builder()
                    .status(StatusCode::NOT_FOUND)
                    .body(Vec::new())
                    .unwrap(),
            }
        })
        .invoke_handler(tauri::generate_handler![probe_ping])
        .setup(|app| {
            WebviewWindowBuilder::new(app, "sandbox-probe", WebviewUrl::App("probe.html".into()))
                .title("PROBE:starting")
                .visible(false)
                .on_page_load(|window, payload| {
                    let Ok(url) = window.url() else { return };
                    println!("PROBE_PAGE_LOAD:{:?}:{}", payload.event(), url.path());
                    if payload.event() == tauri::webview::PageLoadEvent::Finished
                        && url.path() == "/probe-result.html"
                    {
                        let report = url
                            .query_pairs()
                            .find(|(name, _)| name == "report")
                            .map(|(_, value)| value.into_owned());
                        let parsed = report.as_deref().and_then(|value| {
                            serde_json::from_str::<serde_json::Value>(value).ok()
                        });
                        let valid = parsed.as_ref().is_some_and(|value| {
                            let worker = &value["worker"];
                            let violations = worker["cspViolations"].as_array();
                            let blocked = |uri: &str| {
                                violations.is_some_and(|items| {
                                    items.iter().any(|item| {
                                        item["blockedUri"]
                                            .as_str()
                                            .is_some_and(|value| value.contains(uri))
                                    })
                                })
                            };
                            value["main"]["ping"] == "pong"
                                && worker["final"] == true
                                && worker["pyodideLoaded"] == true
                                && worker["workerTauriBridge"] == false
                                && worker["workerIpcGlobal"] == false
                                && worker["workerWebviewBridge"] == false
                                && worker["pythonFileExists"] == false
                                && worker["pythonJsBridge"] == false
                                && worker["externalFetch"]
                                    .as_str()
                                    .is_some_and(|s| s.starts_with("rejected:"))
                                && worker["fileFetch"]
                                    .as_str()
                                    .is_some_and(|s| s.starts_with("rejected:"))
                                && worker["ipcFetch"]
                                    .as_str()
                                    .is_some_and(|s| s.starts_with("rejected:"))
                                && worker["pythonExternalFetch"]
                                    .as_str()
                                    .is_some_and(|s| s.starts_with("rejected:"))
                                && blocked("example.com")
                                && blocked("file")
                                && blocked("ipc.localhost")
                        });
                        println!("PROBE_ASSERT:{}", if valid { "PASS" } else { "FAIL" });
                        if !valid {
                            println!("PROBE_REPORT:{:?}", parsed);
                        }
                        std::process::exit(if valid { 0 } else { 1 });
                    }
                })
                .build()?;
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(60));
                eprintln!("PROBE_TIMEOUT");
                std::process::exit(2);
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("WebView2 probe failed");
}
