//! 用户主动选取的会话文件：只读解析，绝不在预览阶段写库或修改来源。

use std::io::Read;
use std::path::Path;

use crate::error::{Error, Result};
use crate::imports::{parse_input, ImportFormat, ImportPackage, ImportSession, MAX_IMPORT_BYTES};

// 资源上限：防 zip 炸弹 / 手滑选错大文件。所有限制都在「读进内存」之前拦截。
/// ZIP 包自身大小上限（64 MiB）。
const MAX_ARCHIVE_BYTES: u64 = 64 * 1024 * 1024;
/// ZIP 内条目数上限（条目过多视为异常导出）。
const MAX_ARCHIVE_ENTRIES: usize = 2_000;
/// 解压后累计文本上限（128 MiB）：单条 16 MiB 限制防不住「一万个小文件」。
const MAX_TOTAL_TEXT_BYTES: u64 = 128 * 1024 * 1024;

/// 预览阶段完整解析结果，留在原生进程内等待用户确认。
pub struct ParsedImportFile {
    pub package: ImportPackage,
    pub warnings: Vec<String>,
    pub format: ImportFormat,
    pub failed_files: usize,
}

/// 只读取用户在系统文件选择器中指定的单个文件。支持 ChatGPT Markdown zip，
/// 以及单个 Markdown、JSON、JSONL、TXT 会话文件；失败告警只含序号和结构原因。
pub fn read_import_file(path: &Path, source: &str) -> Result<ParsedImportFile> {
    if !matches!(source, "chatgpt" | "codex" | "kimi" | "claude") {
        return Err(Error::parse("请选择受支持的对话来源"));
    }
    let metadata = std::fs::metadata(path).map_err(|e| Error::io(path, e))?;
    if !metadata.is_file() {
        return Err(Error::parse("请选择一个对话导出文件"));
    }
    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    match extension.as_str() {
        "zip" => read_chatgpt_zip(path, source, metadata.len()),
        "md" | "json" | "jsonl" | "txt" => {
            read_text_file(path, source, metadata.len(), metadata.modified().ok())
        }
        _ => Err(Error::parse("支持 .zip、.md、.json、.jsonl 或 .txt 文件")),
    }
}

fn read_text_file(
    path: &Path,
    source: &str,
    size: u64,
    modified: Option<std::time::SystemTime>,
) -> Result<ParsedImportFile> {
    // 双重上限：先看元数据大小，再在读取后复查实际字节数——
    // 元数据可能撒谎（并发改写 / 特殊文件系统），`take(N+1)` 保证读到第 N+1 字节即停。
    if size > MAX_IMPORT_BYTES as u64 {
        return Err(Error::parse("单个文本文件超过 16 MiB，请拆分后导入"));
    }
    let file = std::fs::File::open(path).map_err(|e| Error::io(path, e))?;
    let mut text = String::new();
    file.take(MAX_IMPORT_BYTES as u64 + 1)
        .read_to_string(&mut text)
        .map_err(|e| Error::io(path, e))?;
    if text.len() > MAX_IMPORT_BYTES {
        return Err(Error::parse("单个文本文件超过 16 MiB，请拆分后导入"));
    }
    let fallback = modified.map(|time| chrono::DateTime::<chrono::Utc>::from(time).to_rfc3339());
    let (package, warnings, format) = parse_input(source, &text, fallback.as_deref())?;
    Ok(ParsedImportFile {
        package,
        warnings,
        format,
        failed_files: 0,
    })
}

