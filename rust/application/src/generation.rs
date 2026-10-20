//! One-time reviewed official DeepSeek requests. No retries or startup network.
//!
//! 生成分两阶段：prepare 只组装完整消息并签发五分钟一次性预览票据，不读凭据、不发请求；
//! send 需要显式 confirmed=true 且只发往固定官方端点。同一工作区的生成槽由内存状态串行化，
//! 导航、取消、超时与传输失败均落为稳定错误码，迟到的结果不能保存候选。
use crate::{core_error, err, verify, AppError, Session};
use paraselene_llm_core as llm;
use paraselene_novel_core as novel;
const CLOUD_SETTING: &str = "flutter_cloud_novel_v1";

pub(crate) fn enabled(db: &paraselene_memory_core::Database) -> Result<bool, AppError> {
    Ok(db
        .get_setting(CLOUD_SETTING)
        .map_err(core_error)?
        .as_deref()
        == Some("true"))
}
pub(crate) fn scope(state: &crate::State, work: &str, chapter: &str) -> Result<(), AppError> {
    if state
        .generation_scope
        .as_ref()
        .is_some_and(|(w, c)| w == work && c == chapter)
    {
        Ok(())
    } else {
        Err(err("generation_scope_changed"))
    }
}

impl Session {
    /// Default is disabled. Explicit opt-in does not itself read keys or send.
    ///
    /// 关闭时立即取消活动生成；默认关闭，开启本身不读密钥也不发请求。
    pub fn set_cloud_enabled(&self, value: bool) -> Result<(), AppError> {
        self.with_state(|state| {
            if !value {
                crate::generation_lifecycle::cancel_active(state)?;
            }
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            db.set_setting(CLOUD_SETTING, if value { "true" } else { "false" })
                .map_err(core_error)?;
            Ok(())
        })
    }

