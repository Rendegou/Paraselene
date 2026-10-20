//! A dropped bridge future must release its durable operation and thread slot.
//!
//! GenerationFlight 的 Drop 在 bridge future 被抛弃时尽力取消持久化操作并释放线程槽；
//! 清理失败只输出稳定错误码，绝不输出提示词、正文或凭据。
use crate::{core_error, err, AppError, Session, State};

/// Cancels the active chapter before dropping its in-memory tickets and runs.
///
/// 只在已持有状态锁时调用；先转移生成器与任务槽，确保数据库错误也无法留下付费请求。
pub(crate) fn cancel_active(state: &mut State) -> Result<(), AppError> {
    // Move senders out first. Even a failed DB query/write drops every sender
    // on return, so a storage failure cannot keep a paid HTTP request running.
    let mut generation = std::mem::take(&mut state.generation);
    let tasks = std::mem::take(&mut state.tasks);
    let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
    if let Some(run) = tasks.running {
        run.cancel.send_replace(true);
        if let Some(claim) = run.summary {
            crate::summary_tasks::fail(db, &claim)?;
        }
    }
    if let Some((work, chapter)) = &state.generation_scope {
        for operation in db
            .list_novel_operations(work, chapter)
            .map_err(core_error)?
        {
            if generation.is_running(work, &operation.operation_id) {
                generation.cancel(work, &operation.operation_id);
                db.finish_novel_operation(work, &operation.operation_id, "cancelled", None)
                    .map_err(core_error)?;
            }
        }
    }
    Ok(())
}

pub(crate) struct GenerationFlight {
    pub session: Session,
    pub work: String,
    pub operation: String,
}

impl Drop for GenerationFlight {
    fn drop(&mut self) {
        // Normal completion/cancellation already removed the slot. Abandonment
        // still goes through the same durable barrier; no candidate is retained.
        if let Err(error) = self
            .session
            .cancel_generation(self.work.clone(), self.operation.clone())
        {
            // Drop cannot return an error. The durable barrier poisons failed
            // sessions; emit only its stable code, never prompt/body/credential.
            if error.code != "session_closed" {
                eprintln!("generation_cleanup_failed:{}", error.code);
            }
        }
    }
}
