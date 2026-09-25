//! 真实本机数据实测（T01 补充片验收）：Codex / Kimi 适配器 detect → scan → parse。
//!
//! 隐私红线（AGENTS.md §4）：
//! - 只读不写源目录；不打印任何对话正文 / 会话标题 / 会话文件名；
//!   输出只含计数、耗时、错误分类（失败用序号 + 错误类别标识，不含路径）。
//! - 凭据类路径（auth.json / credentials/ 等）由 paths::is_forbidden_path 硬拦截。
//!
//! 用法：
//!   cargo run --example scan_native -- <工作目录> [--codex-root <路径>] [--kimi-root <路径>]
//! 工作目录下生成 index.db（可删除的索引缓存）。重复运行可观察增量跳过。

use std::path::PathBuf;
use std::time::Instant;

use paraselene_memory_core::adapters::{CodexAdapter, ConversationAdapter, KimiAdapter};
use paraselene_memory_core::scanner::{scan_adapter, ScanReport};
use paraselene_memory_core::Database;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let work = PathBuf::from(args.next().ok_or("用法: scan_native <工作目录> [--codex-root P] [--kimi-root P]")?);
    let mut codex_root: Option<PathBuf> = None;
    let mut kimi_root: Option<PathBuf> = None;
    let rest: Vec<String> = args.collect();
    let mut i = 0;
    while i < rest.len() {
        match rest[i].as_str() {
            "--codex-root" => {
                codex_root = rest.get(i + 1).map(PathBuf::from);
                i += 2;
            }
            "--kimi-root" => {
                kimi_root = rest.get(i + 1).map(PathBuf::from);
                i += 2;
            }
            other => return Err(format!("未知参数: {other}").into()),
        }
    }

    let db = Database::open(&work.join("index.db"))?;
    let t_all = Instant::now();

    let adapters: Vec<(&str, Box<dyn ConversationAdapter>, Option<PathBuf>)> = vec![
        ("codex", Box::new(CodexAdapter::new()), codex_root),
        ("kimi", Box::new(KimiAdapter::new()), kimi_root),
    ];

    for (name, adapter, manual) in adapters {
        println!("== {name} ==");
        // ---- detect ----
        let detections = adapter.detect(manual.as_deref());
        for d in &detections {
            println!(
                "detect: found={} session_hint={} manual={} notes={}",
                d.found,
                d.session_hint,
                d.manual,
                d.notes.len()
            );
            if !d.found {
                println!("detect: 未找到数据目录，按约定跳过（不算失败）");
            }
        }
        if detections.iter().all(|d| !d.found) {
            continue;
        }

        // ---- scan + parse（指纹门控入库）----
        let t0 = Instant::now();
        let report: ScanReport = scan_adapter(&db, adapter.as_ref(), manual.as_deref())?;
        let elapsed = t0.elapsed();
        println!(
            "scan: 发现 {} 会话；入库 {}（其中 0 消息 {}），跳过 {}，失败 {}",
            report.scanned, report.parsed, report.empty, report.skipped, report.failed
        );
        println!("parse: 消息 {} 条，耗时 {} ms", report.messages, elapsed.as_millis());
        // 失败分类（只报序号 + 类别，不含路径与正文）
        if !report.failures.is_empty() {
            let mut by_kind: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
            for (_, kind) in &report.failures {
                *by_kind.entry(kind.as_str().to_string()).or_insert(0) += 1;
            }
            for (i, (_, kind)) in report.failures.iter().enumerate() {
                println!("  fail#{} kind={}", i + 1, kind.as_str());
            }
            println!("  失败分类汇总: {by_kind:?}");
        }
    }

    let stats = db.stats()?;
    let index_bytes = std::fs::metadata(db.path()).map(|m| m.len()).unwrap_or(0);
    println!("== 汇总 ==");
    println!("库内会话: {}，库内消息: {}，索引体积: {} bytes", stats.sessions, stats.messages, index_bytes);
    println!("总耗时: {} ms", t_all.elapsed().as_millis());
    Ok(())
}