fn read_chatgpt_zip(path: &Path, source: &str, size: u64) -> Result<ParsedImportFile> {
    if source != "chatgpt" {
        return Err(Error::parse("ZIP 导出目前仅支持 ChatGPT Markdown"));
    }
    if size > MAX_ARCHIVE_BYTES {
        return Err(Error::parse("ZIP 超过 64 MiB，请拆分后导入"));
    }
    let file = std::fs::File::open(path).map_err(|e| Error::io(path, e))?;
    let mut archive =
        zip::ZipArchive::new(file).map_err(|_| Error::parse("无法读取 ZIP 导出包"))?;
    if archive.len() > MAX_ARCHIVE_ENTRIES {
        return Err(Error::parse("ZIP 文件条目过多，请拆分后导入"));
    }
    let mut total_text_bytes = 0u64;
    let mut sessions: Vec<ImportSession> = Vec::new();
    let mut warnings = Vec::new();
    let mut failed_files = 0;
    let mut markdown_files = 0;
    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|_| Error::parse("ZIP 条目读取失败"))?;
        // 容错策略：单个条目坏 → 计数 + 告警后继续，不拖垮整个导出包里的好会话；
        // 只有「包级」超限（大小 / 条目数 / 解压总量）才整体报错。
        if entry.is_dir() || !entry.name().to_ascii_lowercase().ends_with(".md") {
            continue;
        }
        markdown_files += 1;
        // 告警里只用序号不用文件名：导出包内路径可能含用户目录名（隐私）。
        let entry_number = markdown_files;
        if entry.size() > MAX_IMPORT_BYTES as u64 {
            failed_files += 1;
            warnings.push(format!("第 {entry_number} 个 Markdown 超过 16 MiB，已跳过"));
            continue;
        }
        let mut bytes = Vec::new();
        if (&mut entry)
            .take(MAX_IMPORT_BYTES as u64 + 1)
            .read_to_end(&mut bytes)
            .is_err()
        {
            failed_files += 1;
            warnings.push(format!("第 {entry_number} 个 Markdown 无法读取"));
            continue;
        }
        if bytes.len() > MAX_IMPORT_BYTES {
            failed_files += 1;
            warnings.push(format!("第 {entry_number} 个 Markdown 超过 16 MiB，已跳过"));
            continue;
        }
        total_text_bytes = total_text_bytes.saturating_add(bytes.len() as u64);
        if total_text_bytes > MAX_TOTAL_TEXT_BYTES {
            return Err(Error::parse("ZIP 解压后的文本超过 128 MiB，请拆分后导入"));
        }
        let text = match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => {
                failed_files += 1;
                warnings.push(format!("第 {entry_number} 个 Markdown 无法按 UTF-8 读取"));
                continue;
            }
        };
        let fallback = entry.last_modified().and_then(|date| {
            // ZIP 时间戳只有日期分量且可能是 1980 默认值；解析失败就干脆不给 fallback，
            // 由下游用导入时间兜底，避免假时间戳污染会话时间线。
            chrono::NaiveDate::from_ymd_opt(
                date.year() as i32,
                date.month() as u32,
                date.day() as u32,
            )
            .and_then(|day| {
                day.and_hms_opt(
                    date.hour() as u32,
                    date.minute() as u32,
                    date.second() as u32,
                )
            })
            .map(|date| date.and_utc().to_rfc3339())
        });
        match parse_input("chatgpt", &text, fallback.as_deref()) {
            Ok((package, mut parse_warnings, _)) => {
                sessions.extend(package.sessions);
                warnings.append(&mut parse_warnings);
            }
            Err(error) => {
                failed_files += 1;
                warnings.push(format!(
                    "第 {entry_number} 个 Markdown：{}",
                    error.user_message()
                ));
            }
        }
    }
    if markdown_files == 0 {
        return Err(Error::parse("ZIP 中没有 Markdown 对话文件"));
    }
    if sessions.is_empty() {
        return Err(Error::parse("ZIP 中没有可导入的对话"));
    }
    Ok(ParsedImportFile {
        package: ImportPackage {
            schema_version: 1,
            sessions,
        },
        warnings,
        format: ImportFormat::ChatGPTMarkdown,
        failed_files,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::imports::import_package;
    use crate::Database;
    use std::io::Write;

    const SAMPLE: &str =
        "# 合成想法\n\n#### You:\n\n我想做一只会睡觉的桌宠\n\n#### ChatGPT:\n\n听起来不错\n";

    #[test]
    fn 预览文本只读且解析出处() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("conversation.md");
        std::fs::write(&file, SAMPLE).unwrap();
        let before = blake3::hash(&std::fs::read(&file).unwrap());
        let parsed = read_import_file(&file, "chatgpt").unwrap();
        assert_eq!(parsed.package.sessions.len(), 1);
        assert_eq!(parsed.package.sessions[0].messages.len(), 2);
        assert_eq!(parsed.package.sessions[0].messages[0].role, "user");
        assert_eq!(blake3::hash(&std::fs::read(&file).unwrap()), before);
        assert_eq!(
            std::fs::read_dir(dir.path()).unwrap().count(),
            1,
            "预览不能创建托管副本"
        );
        assert!(read_import_file(&file, "bad-source").is_err());
    }

    #[test]
    fn zip_只取_markdown_坏条目给计数不阻断好会话() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("export.zip");
        let output = std::fs::File::create(&file).unwrap();
        let mut zip = zip::ZipWriter::new(output);
        let options = zip::write::SimpleFileOptions::default();
        zip.start_file("one.md", options).unwrap();
        zip.write_all(SAMPLE.as_bytes()).unwrap();
        zip.start_file("bad.md", options).unwrap();
        zip.write_all(b"invalid transcript").unwrap();
        zip.start_file("other.bin", options).unwrap();
        zip.write_all(b"ignored").unwrap();
        zip.finish().unwrap();
        let before = blake3::hash(&std::fs::read(&file).unwrap());
        let parsed = read_import_file(&file, "chatgpt").unwrap();
        assert_eq!(parsed.package.sessions.len(), 1);
        assert_eq!(parsed.failed_files, 1);
        assert!(!parsed.warnings.is_empty());
        assert_eq!(blake3::hash(&std::fs::read(&file).unwrap()), before);
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
        assert!(read_import_file(&file, "kimi").is_err());
    }

    #[test]
    fn 明确确认后才落库_重复确认不重复入库() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("conversation.md");
        std::fs::write(&source, SAMPLE).unwrap();
        let db = Database::open_in_memory().unwrap();
        let preview = read_import_file(&source, "chatgpt").unwrap();
        assert_eq!(db.stats().unwrap().sessions, 0, "预览不写索引");
        let managed = dir.path().join("managed");
        assert!(!managed.exists(), "预览不写托管副本");
        let (first, scan) = import_package(&db, &managed, &preview.package).unwrap();
        assert_eq!((first.success, scan.indexed, scan.messages), (1, 1, 2));
        let (second, again) = import_package(&db, &managed, &preview.package).unwrap();
        assert_eq!((second.duplicates, again.indexed), (1, 0));
        assert_eq!(db.stats().unwrap().sessions, 1);
    }
}
