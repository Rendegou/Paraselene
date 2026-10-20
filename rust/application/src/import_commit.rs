//! Transactional SQLite import; no managed-path scans or implicit native sources.
//!
//! 导入在单个核心事务内写入源文本（按 BLAKE3 键）、会话、消息与完整规范化包；
//! 任一写入失败整体回滚，不残留部分导入。
use crate::{core_error, AppError};
use paraselene_memory_core::{Database, ImportPackage, ImportSession};
use rusqlite::{params, Transaction};

/// 在单个事务内写源文本、会话、消息与完整规范化包；返回导入会话数，任一失败回滚全部。
pub(crate) fn commit(
    db: &Database,
    package: &ImportPackage,
    source_text: &str,
) -> Result<u32, AppError> {
    db.with_tx(|tx| {
        // 源文本按 BLAKE3 键去重：同一文本重复导入时复用已有 settings 行，避免重复保存大文本。
        let source_key = format!(
            "flutter_import_source:{}",
            blake3::hash(source_text.as_bytes()).to_hex()
        );
        tx.execute(
            "INSERT INTO settings(key,value) VALUES(?1,?2) ON CONFLICT(key) DO NOTHING",
            params![source_key, source_text],
        )?;
        for session in &package.sessions {
            insert_session(tx, session, &source_key)?;
        }
        // Retain the complete normalized source, including any text exceeding
        // the legacy search prefix budget. No external copy is needed to restore.
        let json = serde_json::to_string(package)?;
        let key = format!(
            "flutter_import_package:{}",
            blake3::hash(json.as_bytes()).to_hex()
        );
        tx.execute(
            "INSERT INTO settings(key,value) VALUES(?1,?2)",
            params![key, json],
        )?;
        Ok(package.sessions.len() as u32)
    })
    .map_err(core_error)
}

fn insert_session(
    tx: &Transaction<'_>,
    session: &ImportSession,
    source_key: &str,
) -> paraselene_memory_core::Result<()> {
    let external = session
        .external_id
        .as_deref()
        .ok_or_else(|| paraselene_memory_core::Error::parse("invalid_import"))?;
    let id = format!("{}/{}", session.source.as_str(), external);
    let raw = serde_json::to_string(session)?;
    let hash = blake3::hash(raw.as_bytes()).to_hex().to_string();
    let metadata = serde_json::json!({"imported":true,"sourceKey":source_key,"importSchemaVersion":1,"dateInferred":session.date_inferred,"managedBy":"flutter-synthetic-v1"}).to_string();
    tx.execute("INSERT INTO sessions(id,source,external_session_id,title,created_at,updated_at,content_hash,message_count,partial,metadata,indexed_at)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)", params![id,session.source.as_str(),external,session.title,session.created_at,session.updated_at,
        hash,session.messages.len() as i64,paraselene_memory_core::imports::partial(session),metadata,chrono::Utc::now().to_rfc3339()])?;
    for (index, message) in session.messages.iter().enumerate() {
        let raw = serde_json::json!({"attachments":message.attachments}).to_string();
        tx.execute("INSERT INTO messages(id,session_id,role,kind,text,tool_name,timestamp,sequence,raw) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)",
            params![format!("{id}:{index}"),id,message.role,message.kind,message.text,message.tool_name,message.timestamp,index as i64,raw])?;
    }
    Ok(())
}
