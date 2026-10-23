//! Product-path smoke test: same fixed assets and protocol handler as the learning window.
//! Precondition: scripts/prepare-learning-assets.ps1 and a Vite build.

use std::time::Duration;
use tauri::http::{Response, StatusCode};
use tauri::{WebviewUrl, WebviewWindowBuilder};

#[path = "../src/learning_window.rs"]
#[allow(dead_code)]
mod learning_window;

const SECURITY_SCRIPT: &str = r#"(() => {
  const url = URL.createObjectURL(new Blob([
    "import('http://learning-sandbox.localhost/security-probe-worker.js').catch(error => self.postMessage({bootError:String(error)}));"
  ], {type:'text/javascript'}));
  let worker;
  try { worker = new Worker(url, {type:'module'}); }
  catch (error) { location.replace('/index.html?security=' + encodeURIComponent(JSON.stringify({workerError:String(error)}))); return; }
  const finish = (report) => {
    clearTimeout(timer);
    worker.terminate();
    URL.revokeObjectURL(url);
    location.replace('/index.html?security=' + encodeURIComponent(JSON.stringify(report)));
  };
  const timer = setTimeout(() => finish({timeout:true}), 45000);
  worker.onmessage = (event) => { if (!event.data?.stage) finish(event.data); };
  worker.onerror = (event) => finish({workerError:event.message || 'unknown'});
})();"#;

fn security_passes(report: &serde_json::Value) -> bool {
    let violations = report["cspViolations"].as_array();
    let blocked = |uri: &str| {
        violations.is_some_and(|items| items.iter().any(|item| {
            item["blockedUri"].as_str().is_some_and(|value| value.contains(uri))
        }))
    };
    report["final"] == true
        && report["pyodideLoaded"] == true
        && report["workerTauriBridge"] == false
        && report["workerIpcGlobal"] == false
        && report["workerWebviewBridge"] == false
        && report["pythonFileExists"] == false
        && report["pythonJsBridge"] == false
        && report["externalFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
        && report["fileFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
        && report["ipcFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
        && report["pythonExternalFetch"].as_str().is_some_and(|s| s.starts_with("rejected:"))
        && blocked("example.com") && blocked("file") && blocked("ipc.localhost")
}

fn main() {
    // Include native WebView creation in the deadline, not just page execution.
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(180));
        eprintln!("LEARNING_TIMEOUT");
        std::process::exit(2);
    });
    tauri::Builder::default()
        .register_uri_scheme_protocol("learning-sandbox", |context, request| {
            if request.uri().path() == "/security-probe-worker.js" {
                if context.webview_label() != "learning" || !learning_window::allowed_origin(request.uri()) {
                    return Response::builder().status(StatusCode::FORBIDDEN).body(Vec::new()).unwrap();
                }
                let source = include_str!("../../spikes/webview2-probe/sandbox-probe-worker.js")
                    .replace("http://probe-assets.localhost", "http://learning-sandbox.localhost");
                return Response::builder()
                    .header("Content-Type", "text/javascript")
                    .header("Content-Security-Policy", learning_window::LEARNING_CSP)
                    .header("X-Content-Type-Options", "nosniff")
                    .body(source.into_bytes())
                    .unwrap();
            }
            learning_window::serve(context, request)
        })
        .setup(|app| {
            println!("LEARNING_WINDOW:creating");
            let url = "learning-sandbox://localhost/index.html".parse().unwrap();
            WebviewWindowBuilder::new(app, "learning", WebviewUrl::CustomProtocol(url))
                .visible(false)
                .on_page_load(|window, payload| {
                    println!("LEARNING_PAGE_LOAD:{:?}", payload.event());
                    if payload.event() != tauri::webview::PageLoadEvent::Finished { return; }
                    let Ok(url) = window.url() else { return };
                    if let Some((_, verdict)) = url.query_pairs().find(|(key, _)| key == "probe") {
                        println!("LEARNING_ASSERT:{verdict}");
                        for (key, value) in url.query_pairs().filter(|(key, _)| key == "checks" || key == "reason") {
                            println!("LEARNING_{key}:{value}");
                        }
                        std::process::exit(if verdict == "PASS" { 0 } else { 1 });
                    }
                    let report = url.query_pairs().find(|(key, _)| key == "security")
                        .and_then(|(_, value)| serde_json::from_str::<serde_json::Value>(&value).ok());
                    if url.query_pairs().any(|(key, _)| key == "security") {
                        if !report.as_ref().is_some_and(security_passes) {
                            eprintln!("LEARNING_SECURITY_ASSERT:FAIL:{report:?}");
                            std::process::exit(1);
                        }
                        println!("LEARNING_SECURITY_ASSERT:PASS");
                    } else {
                        if let Err(error) = window.eval(SECURITY_SCRIPT) {
                            eprintln!("LEARNING_SECURITY_EVAL_ERROR:{error}");
                            std::process::exit(1);
                        }
                        return;
                    }
                    let script = include_str!("learning-regression.js");
                    if let Err(error) = window.eval(script) {
                        eprintln!("LEARNING_EVAL_ERROR:{error}");
                        std::process::exit(1);
                    }
                })
                .build()?;
            println!("LEARNING_WINDOW:created");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("learning window probe failed");
}
