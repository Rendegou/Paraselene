//! Explicitly approved RPG and summary tasks. One transient task per workspace.
//!
//! 工作区同时最多一个待发预览与一个运行中任务；场景、回应与摘要共享固定语言与端点约束，
//! 模型输出不会直接确认正文。取消会同时清理预览、运行槽与重建队列，调用方抛弃 future 走同一路径。
use crate::{core_error, err, AppError, Session};
use paraselene_llm_core as llm;
use paraselene_novel_core as novel;
use serde::{Deserialize, Serialize};
use tokio::sync::watch;

/// 三类 reviewed 任务：场景、回应与章节摘要。
#[derive(Clone, Copy, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Kind {
    Scene,
    Response,
    Summary,
}
/// 预览请求；text 默认空串，scene_id 仅回应任务使用。
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Request {
    pub work: String,
    pub chapter: String,
    pub kind: Kind,
    #[serde(default)]
    pub text: String,
    pub scene_id: Option<String>,
    pub output_language: String,
}
/// 已签发但未发送的预览：保留计划与一次性票据账本。
pub(crate) struct Pending {
    pub id: String,
    pub kind: Kind,
    pub plan: novel::GenerationPlan,
    pub ledger: llm::PreviewLedger,
}
/// 运行槽；cancel 广播取消，摘要任务另带 claim。
pub(crate) struct Running {
    pub id: String,
    pub work: String,
    pub cancel: watch::Sender<bool>,
    pub summary: Option<crate::summary_tasks::Claim>,
}
/// 最近一次场景结果，回应任务据此校验上下文与 head。
pub(crate) struct Scene {
    pub id: String,
    pub work: String,
    pub chapter: String,
    pub content: novel::RpgSceneContent,
    pub context: Vec<(String, String)>,
    pub head: Option<String>,
}
/// 工作区任务状态：至多一个待发预览、一个运行槽与一个场景。
#[derive(Default)]
pub(crate) struct Tasks {
    pub pending: Option<Pending>,
    pub running: Option<Running>,
    pub scene: Option<Scene>,
}

/// 发送与落库前重新校验 head 和上下文版本；漂移返回 generation_context_conflict。
pub(crate) fn check(
    db: &paraselene_memory_core::Database,
    kind: Kind,
    plan: &novel::GenerationPlan,
) -> Result<(), AppError> {
    let doc = crate::verify(db, &plan.work_id, &plan.document_id)?;
    if doc.head_version_id != plan.base_version_id {
        return Err(err("generation_context_conflict"));
    }
    if kind != Kind::Summary
        && novel::current_context_versions(db, &plan.work_id)
            .map_err(|_| err("generation_context_conflict"))?
            != plan.context_versions
    {
        return Err(err("generation_context_conflict"));
    }
    Ok(())
}

impl Session {
    /// Preview only: no credentials, network, queue claim or model output writes.
    ///
    /// 请求上限 16000 字节；要求云端开启、生成作用域匹配且无运行中任务，否则分别返回
    /// cloud_disabled/generation_scope_changed/generation_busy。本阶段不读凭据、不发请求。
    pub fn prepare_reviewed_task(&self, request_json: String) -> Result<String, AppError> {
        if request_json.len() > 16000 {
            return Err(err("invalid_input"));
        }
        let request: Request =
            serde_json::from_str(&request_json).map_err(|_| err("invalid_input"))?;
        self.with_state(|state| {
            crate::generation::scope(state, &request.work, &request.chapter)?;
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            if !crate::generation::enabled(db)? { return Err(err("cloud_disabled")); }
            if state.tasks.running.is_some() { return Err(err("generation_busy")); }
            crate::verify(db, &request.work, &request.chapter)?;
            let mut plan = prepare(db, &state.tasks, &request)?;
            let language = crate::reviewed_transport::language(&request.output_language)?;
            plan.prepared.messages.push(llm::Message::system(language));
            plan.prepared = crate::reviewed_transport::assemble(plan.prepared)?;
            check(db, request.kind, &plan)?;
            let mut ledger = llm::PreviewLedger::default();
            let preview = ledger.issue(plan.prepared.clone());
            state.tasks.pending = Some(Pending { id: preview.id.clone(), kind: request.kind, plan, ledger });
            Ok(serde_json::json!({"id":preview.id,"kind":request.kind,"prepared":preview.prepared}).to_string())
        })
    }

