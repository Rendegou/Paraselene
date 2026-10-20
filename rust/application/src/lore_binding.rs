//! Atomic explicit lore binding to an immutable confirmed manuscript quote.
//!
//! 绑定在单个核心事务内校验作品/文档/版本/词条身份与 UTF-16 边界，并同时写入源锚点与词条关联；
//! from/to 是命名不可变版本中的 UTF-16 码元边界，任一校验失败则不保留任何行。
use crate::{core_error, err, AppError, Session};
use paraselene_memory_core::Error;
use rusqlite::{params, OptionalExtension};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Binding {
    entry_id: String,
    document_id: String,
    version_id: String,
    from: usize,
    to: usize,
    quote: String,
}

impl Session {
    /// `from`/`to` are UTF-16 boundaries in the named immutable version.
    /// Both source and binding are committed together, or neither is retained.
    ///
    /// binding_json 上限 1 MB；版本/文档/词条身份不符返回 source_identity_mismatch，边界或 UTF-16 非法
    /// 返回 invalid_source，引文不符返回 source_quote_mismatch；事务失败不保留锚点。
    pub fn bind_lore_source(&self, work_id: String, binding_json: String) -> Result<(), AppError> {
        if binding_json.len() > 1_000_000 {
            return Err(err("invalid_input"));
        }
        let binding: Binding =
            serde_json::from_str(&binding_json).map_err(|_| err("invalid_input"))?;
        self.with_db(|db| db.with_tx(|tx| {
            let body: Option<String> = tx.query_row(
                "SELECT v.body FROM novel_versions v JOIN novel_documents d ON d.id=v.document_id
                 JOIN lore_entries e ON e.work_id=d.work_id
                 WHERE v.id=?1 AND d.id=?2 AND d.work_id=?3 AND e.id=?4",
                params![binding.version_id, binding.document_id, work_id, binding.entry_id], |r| r.get(0),
            ).optional()?;
            let body = body.ok_or_else(|| Error::parse("source_identity_mismatch"))?;
            // 外部边界是 UTF-16 码元，落库坐标是 Unicode 标量；先验证边界可解码再计数，避免拆分代理对。
            let units: Vec<u16> = body.encode_utf16().collect();
            let prefix = units.get(..binding.from).ok_or_else(|| Error::parse("invalid_source"))?;
            let range = units.get(binding.from..binding.to).ok_or_else(|| Error::parse("invalid_source"))?;
            let prefix = String::from_utf16(prefix).map_err(|_| Error::parse("invalid_source"))?;
            let quote = String::from_utf16(range).map_err(|_| Error::parse("invalid_source"))?;
            if quote.is_empty() || quote != binding.quote { return Err(Error::parse("source_quote_mismatch")); }
            let id = uuid::Uuid::new_v4().to_string();
            let hash = blake3::hash(quote.as_bytes()).to_hex().to_string();
            let start = prefix.chars().count() as i64;
            let end = start + quote.chars().count() as i64;
            tx.execute("INSERT INTO source_anchors(id,work_id,document_id,source_version_id,start_char,end_char,quote_hash,created_at)
                VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",
                params![id, work_id, binding.document_id, binding.version_id, start, end, hash, chrono::Utc::now().to_rfc3339()])?;
            tx.execute("INSERT INTO lore_source_anchors(entry_id,anchor_id) VALUES(?1,?2)", params![binding.entry_id, id])?;
            Ok(())
        }).map_err(core_error))
    }
}
