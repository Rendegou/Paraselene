//! 幻月桌宠外壳（T03）。
//!
//! 职责边界（AGENTS.md §3）：本 crate 只负责窗口/托盘/IPC 转发；
//! 业务逻辑一律在 crates/ 下的纯 Rust crate 中，这里不写业务。
//! 窗口配置在 tauri.conf.json；托盘与窗口命令在这里，业务规则在纯 Rust 核心。

pub mod commands;
mod learning_window;
#[cfg(test)]
mod quiet;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Manager, Emitter};
use tauri::State;

struct RuntimeState {
    started: std::time::Instant,
}

#[derive(serde::Serialize)]
struct RuntimeActivity {
    uptime_seconds: u64,
    model_network_attempts: u64,
    scan_invocations: u64,
}

/// 只返回进程内计数与运行时长，不包含请求、路径、正文。
#[tauri::command]
fn runtime_activity(state: State<'_, RuntimeState>) -> RuntimeActivity {
    RuntimeActivity {
        uptime_seconds: state.started.elapsed().as_secs(),
        model_network_attempts: commands::llm::network_attempts(),
        scan_invocations: paraselene_memory_core::scanner::scan_invocations(),
    }
}

/// 供前端 lib/ipc.ts 调用的链路自检命令。
/// 输入：无；输出："pong"；无副作用。
#[tauri::command]
fn ping() -> String {
    "pong".to_string()
}

/// WebView 可能先于 setup 完成加载；状态全部注册后才允许读取设置。
#[tauri::command]
fn app_ready(app: tauri::AppHandle) -> bool {
    app.try_state::<RuntimeState>().is_some()
        && app
            .try_state::<commands::character::CharacterState>()
            .is_some()
        && app.try_state::<commands::ideas::IdeaState>().is_some()
        && app.try_state::<commands::novel::NovelState>().is_some()
        && app.try_state::<commands::memory::MemoryState>().is_some()
        && app.try_state::<commands::import::ImportState>().is_some()
        && app.try_state::<commands::llm::LlmState>().is_some()
}

/// 切换小卡片，不创建重复窗口；只由用户点击或托盘菜单触发。
#[tauri::command]
fn toggle_card(app: tauri::AppHandle) -> tauri::Result<()> {
    if let Some(card) = app.get_webview_window("card") {
        if card.is_visible()? {
            card.hide()?;
        } else {
            card.show()?;
            card.set_focus()?;
        }
    }
    Ok(())
}

/// 卡片右上角关闭按钮只隐藏窗口，保留下一次打开时的状态。
#[tauri::command]
fn hide_card(app: tauri::AppHandle) -> tauri::Result<()> {
    if let Some(card) = app.get_webview_window("card") {
        card.hide()?;
    }
    Ok(())
}

#[tauri::command]
fn studio_finish_close(app: tauri::AppHandle) { app.exit(0); }

/// 构建托盘：菜单「显示 / 退出」。
/// 托盘图标复用窗口默认图标（icons/32x32.png，由 `pnpm tauri icon` 生成）。
fn setup_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "打开小说工作台", true, None::<&str>)?;
    let card = MenuItem::with_id(app, "card", "原有资料与设置", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &card, &quit])?;

    TrayIconBuilder::with_id("main-tray")
        .icon(app.default_window_icon().cloned().ok_or_else(|| {
            tauri::Error::AssetNotFound("default window icon missing; run `pnpm tauri icon`".into())
        })?)
        .menu(&menu)
        .tooltip("幻月")
        .on_menu_event(|app, event| match event.id().as_ref() {
            "quit" => {
                if let Some(window) = app.get_webview_window("studio") {
                    let _ = window.emit("studio-exit-requested", ());
                } else { app.exit(0); }
            },
            "show" => {
                if let Some(w) = app.get_webview_window("studio") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            "card" => {
                let _ = toggle_card(app.clone());
            }
            _ => {}
        })
        .build(app)?;
    Ok(())
}

/// 初始化记忆库（app 数据目录下 index.db；settings KV 存每空间云开关等运行状态）。
fn setup_database(
    app: &tauri::AppHandle,
) -> tauri::Result<std::sync::Arc<paraselene_memory_core::Database>> {
    let dir = app.path().app_data_dir()?;
    let db = paraselene_memory_core::Database::open(&dir.join("index.db"))
        .map_err(|e| tauri::Error::AssetNotFound(format!("记忆库初始化失败: {e}")))?;
    Ok(std::sync::Arc::new(db))
}

