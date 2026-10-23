//! Packaged stage-B workspace with an explicitly scoped synthetic SQLite database.
//! Never opens application data or exposes credential/model commands.
use paraselene_lib::commands::{novel, studio_export, studio_workspace, studio_generation};
use std::sync::Arc;
use tauri::{WebviewUrl, WebviewWindowBuilder};

struct ProbeFaults {
    fail_body_saves: bool,
}

/// Explicit test-only failure injection; normal probe uses the actual core write.
#[tauri::command]
fn novel_save_working_copy(
    state: tauri::State<'_, novel::NovelState>,
    faults: tauri::State<'_, ProbeFaults>,
    document_id: String,
    expected_revision: Option<i64>,
    base_head: Option<String>,
    body: String,
) -> Result<paraselene_memory_core::WorkingCopy, String> {
    if faults.fail_body_saves {
        return Err("合成验收：正文写入故障".into());
    }
    state
        .db
        .save_working_copy(&document_id, expected_revision, base_head.as_deref(), &body)
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn app_ready() -> bool {
    true
}

/// Synthetic geometry only: no text, keys, credentials or document payloads.
#[tauri::command]
fn probe_geometry(value: String) {
    println!("PROBE_GEOMETRY:{value}");
}

#[tauri::command]
fn studio_finish_close(app: tauri::AppHandle) {
    app.exit(0);
}

fn main() {
    let path = std::env::args_os()
        .nth(1)
        .map(std::path::PathBuf::from)
        .expect("pass an explicit synthetic database path");
    let db = Arc::new(
        paraselene_memory_core::Database::open(&path).expect("synthetic database unavailable"),
    );
    let mut context = tauri::generate_context!();
    context.config_mut().app.windows.clear();
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(novel::NovelState::new(db))
        .manage(ProbeFaults {
            fail_body_saves: std::env::args_os()
                .skip(2)
                .any(|argument| argument == "--fail-body-saves"),
        })
        .invoke_handler(tauri::generate_handler![
            app_ready,
            probe_geometry,
            studio_finish_close,
            studio_generation::novel_working_edit_preview,
            studio_generation::novel_working_edit_cancel,
            studio_generation::novel_working_operations,
            studio_generation::novel_working_edit_apply,
            studio_generation::novel_working_edit_reject,
            novel::novel_create_document,
            novel::novel_document_summaries,
            novel::novel_get_document,
            novel::novel_rename_document,
            novel::novel_reorder_documents,
            novel::novel_get_working_copy,
            novel_save_working_copy,
            novel::novel_list_versions,
            novel::novel_list_lore,
            novel::novel_create_lore,
            novel::novel_lore_versions,
            novel::novel_add_source_anchor,
            studio_workspace::novel_list_works,
            studio_workspace::novel_create_work,
            studio_workspace::novel_select_work,
            studio_workspace::novel_workspace_state,
            studio_workspace::novel_set_document_archived,
            studio_workspace::novel_archived_document_summaries,
            studio_workspace::novel_save_thread,
            studio_workspace::novel_list_threads,
            studio_workspace::novel_bind_lore_source_anchor,
            studio_workspace::novel_list_lore_source_anchors,
            studio_workspace::novel_get_ui_session,
            studio_workspace::novel_set_ui_session,
            studio_workspace::novel_save_lore_entry,
            studio_workspace::novel_confirm_working_copy,
            studio_workspace::novel_rollback_working_copy,
            studio_export::studio_export
        ])
        .setup(|app| {
            let window =
                WebviewWindowBuilder::new(app, "studio", WebviewUrl::App("index.html".into()))
                    .title("幻月 · B阶段合成验收")
                    .inner_size(1280.0, 800.0)
                    .min_inner_size(760.0, 560.0)
                    .initialization_script(r#"
                      setInterval(() => {
                        const nodes = ['.cm-scroller','.cm-content','.cm-gutters','.cm-gutter','.cm-line'];
                        if (!document.querySelector('.cm-line')) return;
                        const value = nodes.map(selector => {
                          const element = document.querySelector(selector);
                          if (!element) return {selector, missing:true};
                          const style = getComputedStyle(element), rect = element.getBoundingClientRect();
                          return {selector,display:style.display,direction:style.flexDirection,position:style.position,
                            top:rect.top,left:rect.left,height:rect.height,width:rect.width};
                        });
                        const signature = JSON.stringify(value);
                        if (window.__probeGeometry === signature) return;
                        window.__probeGeometry = signature;
                        window.__TAURI_INTERNALS__.invoke('probe_geometry',{value:signature});
                      },1000);
                    "#)
                    .build()?;
            println!(
                "PROBE_NATIVE:scale={:?}:size={:?}",
                window.scale_factor(),
                window.inner_size()
            );
            Ok(())
        })
        .run(context)
        .expect("isolated native workspace probe failed");
}