    /// Cancels a matching preview/run. Dropped futures use this same path.
    ///
    /// 匹配的预览或运行任务会被清理；摘要任务按 claim token 标记失败，其他任务不触碰。
    pub fn cancel_reviewed_task(&self, work: String, id: String) -> Result<(), AppError> {
        self.with_state(|state| {
            if state
                .tasks
                .pending
                .as_ref()
                .is_some_and(|p| p.id == id && p.plan.work_id == work)
            {
                state.tasks.pending = None;
            }
            if state
                .tasks
                .running
                .as_ref()
                .is_some_and(|r| r.id == id && r.work == work)
            {
                let run = state
                    .tasks
                    .running
                    .take()
                    .ok_or_else(|| err("internal_error"))?;
                run.cancel.send_replace(true);
                if let Some(claim) = run.summary {
                    crate::summary_tasks::fail(
                        state.db.as_ref().ok_or_else(|| err("session_closed"))?,
                        &claim,
                    )?;
                }
                // Dropping the sender wakes a waiting transport, including caller abandonment.
            }
            Ok(())
        })
    }
}

fn prepare(
    db: &paraselene_memory_core::Database,
    tasks: &Tasks,
    request: &Request,
) -> Result<novel::GenerationPlan, AppError> {
    match request.kind {
        Kind::Scene => novel::prepare_rpg_scene(
            db,
            &llm::AllowAll,
            &request.chapter,
            &request.text,
            "deepseek-flash",
        )
        .map_err(|_| err("invalid_rpg_request")),
        Kind::Response => {
            // 场景过期或上下文漂移时回应任务必须重新生成场景，不能把旧上下文写进草稿。
            let scene = tasks.scene.as_ref().ok_or_else(|| err("scene_expired"))?;
            if Some(&scene.id) != request.scene_id.as_ref()
                || scene.work != request.work
                || scene.chapter != request.chapter
            {
                return Err(err("scene_expired"));
            }
            let plan = novel::prepare_rpg_response(
                db,
                &llm::AllowAll,
                &request.chapter,
                &scene.content,
                &request.text,
                "deepseek-flash",
            )
            .map_err(|_| err("invalid_rpg_request"))?;
            if plan.context_versions != scene.context || plan.base_version_id != scene.head {
                return Err(err("scene_expired"));
            }
            Ok(plan)
        }
        Kind::Summary => crate::summary_tasks::prepare(db, &request.work, &request.chapter),
    }
}

/// 按任务类型落库：场景只更新内存、回应创建 AI 草稿、摘要提交 rebuild claim；失败返回相应稳定码。
pub(crate) fn finish(
    state: &mut crate::State,
    task: &Pending,
    body: &str,
) -> Result<String, AppError> {
    let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
    check(db, task.kind, &task.plan)?;
    match task.kind {
        Kind::Scene => {
            let content = novel::parse_rpg_scene(body).map_err(|_| err("invalid_rpg_scene"))?;
            let id = uuid::Uuid::new_v4().to_string();
            let result = serde_json::json!({"kind":"scene","id":id,"scene":content});
            state.tasks.scene = Some(Scene {
                id,
                work: task.plan.work_id.clone(),
                chapter: task.plan.document_id.clone(),
                content,
                context: task.plan.context_versions.clone(),
                head: task.plan.base_version_id.clone(),
            });
            Ok(result.to_string())
        }
        Kind::Response => {
            let draft = db
                .create_novel_draft_at_context(
                    &task.plan.document_id,
                    task.plan.base_version_id.as_deref(),
                    &task.plan.context_versions,
                    body,
                    paraselene_memory_core::DraftOrigin::Ai,
                )
                .map_err(core_error)?;
            state.tasks.scene = None;
            Ok(serde_json::json!({"kind":"draft","draft":draft}).to_string())
        }
        Kind::Summary => {
            if body.chars().count() > 4000 || body.trim().is_empty() {
                return Err(err("invalid_summary"));
            }
            let claim = state
                .tasks
                .running
                .as_ref()
                .and_then(|r| r.summary.as_ref())
                .ok_or_else(|| err("task_expired"))?;
            let summary = db
                .finish_rebuild_job(&claim.job, &claim.token, &claim.head, body)
                .map_err(core_error)?;
            Ok(serde_json::json!({"kind":"summary","summary":summary}).to_string())
        }
    }
}