pub fn run() {
    tauri::Builder::default()
        .register_uri_scheme_protocol("learning-sandbox", learning_window::serve)
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            ping,
            app_ready,
            toggle_card,
            hide_card,
            studio_finish_close,
            learning_window::open_learning_window,
            runtime_activity,
            commands::key::set_api_key,
            commands::key::has_api_key,
            commands::key::delete_api_key,
            commands::llm::llm_chat_preview,
            commands::llm::llm_chat_send,
            commands::llm::llm_fetch_models,
            commands::llm::get_cloud_enabled,
            commands::llm::set_cloud_enabled,
            commands::character::get_character,
            commands::character::set_character,
            commands::character::export_character_pack,
            commands::character::import_character_pack,
            commands::memory::memory_list,
            commands::memory::memory_detail,
            commands::memory::memory_source,
            commands::memory::memory_correct,
            commands::memory::memory_delete,
            commands::memory::memory_export,
            commands::ideas::suggest_old_idea,
            commands::ideas::list_old_ideas,
            commands::ideas::confirm_old_idea,
            commands::ideas::confirm_old_idea_status,
            commands::ideas::old_idea_source,
            commands::ideas::convert_old_idea,
            commands::ideas::converted_idea_target,
            commands::ideas::update_converted_idea_target,
            commands::ideas::set_old_idea_reminder,
            commands::novel::open_novel_editor,
            commands::novel::open_editor_spike,
            commands::novel::active_novel_work,
            commands::novel::novel_create_document,
            commands::novel::novel_list_documents,
            commands::novel::novel_document_summaries,
            commands::novel::novel_get_document,
            commands::novel::novel_rename_document,
            commands::novel::novel_reorder_documents,
            commands::novel::novel_get_working_copy,
            commands::novel::novel_save_working_copy,
            commands::novel::novel_delete_working_copy,
            commands::novel::novel_generate_edit_patch,
            commands::novel::novel_apply_patch,
            commands::novel::novel_reject_patch,
            commands::novel::novel_list_lore,
            commands::novel::novel_find_lore,
            commands::novel::novel_create_lore,
            commands::novel::novel_update_lore,
            commands::novel::novel_resolve_lore,
            commands::novel::novel_lore_versions,
            commands::novel::novel_add_source_anchor,
            commands::novel::novel_list_source_anchors,
            commands::novel::novel_create_user_draft,
            commands::novel::novel_list_drafts,
            commands::novel::novel_accept_draft,
            commands::novel::novel_draft_conflicts,
            commands::novel::novel_open_questions,
            commands::novel::novel_discard_draft,
            commands::novel::novel_list_versions,
            commands::novel::novel_rollback_document,
            commands::novel::novel_ai_preview,
            commands::novel::novel_edit_preview,
            commands::novel::novel_ai_generate,
            commands::novel::novel_rpg_scene_preview,
            commands::novel::novel_rpg_generate_scene,
            commands::novel::novel_rpg_response_preview,
            commands::studio_workspace::novel_list_works,
            commands::studio_workspace::novel_create_work,
            commands::studio_workspace::novel_select_work,
            commands::studio_workspace::novel_workspace_state,
            commands::studio_workspace::novel_set_document_archived,
            commands::studio_workspace::novel_archived_document_summaries,
            commands::studio_workspace::novel_save_thread,
            commands::studio_workspace::novel_list_threads,
            commands::studio_workspace::novel_bind_lore_source_anchor,
            commands::studio_workspace::novel_list_lore_source_anchors,
            commands::studio_workspace::novel_get_ui_session,
            commands::studio_workspace::novel_set_ui_session,
            commands::studio_workspace::novel_save_lore_entry,
            commands::studio_workspace::novel_confirm_working_copy,
            commands::studio_workspace::novel_rollback_working_copy,
            commands::studio_generation::novel_working_edit_preview,
            commands::studio_generation::novel_working_edit_send,
            commands::studio_generation::novel_working_edit_cancel,
            commands::studio_generation::novel_working_operations,
            commands::studio_generation::novel_working_edit_apply,
            commands::studio_generation::novel_working_edit_reject,
            commands::import::select_import_file,
            commands::import::confirm_import_file,
            commands::import::cancel_import_preview,
            commands::studio_export::studio_export,
        ])
        .setup(|app| {
            setup_tray(app.handle())?;
            // 小说前端优先：不启动桌宠的常驻通知轮询。旧适配器保留供历史窗口使用。
            // LLM 状态：memory-core 的 Database（Arc 供异步命令克隆）
            let db = setup_database(app.handle())?;
            app.manage(RuntimeState {
                started: std::time::Instant::now(),
            });
            app.manage(commands::character::CharacterState { db: db.clone() });
            app.manage(commands::memory::MemoryState { db: db.clone() });
            app.manage(commands::ideas::IdeaState { db: db.clone() });
            app.manage(commands::novel::NovelState::new(db.clone()));
            app.manage(commands::import::ImportState::new(db.clone()));
            app.manage(commands::llm::LlmState {
                db,
                previews: std::sync::Mutex::new(paraselene_llm_core::PreviewLedger::default()),
            });
            // SPIKE（T05B 临时）：设置 PARASELENE_SPIKE=1 直接打开编辑器验证窗口，
            // 供原生 WebView2 实测；spike 结论后移除。
            if std::env::var_os("PARASELENE_SPIKE").is_some() {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    // 等 WebView 运行时就绪；线程睡眠仅 300ms 的一次性 spike 触发。
                    std::thread::sleep(std::time::Duration::from_millis(300));
                    if let Err(e) = commands::novel::open_editor_spike(handle).await {
                        eprintln!("spike window failed: {e}");
                    }
                });
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running 幻月");
}
