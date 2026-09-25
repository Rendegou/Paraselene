//! 真实导出包导入实测（T01 第二片验收）：ChatGPT Markdown zip → 托管副本 → 扫描入库。
//!
//! 隐私红线（AGENTS.md §4）：本程序只打印**计数与统计**，绝不打印对话正文、
//! 会话标题或 zip 内文件名（文件名即对话标题）。
//!
//! 用法：
//!   cargo run --example import_chatgpt_export -- <zip路径> <工作目录>
//! 工作目录下生成 `imports/`（托管副本）与 `index.db`（索引），均为可删除的缓存。

use std::io::Read;
use std::path::PathBuf;

use paraselene_memory_core::imports::{
    self, parse_input, preview, scan_imports, write_managed_copies, ImportPackage, ImportSession,
};
use paraselene_memory_core::Database;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let zip_path = PathBuf::from(args.next().ok_or("用法: import_chatgpt_export <zip路径> <工作目录>")?);
    let work = PathBuf::from(args.next().ok_or("用法: import_chatgpt_export <zip路径> <工作目录>")?);
    let managed_root = work.join("imports");

    let db = Database::open(&work.join("index.db"))?;
    let t_start = std::time::Instant::now();

    // ---- 阶段一：逐文件解析（预览语义：不写库），聚合成一个包 ----
    let file = std::fs::File::open(&zip_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut sessions: Vec<ImportSession> = Vec::new();
    let mut warnings_all: Vec<String> = Vec::new();
    let mut files_md = 0usize;
    let mut files_other = 0usize;
    let mut files_failed = 0usize;
    let mut detected: Option<String> = None;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        if entry.is_dir() || !entry.name().ends_with(".md") {
            files_other += 1;
            continue;
        }
        let mut text = String::new();
        entry.read_to_string(&mut text)?;
        files_md += 1;
        // 日期兜底：zip 条目 mtime（导出时间；导出本身没有对话日期）
        let fallback = entry.last_modified().and_then(|dt| {
            chrono::NaiveDate::from_ymd_opt(dt.year() as i32, dt.month() as u32, dt.day() as u32)
                .and_then(|d| d.and_hms_opt(dt.hour() as u32, dt.minute() as u32, dt.second() as u32))
                .map(|n| n.and_utc().to_rfc3339())
        });
        match parse_input("chatgpt", &text, fallback.as_deref()) {
            Ok((package, warnings, format)) => {
                detected.get_or_insert(format.label().to_string());
                warnings_all.extend(warnings);
                sessions.extend(package.sessions);
            }
            Err(e) => {
                files_failed += 1;
                warnings_all.push(format!("第 {files_md} 个 .md 解析失败: {}", e.user_message()));
            }
        }
    }

    let messages_total: usize = sessions.iter().map(|s| s.messages.len()).sum();
    let package = ImportPackage { schema_version: 1, sessions };

    // 预览接口冒烟（真实产品里此时展示给用户确认；token 仅本地状态标识）
    let pv = preview(&package, warnings_all.clone(), uuid::Uuid::new_v4().to_string(), imports::ImportFormat::ChatGPTMarkdown);
    println!("== 预览（不写库）==");
    println!("detected_format: {}", pv.detected_format);
    println!("md 文件: {files_md}（跳过非 .md: {files_other}，解析失败: {files_failed}）");
    println!("会话: {}，消息: {messages_total}，预览告警: {}", pv.sessions.len(), pv.failed);

    // ---- 阶段二：确认（写托管副本 + 扫描入库）----
    let t_write = std::time::Instant::now();
    let written = write_managed_copies(&managed_root, &package)?;
    let scan = scan_imports(&db, &managed_root)?;
    let write_elapsed = t_write.elapsed();

    println!("== 确认（写托管副本 + 入库）==");
    println!("写入: 新增 {}，重复 {}，失败 {}", written.success, written.duplicates, written.failed);
    println!("入库: 新索引 {}，跳过(未变化) {}，冲突 {}，失败 {}，消息 {}",
        scan.indexed, scan.skipped_unchanged, scan.conflicts, scan.failed, scan.messages);
    println!("确认阶段耗时: {} ms", write_elapsed.as_millis());

    // ---- 阶段三：重复导入验证（同一 zip 再来一遍）----
    let again = write_managed_copies(&managed_root, &package)?;
    let rescan = scan_imports(&db, &managed_root)?;
    println!("== 重复导入（同一 zip 第二遍）==");
    println!("写入: 新增 {}，重复 {}（应全部判重），失败 {}", again.success, again.duplicates, again.failed);
    println!("入库: 新索引 {}（应为 0），跳过(未变化) {}（应等于会话数）",
        rescan.indexed, rescan.skipped_unchanged);

    // ---- 汇总（计数级）----
    let stats = db.stats()?;
    let index_bytes = std::fs::metadata(db.path()).map(|m| m.len()).unwrap_or(0);
    let wal_bytes = std::fs::metadata(db.path().with_extension("db-wal")).map(|m| m.len()).unwrap_or(0);
    println!("== 汇总 ==");
    println!("库内会话: {}，库内消息: {}，项目数: {}", stats.sessions, stats.messages, stats.projects);
    println!("索引体积: {} bytes（WAL: {} bytes）", index_bytes, wal_bytes);
    println!("总耗时: {} ms", t_start.elapsed().as_millis());
    println!("告警 {} 条（只含结构原因）", warnings_all.len());
    for w in warnings_all.iter().take(5) {
        println!("  - {w}");
    }
    Ok(())
}
