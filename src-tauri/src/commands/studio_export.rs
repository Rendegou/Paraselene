//! Explicit preview/recovery export. Only the native save dialog supplies a path.

use std::{fs, io::Write, path::Path};
use tauri_plugin_dialog::DialogExt;

const MAX_EXPORT_BYTES: usize = 16 * 1024 * 1024;

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExportPayload {
    file_name: String,
    content: String,
    format: ExportFormat,
}

#[derive(Clone, Copy, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
enum ExportFormat {
    Markdown,
    Json,
}

impl ExportFormat {
    fn extension(self) -> &'static str {
        match self {
            Self::Markdown => "md",
            Self::Json => "json",
        }
    }
}

#[derive(serde::Serialize)]
#[serde(tag = "status", rename_all = "lowercase")]
pub enum ExportResult {
    Cancelled,
    Saved,
}

fn export_name(name: &str, format: ExportFormat) -> String {
    let clean: String = name
        .chars()
        .filter(|ch| !ch.is_control() && !"<>:\"/\\|?*".contains(*ch))
        .take(100)
        .collect();
    let clean = clean.trim().trim_matches(['.', ' ']);
    let stem = clean.split('.').next().unwrap_or("").to_ascii_uppercase();
    let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || matches!(
            stem.strip_prefix("COM")
                .or_else(|| stem.strip_prefix("LPT")),
            Some("1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9")
        );
    let clean = if clean.is_empty() || reserved {
        "幻月导出"
    } else {
        clean
    };
    let suffix = format!(".{}", format.extension());
    if clean.to_ascii_lowercase().ends_with(&suffix) {
        clean.to_owned()
    } else {
        format!("{clean}{suffix}")
    }
}

fn validate_payload(payload: &ExportPayload) -> Result<(), String> {
    if payload.content.len() > MAX_EXPORT_BYTES {
        return Err("导出内容超过 16 MiB，请分章导出。".into());
    }
    if matches!(payload.format, ExportFormat::Json)
        && serde_json::from_str::<serde_json::Value>(&payload.content).is_err()
    {
        return Err("导出数据不是有效 JSON，请保留草稿并重试。".into());
    }
    Ok(())
}

/// Write beside the destination, then replace it. A failed write preserves an existing export.
fn write_export(path: &Path, content: &str) -> Result<(), String> {
    let parent = path.parent().ok_or("请选择本机文件保存位置。")?;
    let temporary = parent.join(format!(".paraselene-export-{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| -> std::io::Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(content.as_bytes())?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
        return Err("导出文件写入失败，请检查位置、权限或文件占用后重试；草稿仍保留。".into());
    }
    Ok(())
}

/// Export only the supplied snapshot; this command never reads the novel database.
#[tauri::command]
pub async fn studio_export(
    window: tauri::WebviewWindow,
    payload: ExportPayload,
) -> Result<ExportResult, String> {
    validate_payload(&payload)?;
    let name = export_name(&payload.file_name, payload.format);
    let selected = window
        .dialog()
        .file()
        .set_parent(&window)
        .set_title("导出当前写作稿")
        .set_file_name(name)
        .add_filter("写作稿", &[payload.format.extension()])
        .blocking_save_file();
    let Some(selected) = selected else {
        return Ok(ExportResult::Cancelled);
    };
    let path = selected
        .into_path()
        .map_err(|_| "请选择本机文件保存位置。")?;
    tauri::async_runtime::spawn_blocking(move || write_export(&path, &payload.content))
        .await
        .map_err(|_| "导出任务中断，请保留草稿并重试。")??;
    Ok(ExportResult::Saved)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filenames_cannot_supply_paths_or_windows_devices() {
        assert_eq!(export_name("../CON", ExportFormat::Markdown), "幻月导出.md");
        assert_eq!(
            export_name("LPT9.json", ExportFormat::Json),
            "幻月导出.json"
        );
        assert_eq!(
            export_name("章节😀.md", ExportFormat::Markdown),
            "章节😀.md"
        );
        assert!(!export_name("C:\\draft/正文", ExportFormat::Json).contains([':', '\\', '/']));
    }

    #[test]
    fn export_checks_byte_limit_and_json_before_opening_dialog() {
        let mut payload = ExportPayload {
            file_name: "test".into(),
            content: "{}".into(),
            format: ExportFormat::Json,
        };
        assert!(validate_payload(&payload).is_ok());
        payload.content = "invalid".into();
        assert!(validate_payload(&payload).is_err());
        payload.format = ExportFormat::Markdown;
        payload.content = "文".repeat(MAX_EXPORT_BYTES / 3 + 1);
        assert!(validate_payload(&payload).is_err());
    }

    #[test]
    fn utf8_overwrite_and_failure_do_not_report_success() {
        let directory =
            std::env::temp_dir().join(format!("paraselene-export-test-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&directory).unwrap();
        let path = directory.join("test.md");
        write_export(&path, "中文😀\r\n原稿").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "中文😀\r\n原稿");
        write_export(&path, "新稿").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "新稿");
        assert!(write_export(&directory, "不可替换目录").is_err());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_file(path).unwrap();
        fs::remove_dir(directory).unwrap();
    }
}
