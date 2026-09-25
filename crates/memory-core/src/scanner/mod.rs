//! 扫描层：文件指纹、增量判定、适配器扫描编排。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/scanner/mod.rs
//! 移植改动：
//! - 只保留 fingerprint（直接拷贝）与 [`scan_adapter`] 编排（源项目的完整扫描器
//!   带进度回调 / batch_limit / 设置开关 / 同步状态机，按单机裁剪原则简化）；
//! - watcher（notify 监听）后续再评估，不在本片范围。

pub mod fingerprint;

pub use fingerprint::{decide, hash_bytes, hash_file, quick_stat, Decision};

use std::path::Path;

use crate::adapters::ConversationAdapter;
use crate::error::Result;
use crate::model::SessionDescriptor;
use crate::storage::db::{Database, FingerprintRow};
use crate::storage::sessions::DatabaseSink;
use crate::storage::types::SessionStub;

/// 扫描报告（计数级，不含正文）。
#[derive(Debug, Default, Clone)]
pub struct ScanReport {
    /// 扫描到的会话描述符总数
    pub scanned: usize,
    /// 本次新解析入库的会话数
    pub parsed: usize,
    /// 指纹判定未变化（跳过解析）
    pub skipped: usize,
    /// 解析或写库失败的会话数
    pub failed: usize,
    /// 解析成功但 0 消息的会话数（如空的 rollout 文件）
    pub empty: usize,
    /// 入库消息总数
    pub messages: u64,
    /// 结构化失败清单（(会话 external_id, 错误分类)），供上层做失败分类统计
    pub failures: Vec<(String, crate::error::ErrorKind)>,
    /// 告警（只含结构原因，不含正文）
    pub warnings: Vec<String>,
}

/// 把一个适配器发现的会话全部扫入索引（指纹门控：内容变了才重解析）。
///
/// 流程与源项目 scanner 一致：指纹判定 → 冲突检查 → 占位 → 清旧消息 →
/// 流式解析写库 → 会话元数据 → 落指纹（主文件带内容哈希，附属文件只记 size+mtime）。
/// 单个会话失败只计入报告，不影响其他会话。
pub fn scan_adapter(
    db: &Database,
    adapter: &dyn ConversationAdapter,
    manual_root: Option<&Path>,
) -> Result<ScanReport> {
    let mut report = ScanReport::default();
    let descriptors = adapter.scan(manual_root)?;
    report.scanned = descriptors.len();

    // 一次扫描只查一次指纹（避免 N+1）
    let paths: Vec<String> = descriptors
        .iter()
        .map(|d| crate::error::display_path(&d.primary_file))
        .collect();
    let fingerprints = db.fingerprints_by_paths(&paths)?;

    for descriptor in descriptors {
        match scan_one(db, adapter, &descriptor, &fingerprints, &mut report) {
            Ok(()) => {}
            Err(e) => {
                report.failed += 1;
                report.failures.push((descriptor.external_id.clone(), e.kind()));
                report.warnings.push(format!(
                    "{}: {}",
                    descriptor.external_id,
                    e.user_message()
                ));
            }
        }
    }
    db.checkpoint()?;
    Ok(report)
}

fn scan_one(
    db: &Database,
    adapter: &dyn ConversationAdapter,
    descriptor: &SessionDescriptor,
    fingerprints: &std::collections::HashMap<String, FingerprintRow>,
    report: &mut ScanReport,
) -> Result<()> {
    let session_id = descriptor.session_id();
    let primary_path = crate::error::display_path(&descriptor.primary_file);

    // 指纹门控：先比 size+mtime，变了才算 BLAKE3
    let (decision, content_hash) = fingerprint::decide(&descriptor.primary_file, fingerprints.get(&primary_path))?;
    match decision {
        Decision::Unchanged => {
            report.skipped += 1;
            return Ok(());
        }
        Decision::SameContent => {
            if let Some((size, mtime)) = fingerprint::quick_stat(&descriptor.primary_file) {
                db.touch_fingerprint(&primary_path, size, mtime, content_hash.as_deref())?;
            }
            report.skipped += 1;
            return Ok(());
        }
        Decision::Changed => {}
    }

    // 主键冲突：同 ID 会话已由其他主文件索引（如导入副本），保留已有记录
    if let Some(existing) = db.get_session(&session_id)? {
        if existing.primary_file.as_deref() != Some(primary_path.as_str()) {
            report.warnings.push(format!(
                "会话 {session_id} 已存在且主文件不同，保留已有记录"
            ));
            report.skipped += 1;
            return Ok(());
        }
    }

    db.upsert_session_stub(&SessionStub {
        id: session_id.clone(),
        source: descriptor.source.as_str().to_string(),
        external_id: descriptor.external_id.clone(),
        source_root: Some(crate::error::display_path(&descriptor.session_dir)),
        primary_file: Some(primary_path.clone()),
    })?;
    // 全量重解析：先清旧消息（FTS 由触发器同步），再流式写入
    db.clear_messages(&session_id)?;

    let mut sink = DatabaseSink::new(db, &session_id, 512);
    let info = adapter.parse_streaming(descriptor, &mut sink)?;
    sink.flush()?;
    db.finalize_session(&session_id, &info, content_hash.as_deref())?;

    // 解析成功后再落指纹：中途失败下次仍会重试。
    // 主文件带内容哈希；其余文件（state.json / 子 Agent wire 等）只记 size+mtime，
    // 它们不参与增量判定（与源项目一致）。
    let mut rows = vec![FingerprintRow {
        path: primary_path.clone(),
        session_id: session_id.clone(),
        role: "primary".to_string(),
        size: 0,
        mtime: 0,
        hash: content_hash,
    }];
    if let Some((size, mtime)) = fingerprint::quick_stat(&descriptor.primary_file) {
        rows[0].size = size;
        rows[0].mtime = mtime;
    }
    for file in descriptor.files.iter().skip(1) {
        if crate::paths::is_forbidden_path(&file.path) {
            continue;
        }
        let Some((size, mtime)) = fingerprint::quick_stat(&file.path) else {
            continue;
        };
        rows.push(FingerprintRow {
            path: crate::error::display_path(&file.path),
            session_id: session_id.clone(),
            role: file.role.clone(),
            size,
            mtime,
            hash: None,
        });
    }
    db.replace_fingerprints(&session_id, descriptor.source.as_str(), &rows)?;

    report.parsed += 1;
    report.messages += info.message_count;
    if info.message_count == 0 {
        report.empty += 1;
    }
    Ok(())
}
