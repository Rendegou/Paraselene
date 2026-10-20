//! Old ideas are derived only from explicitly imported user messages.
//!
//! 旧想法只从显式导入的会话消息派生；候选读取不创建记忆、不发送材料，确认、状态迁移与转换
//! 都要求目标存在且当前状态匹配，转换保留来源与空间身份。
use crate::{core_error, err, AppError, Session};
impl Session {
    /// Full selected UTF-8 source before Markdown parsing; no filesystem lookup.
    ///
    /// 读取 settings 中的完整导入源文本；只接受 flutter_import_source: 前缀，缺失返回 source_unavailable。
    pub fn imported_original(&self, session: String) -> Result<String, AppError> {
        self.with_db(|db| {
            db.with_conn(|conn| {
                let metadata: String = conn.query_row(
                    "SELECT metadata FROM sessions WHERE id=?1",
                    [&session],
                    |row| row.get(0),
                )?;
                let metadata: serde_json::Value = serde_json::from_str(&metadata)?;
                let key = metadata["sourceKey"]
                    .as_str()
                    .ok_or_else(|| paraselene_memory_core::Error::parse("source_unavailable"))?;
                if !key.starts_with("flutter_import_source:") {
                    return Err(paraselene_memory_core::Error::parse("source_unavailable"));
                }
                conn.query_row("SELECT value FROM settings WHERE key=?1", [key], |row| {
                    row.get(0)
                })
                .map_err(Into::into)
            })
            .map_err(core_error)
        })
    }
    /// Reads a candidate without creating a memory or sending any material.
    ///
    /// 只读候选 JSON，不创建记忆、不发材料；读取失败返回 idea_read_failed。
    pub fn idea_candidate(&self, skip: u32) -> Result<String, AppError> {
        self.with_db(|db| {
            serde_json::to_string(&db.suggest_old_idea(skip).map_err(core_error)?)
                .map_err(|_| err("idea_read_failed"))
        })
    }
    /// Explicit user confirmation binds the exact user-message source.
    ///
    /// 显式确认并把状态置为 liked；状态或来源不合法时返回稳定映射码。
    pub fn confirm_idea(
        &self,
        session: String,
        sequence: i64,
        title: String,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            db.confirm_idea(&session, sequence, &title, "liked")
                .map(|_| ())
                .map_err(core_error)
        })
    }
    /// Existing status is required; invalid or stale transitions do not change it.
    ///
    /// 当前状态必须等于 expected 才迁移到 next；状态不符返回稳定码，不部分更新。
    pub fn idea_status(&self, id: String, expected: String, next: String) -> Result<(), AppError> {
        self.with_db(|db| {
            db.confirm_idea_status(&id, &expected, &next)
                .map(|_| ())
                .map_err(core_error)
        })
    }
    /// Explicit conversion preserves the source and never changes the idea's space.
    ///
    /// 转换保留来源与思想空间身份；目标非法或状态不允许时返回稳定错误码。
    pub fn convert_idea(&self, id: String, target: String) -> Result<String, AppError> {
        self.with_db(|db| {
            serde_json::to_string(&db.convert_idea(&id, &target).map_err(core_error)?)
                .map_err(|_| err("idea_convert_failed"))
        })
    }
    /// Only confirmed imported data, never a filesystem lookup.
    ///
    /// 只读已导入会话消息，不访问文件系统；读取失败返回 source_read_failed。
    pub fn imported_source(&self, session: String, sequence: i64) -> Result<String, AppError> {
        self.with_db(|db| {
            serde_json::to_string(
                &db.messages_around(&session, sequence, 0, 0)
                    .map_err(core_error)?,
            )
            .map_err(|_| err("source_read_failed"))
        })
    }
}
