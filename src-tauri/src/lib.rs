//! 幻月桌宠外壳（T00 原型）。
//!
//! 职责边界（AGENTS.md §3）：本 crate 只负责窗口/托盘/IPC 转发；
//! 业务逻辑一律在 crates/ 下的纯 Rust crate 中，这里不写业务。
//! 当前为占位原型：窗口配置在 tauri.conf.json（透明/无边框/置顶/不进任务栏/不可缩放），
//! 托盘提供「显示/退出」，IPC 仅暴露 ping 用于验证前端 ↔ Rust 链路。

pub mod commands;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::Manager;

/// 供前端 lib/ipc.ts 调用的链路自检命令。
/// 输入：无；输出："pong"；无副作用。
#[tauri::command]
fn ping() -> String {
    "pong".to_string()
}

/// 构建托盘：菜单「显示 / 退出」。
/// 托盘图标复用窗口默认图标（icons/32x32.png，由 `pnpm tauri icon` 生成）。
fn setup_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "显示", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    TrayIconBuilder::with_id("main-tray")
        .icon(app.default_window_icon().cloned().ok_or_else(|| {
            tauri::Error::AssetNotFound("default window icon missing; run `pnpm tauri icon`".into())
        })?)
        .menu(&menu)
        .tooltip("幻月")
        .on_menu_event(|app, event| match event.id().as_ref() {
            "quit" => app.exit(0),
            "show" => {
                if let Some(w) = app.get_webview_window("pet") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            _ => {}
        })
        .build(app)?;
    Ok(())
}

/// 初始化记忆库（app 数据目录下 index.db；settings KV 存每空间云开关等运行状态）。
fn setup_database(app: &tauri::AppHandle) -> tauri::Result<std::sync::Arc<paraselene_memory_core::Database>> {
    let dir = app.path().app_data_dir()?;
    let db = paraselene_memory_core::Database::open(&dir.join("index.db"))
        .map_err(|e| tauri::Error::AssetNotFound(format!("记忆库初始化失败: {e}")))?;
    Ok(std::sync::Arc::new(db))
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            ping,
            commands::key::set_api_key,
            commands::key::has_api_key,
            commands::key::delete_api_key,
            commands::llm::llm_chat_preview,
            commands::llm::llm_chat_send,
            commands::llm::llm_fetch_models,
        ])
        .setup(|app| {
            setup_tray(app.handle())?;
            // LLM 状态：memory-core 的 Database（Arc 供异步命令克隆）
            let db = setup_database(app.handle())?;
            app.manage(commands::llm::LlmState { db });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running 幻月");
}
