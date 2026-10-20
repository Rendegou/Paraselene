//! Explicit text import. Only the UI-selected bytes are parsed; never scan paths.
//!
//! 预览只在内存保留至多 4 个五分钟后过期的包，不写库、不触网；确认消费同一份原生持有的
//! 规范化包并在一个事务内提交，调用方无法替换预览内容。
use crate::{core_error, err, AppError, Session};
use paraselene_memory_core::ImportPackage;
use std::time::{Duration, Instant};
/// 预览期间原生保留的规范化包与源文本；确认或过期后从内存移除。
pub(crate) struct PendingImport {
    pub package: ImportPackage,
    pub source_text: String,
    pub issued: Instant,
}
impl Session {
    /// Bounded five-minute preview. No writes/network; confirmation consumes
    /// the same native-held normalized package, never a frontend replacement.
    ///
    /// 最多保留 4 个预览，超出返回 import_preview_limit；不写库、不发网络。
    pub fn preview_import(&self, source: String, text: String) -> Result<String, AppError> {
        let (package, warnings, format) =
            paraselene_memory_core::parse_input(&source, &text, None).map_err(core_error)?;
        self.with_state(|state| {
            state
                .imports
                // 清理过期预览与数量上限在同一把状态锁内完成，并发预览不会超过上限。
                .retain(|_, pending| pending.issued.elapsed() < Duration::from_secs(300));
            if state.imports.len() >= 4 {
                return Err(err("import_preview_limit"));
            }
            let token = uuid::Uuid::new_v4().to_string();
            let preview =
                paraselene_memory_core::preview(&package, warnings, token.clone(), format);
            let json = serde_json::to_string(&preview).map_err(|_| err("import_preview_failed"))?;
            state.imports.insert(
                token,
                PendingImport {
                    package,
                    source_text: text,
                    issued: Instant::now(),
                },
            );
            Ok(json)
        })
    }
    /// Drops an unused native preview without creating any imported records.
    ///
    /// 幂等删除内存预览，不产生任何导入记录。
    pub fn cancel_import(&self, token: String) -> Result<(), AppError> {
        self.with_state(|state| {
            state.imports.remove(&token);
            Ok(())
        })
    }
    /// Explicit one-use confirm. The complete source package and FTS-backed
    /// messages commit atomically in SQLite and are included in full backups.
    ///
    /// 令牌一次性且五分钟有效；缺失或过期返回 import_preview_expired，成功后返回导入会话数。
    pub fn confirm_import(&self, token: String) -> Result<u32, AppError> {
        self.with_state(|state| {
            let pending = state
                .imports
                .remove(&token)
                .ok_or_else(|| err("import_preview_expired"))?;
            if pending.issued.elapsed() >= Duration::from_secs(300) {
                return Err(err("import_preview_expired"));
            }
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            crate::import_commit::commit(db, &pending.package, &pending.source_text)
        })
    }
}
