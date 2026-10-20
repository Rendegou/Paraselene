//! Fixed-endpoint transport; transient task ownership is revoked on every exit.
//!
//! 传输只使用固定官方端点与 120 秒超时；Flight 的 Drop 在调用方抛弃 future 时也撤销任务所有权，
//! 清理失败只输出稳定错误码，不输出提示词、正文或凭据。
use crate::{
    err,
    reviewed_tasks::{Pending, Running},
    AppError, Session,
};
use paraselene_llm_core as llm;
use std::time::Duration;

/// 输出语言白名单；未知值返回 invalid_output_language。
pub(crate) fn language(value: &str) -> Result<&'static str, AppError> {
    match value {
        "preserve" => Ok("Preserve the language of the confirmed chapter. Do not translate quoted source text."),
        "zh-Hans" => Ok("Write the requested output in Simplified Chinese. Do not translate quoted source text."),
        "en" => Ok("Write the requested output in English. Do not translate quoted source text."),
        _ => Err(err("invalid_output_language")),
    }
}
/// 用固定模型名重新组装请求；失败返回 preview_failed。
pub(crate) fn assemble(prepared: llm::PreparedChat) -> Result<llm::PreparedChat, AppError> {
    llm::assemble_chat(
        &llm::AllowAll,
        llm::ChatRequest {
            space: prepared.space,
            messages: prepared.messages,
            model: Some(prepared.model),
            max_tokens: prepared.max_tokens,
            temperature: prepared.temperature,
            tools: None,
        },
        "deepseek-flash",
    )
    .map_err(|_| err("preview_failed"))
}
struct Flight {
    session: Session,
    work: String,
    id: String,
}
// 调用方抛弃 future 时同样撤销任务所有权，清理失败只输出稳定错误码。
impl Drop for Flight {
    fn drop(&mut self) {
        if let Err(error) = self
            .session
            .cancel_reviewed_task(self.work.clone(), self.id.clone())
        {
            if error.code != "session_closed" {
                eprintln!("task_cleanup_failed:{}", error.code);
            }
        }
    }
}
impl Session {
    /// Consumes an approved full preview once; fixed official endpoint, no retries.
    ///
    /// 未显式确认返回 explicit_confirmation_required；只发固定官方端点，超时 120 秒，不自动重试。
    pub async fn send_reviewed_task(
        &self,
        work: String,
        id: String,
        confirmed: bool,
    ) -> Result<String, AppError> {
        if !confirmed {
            return Err(err("explicit_confirmation_required"));
        }
        let client =
            llm::OpenAiCompatClient::deepseek().map_err(|_| err("transport_unavailable"))?;
        self.run_reviewed_task(
            work,
            id,
            client,
            crate::credentials::read,
            Duration::from_secs(120),
        )
        .await
    }

    ///
    /// 启动任务后竞争取消信号与网络；返回前在同一状态锁内重查运行槽与作用域，失败时回收摘要 claim。
    pub(crate) async fn run_reviewed_task(
        &self,
        work: String,
        id: String,
        client: llm::OpenAiCompatClient,
        read_key: impl FnOnce() -> Result<String, AppError>,
        timeout: Duration,
    ) -> Result<String, AppError> {
        let (task, mut cancel) = self.start_reviewed(&work, &id)?;
        let _flight = Flight {
            session: self.clone(),
            work: work.clone(),
            id: id.clone(),
        };
        let generated = tokio::select! {
            biased;
            _ = cancel.changed() => Err(err("generation_cancelled")),
            result = async {
                let key = read_key()?;
                tokio::time::timeout(timeout, async {
                    let stream = client.send(&task.plan.prepared, &key).await.map_err(|_| err("generation_transport_failed"))?;
                    paraselene_novel_core::collect_complete(stream).await.map_err(|_| err("generation_failed"))
                }).await.map_err(|_| err("generation_timeout"))?
            } => result,
        };
        self.with_state(|state| {
            crate::generation::scope(state, &work, &task.plan.document_id)?;
            if !state
                .tasks
                .running
                .as_ref()
                .is_some_and(|r| r.id == id && r.work == work)
            {
                return Ok(Err(err("generation_cancelled")));
            }
            let result =
                generated.and_then(|body| crate::reviewed_tasks::finish(state, &task, &body));
            let run = state
                .tasks
                .running
                .take()
                .ok_or_else(|| err("task_expired"))?;
            if result.is_err() {
                if let Some(claim) = run.summary {
                    crate::summary_tasks::fail(
                        state.db.as_ref().ok_or_else(|| err("session_closed"))?,
                        &claim,
                    )?;
                }
            }
            Ok(result)
        })?
    }

    fn start_reviewed(
        &self,
        work: &str,
        id: &str,
    ) -> Result<(Pending, tokio::sync::watch::Receiver<bool>), AppError> {
        self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if !crate::generation::enabled(db)? {
                return Err(err("cloud_disabled"));
            }
            if state.tasks.running.is_some() {
                return Err(err("generation_busy"));
            }
            if !state
                .tasks
                .pending
                .as_ref()
                .is_some_and(|p| p.id == id && p.plan.work_id == work)
            {
                return Err(err("preview_expired"));
            }
            let mut task = state
                .tasks
                .pending
                .take()
                .ok_or_else(|| err("preview_expired"))?;
            task.plan.prepared = task.ledger.take(id).ok_or_else(|| err("preview_expired"))?;
            crate::generation::scope(state, work, &task.plan.document_id)?;
            crate::reviewed_tasks::check(db, task.kind, &task.plan)?;
            let summary = if task.kind == crate::reviewed_tasks::Kind::Summary {
                Some(crate::summary_tasks::start(db, &task.plan)?)
            } else {
                None
            };
            let (sender, cancel) = tokio::sync::watch::channel(false);
            state.tasks.running = Some(Running {
                id: id.into(),
                work: work.into(),
                cancel: sender,
                summary,
            });
            Ok((task, cancel))
        })
    }
}
