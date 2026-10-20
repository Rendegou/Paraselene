//! Work-scoped lore and immutable historical sources; no map schema changes.
//!
//! 词条按作品隔离；新建与 CAS 更新要求精确 expected_version，确认必须由作者显式给出。
//! 来源解析在记录的历史版本上按 Unicode 标量区间重建引用并校验 BLAKE3 哈希，绝不使用当前正文。
use crate::{core_error, err, AppError, Session};
use paraselene_memory_core::{Database, LoreKind};
use serde::Deserialize;
use serde_json::json;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LoreEdit {
    id: Option<String>,
    expected_version: Option<i64>,
    kind: String,
    name: String,
    body: String,
    aliases: Vec<String>,
    scope: String,
    confirmed: bool,
}

fn owned(db: &Database, work: &str, entry: &str) -> Result<(), AppError> {
    let entry = db
        .get_lore_entry(entry)
        .map_err(core_error)?
        .ok_or_else(|| err("not_found"))?;
    if entry.work_id != work {
        return Err(err("identity_mismatch"));
    }
    Ok(())
}

impl Session {
    /// Lists all six legacy kinds with their exact head body and explicit status.
    ///
    /// 返回六类词条及其精确 head 正文与显式状态；序列化失败返回 lore_read_failed。
    pub fn list_lore(&self, work_id: String) -> Result<String, AppError> {
        self.with_db(|db| {
            let entries = db.list_lore_entries(&work_id, None).map_err(core_error)?;
            let mut rows = Vec::new();
            for entry in entries {
                let versions = db.list_lore_versions(&entry.id).map_err(core_error)?;
                let head = versions.iter().find(|v| v.version == entry.head_version);
                rows.push(json!({"entry": entry, "head": head}));
            }
            serde_json::to_string(&rows).map_err(|_| err("lore_read_failed"))
        })
    }

    /// Creates or CAS-saves lore. Confirmation is explicit; AI is never auto-confirmed.
    ///
    /// 新建要求 scope=whole 且无 expected_version；更新要求 id 与 expected_version，身份不符返回
    /// identity_mismatch，版本过期返回稳定冲突码。scope=from:章节 时章节必须存在且未归档，否则 invalid_scope。
    /// 输入上限 200000 字节，确认状态完全由作者显式给出。
    pub fn save_lore(&self, work_id: String, edit_json: String) -> Result<String, AppError> {
        if edit_json.len() > 200_000 {
            return Err(err("invalid_input"));
        }
        let edit: LoreEdit = serde_json::from_str(&edit_json).map_err(|_| err("invalid_input"))?;
        self.with_db(|db| {
            if let Some(chapter) = edit.scope.strip_prefix("from:") {
                let document = crate::verify(db, &work_id, chapter)?;
                let live = db
                    .with_conn(|conn| {
                        Ok(conn.query_row(
                            "SELECT archived_at IS NULL FROM novel_documents WHERE id=?1",
                            [chapter],
                            |row| row.get::<_, bool>(0),
                        )?)
                    })
                    .map_err(core_error)?;
                if document.kind != "chapter" || !live {
                    return Err(err("invalid_scope"));
                }
            }
            let entry = if let Some(id) = edit.id {
                owned(db, &work_id, &id)?;
                db.save_lore_entry(
                    &id,
                    edit.expected_version.ok_or_else(|| err("invalid_input"))?,
                    &edit.name,
                    &edit.body,
                    &edit.aliases,
                    &edit.scope,
                    edit.confirmed,
                )
                .map_err(core_error)?
            } else {
                if edit.expected_version.is_some() || edit.scope != "whole" {
                    return Err(err("invalid_input"));
                }
                db.create_lore_entry(
                    &work_id,
                    LoreKind::parse(&edit.kind).map_err(core_error)?,
                    &edit.name,
                    &edit.body,
                    &edit.aliases,
                    edit.confirmed,
                )
                .map_err(core_error)?
            };
            serde_json::to_string(&entry).map_err(|_| err("lore_save_failed"))
        })
    }

    /// Reject only the exact candidate head reviewed by the author.
    ///
    /// 只拒绝 head_version 精确匹配的 candidate；不匹配返回 lore_candidate_conflict，跨作品返回 identity_mismatch。
    pub fn reject_lore(
        &self,
        work_id: String,
        entry_id: String,
        expected_version: i64,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            owned(db, &work_id, &entry_id)?;
            db.with_tx(|tx| {
                let changed = tx.execute("UPDATE lore_entries SET status='rejected', updated_at=?4 WHERE id=?1 AND work_id=?2 AND head_version=?3 AND status='candidate'",
                    rusqlite::params![entry_id,work_id,expected_version,chrono::Utc::now().to_rfc3339()])?;
                if changed != 1 { return Err(paraselene_memory_core::Error::parse("lore_candidate_conflict")); }
                Ok(())
            }).map_err(core_error)
        })
    }
    /// Returns every immutable lore version, after ownership validation.
    ///
    /// 先校验作品归属再返回不可变版本列表；序列化失败返回 lore_read_failed。
    pub fn lore_versions(&self, work_id: String, entry_id: String) -> Result<String, AppError> {
        self.with_db(|db| {
            owned(db, &work_id, &entry_id)?;
            serde_json::to_string(&db.list_lore_versions(&entry_id).map_err(core_error)?)
                .map_err(|_| err("lore_read_failed"))
        })
    }

    /// Resolves coordinates against the recorded historical version, never current text.
    /// Coordinates remain Unicode scalars; original body and quote are exact UTF-8.
    ///
    /// 在记录的历史版本上重建引用并校验 BLAKE3；版本缺失或哈希不符分别返回
    /// source_version_missing/source_hash_mismatch，坐标非法返回 invalid_source。
    pub fn lore_sources(&self, work_id: String, entry_id: String) -> Result<String, AppError> {
        self.with_db(|db| {
            owned(db, &work_id, &entry_id)?;
            let anchors = db
                .list_lore_source_anchors(&work_id, &entry_id)
                .map_err(core_error)?;
            let mut rows = Vec::new();
            for anchor in anchors {
                let document = db
                    .get_novel_document(&anchor.document_id)
                    .map_err(core_error)?
                    .ok_or_else(|| err("source_version_missing"))?;
                if document.work_id != work_id {
                    return Err(err("identity_mismatch"));
                }
                let versions = db
                    .list_novel_versions(&anchor.document_id)
                    .map_err(core_error)?;
                let version = versions
                    .iter()
                    .find(|v| v.id == anchor.source_version_id)
                    .ok_or_else(|| err("source_version_missing"))?;
                let start =
                    usize::try_from(anchor.start_char).map_err(|_| err("invalid_source"))?;
                let end = usize::try_from(anchor.end_char).map_err(|_| err("invalid_source"))?;
                if end < start || end > version.body.chars().count() {
                    return Err(err("invalid_source"));
                }
                let quote: String = version.body.chars().skip(start).take(end - start).collect();
                if blake3::hash(quote.as_bytes()).to_hex().as_str() != anchor.quote_hash {
                    return Err(err("source_hash_mismatch"));
                }
                rows.push(json!({"anchor": anchor, "body": version.body, "quote": quote}));
            }
            serde_json::to_string(&rows).map_err(|_| err("lore_read_failed"))
        })
    }
}