    /// Chapter/work navigation drops all old previews and active HTTP futures.
    ///
    /// 作品与章节必须成对给出或同时清空，否则 invalid_input；切换作用域会取消旧章节的预览与在途请求。
    pub fn activate_generation_scope(
        &self,
        work: Option<String>,
        chapter: Option<String>,
    ) -> Result<(), AppError> {
        self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            let next = match (work, chapter) {
                (Some(w), Some(c)) => {
                    verify(db, &w, &c)?;
                    Some((w, c))
                }
                (_, None) => None,
                _ => return Err(err("invalid_input")),
            };
            if state.generation_scope == next {
                return Ok(());
            }
            crate::generation_lifecycle::cancel_active(state)?;
            state.generation_scope = next;
            Ok(())
        })
    }

    /// Assembles the exact full message preview and five-minute one-use ticket.
    /// This stage performs no credential access and no network request.
    ///
    /// 请求上限 2 MB，仅接受 preserve/zh-Hans/en 输出语言；云端关闭返回 cloud_disabled，
    /// 已有预览票据返回 generation_busy。本阶段不读凭据、不发网络请求。
    pub fn prepare_generation(&self, request_json: String) -> Result<String, AppError> {
        if request_json.len() > 2_000_000 {
            return Err(err("invalid_input"));
        }
        let value: serde_json::Value =
            serde_json::from_str(&request_json).map_err(|_| err("invalid_input"))?;
        let instruction = match value
            .get("outputLanguage")
            .and_then(|value| value.as_str())
            .unwrap_or("preserve")
        {
            "preserve" => "Preserve the language of the selected manuscript text.",
            "zh-Hans" => "Write the replacement manuscript text in Simplified Chinese.",
            "en" => "Write the replacement manuscript text in English.",
            _ => return Err(err("invalid_output_language")),
        };
        let request: novel::WorkingEditRequest =
            serde_json::from_str(&request_json).map_err(|_| err("invalid_input"))?;
        self.with_state(|state| {
            scope(state, &request.work_id, &request.document_id)?;
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if !enabled(db)? {
                return Err(err("cloud_disabled"));
            }
            let mut plan = novel::prepare_working_edit(db, &llm::AllowAll, request)
                .map_err(|_| err("generation_context_conflict"))?;
            plan.prepared
                .messages
                .push(llm::Message::system(instruction));
            plan.prepared = llm::assemble_chat(
                &llm::AllowAll,
                llm::ChatRequest {
                    space: plan.prepared.space,
                    messages: plan.prepared.messages,
                    model: Some(plan.prepared.model),
                    max_tokens: plan.prepared.max_tokens,
                    temperature: plan.prepared.temperature,
                    tools: plan.prepared.tools,
                },
                "deepseek-flash",
            )
            .map_err(|_| err("preview_failed"))?;
            let preview = state
                .generation
                .issue(plan)
                .map_err(|_| err("generation_busy"))?;
            serde_json::to_string(&preview).map_err(|_| err("preview_failed"))
        })
    }

    /// Sends only to the fixed official endpoint, after explicit material/fee approval.
    /// Cancellation drops the HTTP future; a late result cannot save a candidate.
    ///
    /// 未显式确认返回 explicit_confirmation_required；只发固定官方端点，超时 120 秒，
    /// 成功后只写入候选，不自动确认正文。
    pub async fn send_generation(
        &self,
        work: String,
        preview_id: String,
        confirmed: bool,
    ) -> Result<(), AppError> {
        if !confirmed {
            return Err(err("explicit_confirmation_required"));
        }
        let client =
            llm::OpenAiCompatClient::deepseek().map_err(|_| err("transport_unavailable"))?;
        self.run_generation(work, preview_id, client, crate::credentials::read)
            .await
    }

    pub(crate) async fn run_generation(
        &self,
        work: String,
        preview_id: String,
        client: llm::OpenAiCompatClient,
        read_key: impl FnOnce() -> Result<String, AppError>,
    ) -> Result<(), AppError> {
        self.run_generation_with_timeout(
            work,
            preview_id,
            client,
            read_key,
            std::time::Duration::from_secs(120),
        )
        .await
    }

    pub(crate) async fn run_generation_with_timeout(
        &self,
        work: String,
        preview_id: String,
        client: llm::OpenAiCompatClient,
        read_key: impl FnOnce() -> Result<String, AppError>,
        timeout: std::time::Duration,
    ) -> Result<(), AppError> {
        let (run, operation) = self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if !enabled(db)? {
                return Err(err("cloud_disabled"));
            }
            let run = state
                .generation
                .take(&work, &preview_id)
                .map_err(|_| err("preview_expired"))?;
            scope(state, &work, &run.plan.request.document_id)?;
            match novel::start_working_generation(db, &run.plan) {
                Ok(operation) => Ok((run, operation)),
                Err(_) => {
                    state
                        .generation
                        .cancel(&work, &run.plan.request.operation_id);
                    Err(err("generation_context_conflict"))
                }
            }
        })?;
        // 取消令牌与网络 future 竞争：取消时丢弃 HTTP future，迟到的响应不会进入保存路径。
        let _flight = crate::generation_lifecycle::GenerationFlight {
            session: self.clone(),
            work: work.clone(),
            operation: operation.operation_id.clone(),
        };
        let generated = novel::collect_cancellable(run.cancel, async {
            let key = read_key().map_err(|_| "credential_unavailable".to_string())?;
            tokio::time::timeout(timeout, async {
                let stream = client
                    .send(&run.plan.prepared, &key)
                    .await
                    .map_err(|_| "generation_transport_failed".to_string())?;
                novel::collect_complete(stream).await
            })
            .await
            .map_err(|_| "generation_timeout".to_string())?
        })
        .await;
        self.with_state(|state| {
            scope(state, &work, &run.plan.request.document_id)?;
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if !state.generation.is_running(&work, &operation.operation_id) {
                return Ok(Err(err("generation_cancelled")));
            }
            // 收尾在同一把状态锁内重查作用域、运行槽与取消状态，避免与取消动作竞态。
            let result =
                state
                    .generation
                    .finish(&work, &operation.operation_id, || match generated {
                        Ok(body) => {
                            novel::complete_working_generation(db, &operation, &run.plan, &body)
                                .map(|_| ())
                        }
                        Err(_) => Err("generation_failed".into()),
                    });
            if result.is_err() {
                db.finish_novel_operation(
                    &work,
                    &operation.operation_id,
                    "failed",
                    Some("generation_failed"),
                )
                .map_err(core_error)?;
            }
            // A persisted terminal failure is a successful transaction. Return
            // its user-facing error only after the durable barrier publishes it.
            Ok(result.map_err(|_| err("generation_failed")))
        })?
    }

    /// Cancellation is explicit and idempotent; completion and cancellation serialize.
    ///
    /// 幂等；同时取消内存票据与运行槽，并把持久化操作置为 cancelled。
    pub fn cancel_generation(&self, work: String, operation_id: String) -> Result<(), AppError> {
        self.with_state(|state| {
            let cancelled = state.generation.cancel(&work, &operation_id);
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if cancelled
                && db
                    .get_novel_operation(&work, &operation_id)
                    .map_err(core_error)?
                    .is_some()
            {
                db.finish_novel_operation(&work, &operation_id, "cancelled", None)
                    .map_err(core_error)?;
            }
            Ok(())
        })
    }
}
