//! 明确授权的文件导入 IPC。系统选择器只交给原生层路径；预览票据只在本进程有效。

use std::sync::{Arc, Mutex};

use paraselene_memory_core::import_file::read_import_file;
use paraselene_memory_core::imports::{import_package, partial, ImportPackage};
use paraselene_memory_core::Database;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_dialog::DialogExt;

struct PendingImport {
    token: String,
    package: ImportPackage,
}

pub struct ImportState {
    db: Arc<Database>,
    pending: Mutex<Option<PendingImport>>,
}

impl ImportState {
    pub fn new(db: Arc<Database>) -> Self {
        Self {
            db,
            pending: Mutex::new(None),
        }
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSample {
    role: String,
    text: String,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportReview {
    token: String,
    file_name: String,
    source: String,
    detected_format: String,
    sessions: usize,
    messages: usize,
    partial: usize,
    failed_files: usize,
    warning_count: usize,
    warnings: Vec<String>,
    sample_title: Option<String>,
    sample_messages: Vec<ImportSample>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportCompletion {
    written: usize,
    duplicates: usize,
    write_failed: usize,
    indexed: usize,
    scan_failed: usize,
    messages: u64,
    warning_count: usize,
}

/// 用户打开系统文件选择器。取消返回 None；选中后只解析预览，不写托管副本或索引。
#[tauri::command]
pub async fn select_import_file(
    app: AppHandle,
    state: State<'_, ImportState>,
    source: String,
) -> Result<Option<ImportReview>, String> {
    if !matches!(source.as_str(), "chatgpt" | "codex" | "kimi" | "claude") {
        return Err("请选择受支持的对话来源".into());
    }
    *state.pending.lock().map_err(|_| "导入预览状态不可用")? = None;
    let extensions: &[&str] = if source == "chatgpt" {
        &["zip", "md", "json", "jsonl", "txt"]
    } else {
        &["md", "json", "jsonl", "txt"]
    };
    let selected = app
        .dialog()
        .file()
        .add_filter("对话导出", extensions)
        .blocking_pick_file();
    let Some(selected) = selected else {
        return Ok(None);
    };
    let path = selected.into_path().map_err(|_| "只能导入本机文件")?;
    let file_name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "所选文件".into());
    let parsed = tauri::async_runtime::spawn_blocking({
        let source = source.clone();
        move || read_import_file(&path, &source)
    })
    .await
    .map_err(|_| "读取导出文件时发生错误")?
    .map_err(|error| error.user_message())?;
    let token = uuid::Uuid::new_v4().to_string();
    let sample = parsed.package.sessions.first();
    let review = ImportReview {
        token: token.clone(),
        file_name,
        source,
        detected_format: parsed.format.label().to_string(),
        sessions: parsed.package.sessions.len(),
        messages: parsed
            .package
            .sessions
            .iter()
            .map(|session| session.messages.len())
            .sum(),
        partial: parsed
            .package
            .sessions
            .iter()
            .filter(|session| partial(session))
            .count(),
        failed_files: parsed.failed_files,
        warning_count: parsed.warnings.len(),
        warnings: parsed.warnings.iter().take(5).cloned().collect(),
        sample_title: sample.and_then(|session| session.title.clone()),
        sample_messages: sample
            .map(|session| {
                session
                    .messages
                    .iter()
                    .take(2)
                    .map(|message| ImportSample {
                        role: message.role.clone(),
                        text: message.text.chars().take(360).collect(),
                    })
                    .collect()
            })
            .unwrap_or_default(),
    };
    *state.pending.lock().map_err(|_| "导入预览状态不可用")? = Some(PendingImport {
        token,
        package: parsed.package,
    });
    Ok(Some(review))
}

/// 仅消费当前预览的票据。用户取消、换文件或重复确认后旧票据不能写库。
#[tauri::command]
pub async fn confirm_import_file(
    app: AppHandle,
    state: State<'_, ImportState>,
    token: String,
) -> Result<ImportCompletion, String> {
    let package = {
        let mut guard = state.pending.lock().map_err(|_| "导入预览状态不可用")?;
        if guard.as_ref().map(|pending| pending.token.as_str()) != Some(token.as_str()) {
            return Err("预览已过期，请重新选择文件".into());
        }
        guard.take().ok_or("预览已过期，请重新选择文件")?.package
    };
    let root = app
        .path()
        .app_data_dir()
        .map_err(|_| "无法定位应用数据目录")?
        .join("imports");
    let db = state.db.clone();
    let (written, scanned) =
        tauri::async_runtime::spawn_blocking(move || import_package(&db, &root, &package))
            .await
            .map_err(|_| "导入任务意外中断")?
            .map_err(|error| error.user_message())?;
    Ok(ImportCompletion {
        written: written.success,
        duplicates: written.duplicates,
        write_failed: written.failed,
        indexed: scanned.indexed,
        scan_failed: scanned.failed,
        messages: scanned.messages,
        warning_count: written.warnings.len() + scanned.warnings.len(),
    })
}

/// 放弃尚未确认的预览，立即释放原生进程内的解析数据。
#[tauri::command]
pub fn cancel_import_preview(state: State<'_, ImportState>, token: String) -> Result<(), String> {
    let mut guard = state.pending.lock().map_err(|_| "导入预览状态不可用")?;
    if guard.as_ref().map(|pending| pending.token.as_str()) == Some(token.as_str()) {
        *guard = None;
    }
    Ok(())
}
