//! Shell-only learning window: fixed resources and a per-window CSP.
//! Learner code is evaluated exclusively in a Blob module Worker.

use tauri::http::{Request, Response, StatusCode};
use tauri::{Manager, UriSchemeContext, WebviewUrl, WebviewWindowBuilder, Wry};

pub const LEARNING_CSP: &str = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src blob:; connect-src 'self'; style-src 'self'";

fn static_asset(path: &str) -> Option<(&'static [u8], &'static str)> {
    match path {
        "/" | "/index.html" => Some((
            include_bytes!("../learning/learning.html"),
            "text/html; charset=utf-8",
        )),
        "/learning.js" => Some((include_bytes!("../learning/learning.js"), "text/javascript")),
        "/learning.css" => Some((include_bytes!("../learning/learning.css"), "text/css")),
        "/worker.js" => Some((include_bytes!("../learning/worker.js"), "text/javascript")),
        _ => None,
    }
}

pub fn allowed_origin(uri: &tauri::http::Uri) -> bool {
    matches!(
        (uri.scheme_str(), uri.host()),
        (Some("learning-sandbox"), Some("localhost"))
            | (Some("http"), Some("learning-sandbox.localhost"))
    )
}

pub fn serve(context: UriSchemeContext<'_, Wry>, request: Request<Vec<u8>>) -> Response<Vec<u8>> {
    if context.webview_label() != "learning" || !allowed_origin(request.uri()) {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .body(Vec::new())
            .unwrap();
    }
    let path = request.uri().path();
    let resource = static_asset(path).map(|(bytes, kind)| (bytes.to_vec(), kind));
    let resource = resource.or_else(|| {
        let name = path.strip_prefix("/pyodide/")?;
        let kind = match name {
            "pyodide.mjs" | "pyodide.asm.mjs" => "text/javascript",
            "pyodide.asm.wasm" => "application/wasm",
            "pyodide-lock.json" => "application/json",
            "python_stdlib.zip" => "application/zip",
            _ => return None,
        };
        let asset = context
            .app_handle()
            .asset_resolver()
            .get(format!("learning/pyodide/{name}"))?;
        Some((asset.bytes, kind))
    });
    let Some((bytes, kind)) = resource else {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Vec::new())
            .unwrap();
    };
    Response::builder()
        .header("Content-Type", kind)
        .header("Content-Security-Policy", LEARNING_CSP)
        .header("X-Content-Type-Options", "nosniff")
        .header("Cache-Control", "no-store")
        .body(bytes)
        .unwrap()
}

#[tauri::command]
pub fn open_learning_window(app: tauri::AppHandle) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window("learning") {
        window.show()?;
        window.set_focus()?;
        return Ok(());
    }
    let url = "learning-sandbox://localhost/index.html".parse().unwrap();
    WebviewWindowBuilder::new(&app, "learning", WebviewUrl::CustomProtocol(url))
        .title("幻月 · 五分钟练习")
        .inner_size(760.0, 620.0)
        .min_inner_size(520.0, 420.0)
        .build()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{allowed_origin, static_asset};

    #[test]
    fn learning_static_asset_whitelist_rejects_paths() {
        assert!(static_asset("/index.html").is_some());
        assert!(static_asset("/worker.js").is_some());
        assert!(static_asset("/../index.html").is_none());
        assert!(static_asset("/other.js").is_none());
    }

    #[test]
    fn only_learning_scheme_hosts_are_allowed() {
        assert!(allowed_origin(
            &"learning-sandbox://localhost/index.html".parse().unwrap()
        ));
        assert!(allowed_origin(
            &"http://learning-sandbox.localhost/worker.js"
                .parse()
                .unwrap()
        ));
        assert!(!allowed_origin(
            &"http://tauri.localhost/index.html".parse().unwrap()
        ));
        assert!(!allowed_origin(&"https://example.com/".parse().unwrap()));
    }

    #[test]
    fn general_windows_do_not_receive_learning_csp_permissions() {
        let config: serde_json::Value =
            serde_json::from_str(include_str!("../tauri.conf.json")).unwrap();
        for policy in ["csp", "devCsp"] {
            let value = &config["app"]["security"][policy];
            assert!(
                value.get("worker-src").is_none(),
                "{policy} must not allow Blob Worker globally"
            );
            assert!(
                !value.to_string().contains("wasm-unsafe-eval"),
                "{policy} must not allow WASM eval globally"
            );
            assert!(
                !value.to_string().contains("learning-sandbox"),
                "{policy} must not allow learning assets globally"
            );
        }
    }
}
