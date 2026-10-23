//! dsh 受控出口：可信调用方绑定运行归属，模型仅提交请求提案。
//!
//! 本模块不读取凭据、不启动进程。请求先由 Rust 序列化并保存在内存；
//! 确认只能消费票据，不能替换正文。原生调用方负责从用户选择/数据库取得
//! 可信 scope；不可直接使用 dsh 提交的空间或作品 ID 建立授权。

use std::time::{Duration, Instant};

use futures_util::future::{AbortHandle, AbortRegistration, Abortable};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    assemble_chat, ChatRequest, CloudGate, Message, OpenAiCompatClient, ProviderTool, Space,
    StreamEvent,
};

pub const OFFICIAL_COMPLETIONS_URL: &str = "https://api.deepseek.com/v1/chat/completions";
const PREVIEW_TTL: Duration = Duration::from_secs(5 * 60);
const RUN_TTL: Duration = Duration::from_secs(30 * 60);
const MAX_BODY_BYTES: usize = 1024 * 1024;

/// 每一个模型调用都必须显式归类；辅助调用没有免确认特权。
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallPurpose {
    Conversation,
    Compaction,
    SessionTitle,
}

/// 由原生应用建立的归属，不是模型自报身份；作品权限仍须领域服务验证。
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RunScope {
    pub space: Space,
    pub work_id: Option<String>,
}

/// 白名单提案。没有 endpoint、headers、api_key、scope 或额外上传字段。
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelProposal {
    pub model: String,
    pub messages: Vec<Message>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    pub tools: Option<Vec<ProviderTool>>,
    pub purpose: CallPurpose,
}

/// 安全错误不携带请求正文、模型响应或凭据。
#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum EgressError {
    #[error("已有活动，请先结束当前运行")]
    Busy,
    #[error("运行或预览已失效，请重新开始")]
    InvalidTicket,
    #[error("该空间已关闭云模型调用")]
    GateClosed,
    #[error("运行归属或模型请求不符合出口约束")]
    InvalidProposal,
    #[error("请求超过出口大小限制")]
    TooLarge,
    #[error("请求已取消")]
    Cancelled,
    #[error("模型传输失败")]
    Transport,
    #[error("接收端已断开")]
    Disconnected,
}

/// 原生侧的运行句柄；仅交给可信宿主，不能发给 dsh 充当自行授权凭据。
#[derive(Clone, Serialize)]
pub struct RunGrant {
    pub id: String,
    pub scope: RunScope,
    pub model: String,
}

/// body_json 是最终 HTTP 正文的 UTF-8 文本，不包含 Authorization 请求头。
/// 不派生 Debug，避免调试日志意外输出记忆或会话正文。
#[derive(Clone, Serialize)]
pub struct EgressPreview {
    pub id: String,
    pub run_id: String,
    pub scope: RunScope,
    pub purpose: CallPurpose,
    pub endpoint: &'static str,
    pub body_json: String,
}

/// 构造只发生在出口内；消费授权后，传输不能重新组装消息或追加字段。
pub struct FrozenChat {
    body_json: String,
}

impl FrozenChat {
    pub(crate) fn body_json(&self) -> &str {
        &self.body_json
    }
}

struct Pending {
    preview: EgressPreview,
    issued_at: Instant,
}
struct InFlight {
    id: String,
    abort: AbortHandle,
}
struct ActiveRun {
    grant: RunGrant,
    started: Instant,
    pending: Option<Pending>,
    in_flight: Option<InFlight>,
}

/// 单个桌面卡片一次一个运行、一个待确认请求和一个发送。
/// 容量有界；新预览使旧票据失效，结束运行会撤销预览并中止在途请求。
#[derive(Default)]
pub struct EgressLedger {
    active: Option<ActiveRun>,
}

impl EgressLedger {
    fn expire(&mut self) {
        if self
            .active
            .as_ref()
            .is_some_and(|run| run.started.elapsed() > RUN_TTL)
        {
            if let Some(flight) = self.active.take().and_then(|run| run.in_flight) {
                flight.abort.abort();
            }
        }
    }

    fn active(&mut self, id: &str) -> Result<&mut ActiveRun, EgressError> {
        self.expire();
        self.active
            .as_mut()
            .filter(|run| run.grant.id == id)
            .ok_or(EgressError::InvalidTicket)
    }

    /// 只由可信应用根据用户选择调用；不联网，关闭云调用时立即拒绝。
    pub fn begin(
        &mut self,
        gate: &dyn CloudGate,
        scope: RunScope,
        model: String,
    ) -> Result<RunGrant, EgressError> {
        self.expire();
        if self.active.is_some() {
            return Err(EgressError::Busy);
        }
        if !gate.cloud_enabled(scope.space) {
            return Err(EgressError::GateClosed);
        }
        let valid_work = match (&scope.space, &scope.work_id) {
            (Space::Novel, Some(id)) => {
                !id.is_empty()
                    && id.len() <= 128
                    && id
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
            }
            (Space::Novel, None) => false,
            (_, None) => true,
            _ => false,
        };
        if !valid_work
            || model.is_empty()
            || model.len() > 128
            || model.chars().any(|c| c.is_control() || c.is_whitespace())
        {
            return Err(EgressError::InvalidProposal);
        }
        let grant = RunGrant {
            id: Uuid::new_v4().to_string(),
            scope,
            model,
        };
        self.active = Some(ActiveRun {
            grant: grant.clone(),
            started: Instant::now(),
            pending: None,
            in_flight: None,
        });
        Ok(grant)
    }

    /// 冻结原生序列化后的最终请求。归属和模型来自运行句柄，提案无权扩展。
    pub fn prepare(
        &mut self,
        gate: &dyn CloudGate,
        run_id: &str,
        proposal: ModelProposal,
    ) -> Result<EgressPreview, EgressError> {
        let run = self.active(run_id)?;
        if run.in_flight.is_some() {
            return Err(EgressError::Busy);
        }
        // 即使本次提案非法，先前的确认内容也不再代表最新意图。
        run.pending = None;
        if !gate.cloud_enabled(run.grant.scope.space) {
            return Err(EgressError::GateClosed);
        }
        if proposal.model != run.grant.model
            || proposal.messages.is_empty()
            || proposal.max_tokens == Some(0)
            || proposal
                .temperature
                .is_some_and(|v| !v.is_finite() || !(0.0..=2.0).contains(&v))
        {
            return Err(EgressError::InvalidProposal);
        }
        let purpose = proposal.purpose;
        let prepared = assemble_chat(
            gate,
            ChatRequest {
                space: run.grant.scope.space,
                messages: proposal.messages,
                model: Some(proposal.model),
                max_tokens: proposal.max_tokens,
                temperature: proposal.temperature,
                tools: proposal.tools,
            },
            &run.grant.model,
        )
        .map_err(|_| EgressError::InvalidProposal)?;
        let body_json = serde_json::to_string(&crate::openai::request_body(&prepared))
            .map_err(|_| EgressError::InvalidProposal)?;
        if body_json.len() > MAX_BODY_BYTES {
            return Err(EgressError::TooLarge);
        }
        let preview = EgressPreview {
            id: Uuid::new_v4().to_string(),
            run_id: run.grant.id.clone(),
            scope: run.grant.scope.clone(),
            purpose,
            endpoint: OFFICIAL_COMPLETIONS_URL,
            body_json,
        };
        run.pending = Some(Pending {
            preview: preview.clone(),
            issued_at: Instant::now(),
        });
        Ok(preview)
    }

    /// 发送只能指定票据，不接受正文。消费后再次查开关；失败也不恢复票据。
    pub fn authorize(
        &mut self,
        gate: &dyn CloudGate,
        run_id: &str,
        preview_id: &str,
    ) -> Result<AuthorizedCall, EgressError> {
        let run = self.active(run_id)?;
        if run.in_flight.is_some() {
            return Err(EgressError::Busy);
        }
        let pending = run
            .pending
            .as_ref()
            .filter(|p| p.preview.id == preview_id)
            .ok_or(EgressError::InvalidTicket)?;
        if pending.issued_at.elapsed() > PREVIEW_TTL {
            run.pending = None;
            return Err(EgressError::InvalidTicket);
        }
        let pending = run.pending.take().ok_or(EgressError::InvalidTicket)?;
        if !gate.cloud_enabled(run.grant.scope.space) {
            return Err(EgressError::GateClosed);
        }
        let (abort, registration) = AbortHandle::new_pair();
        run.in_flight = Some(InFlight {
            id: pending.preview.id.clone(),
            abort: abort.clone(),
        });
        Ok(AuthorizedCall {
            id: pending.preview.id,
            request: FrozenChat {
                body_json: pending.preview.body_json,
            },
            registration,
            cancellation: abort,
        })
    }

    /// 传输结束后由宿主调用；旧运行/旧请求的迟到结束不能释放另一请求。
    pub fn settle(&mut self, run_id: &str, call_id: &str) {
        if let Ok(run) = self.active(run_id) {
            if run
                .in_flight
                .as_ref()
                .is_some_and(|flight| flight.id == call_id)
            {
                run.in_flight = None;
            }
        }
    }

    /// 用户取消、进程退出或宿主清理时撤销整个运行，立即中断连接/收流。
    pub fn end(&mut self, run_id: &str) -> Result<(), EgressError> {
        self.active(run_id)?;
        if let Some(flight) = self.active.take().and_then(|run| run.in_flight) {
            flight.abort.abort();
        }
        Ok(())
    }
}

/// 一次性发送租约，不可序列化给 dsh；原生调用方负责最终 settle。
pub struct AuthorizedCall {
    pub id: String,
    request: FrozenChat,
    registration: AbortRegistration,
    cancellation: AbortHandle,
}

impl AuthorizedCall {
    /// 只在 Rust 内传入 Key。取消覆盖连接建立与后续收流；接收端断开即停。
    /// 生产调用方必须使用 `OpenAiCompatClient::deepseek()`，端点不由提案决定。
    pub async fn execute(
        self,
        client: &OpenAiCompatClient,
        key: &str,
        mut on_event: impl FnMut(StreamEvent) -> bool,
    ) -> Result<(), EgressError> {
        Abortable::new(
            async {
                let mut stream = client
                    .send_frozen(&self.request, key)
                    .await
                    .map_err(|_| EgressError::Transport)?;
                while let Some(event) = stream.next().await {
                    if self.cancellation.is_aborted() {
                        return Err(EgressError::Cancelled);
                    }
                    let event = event.map_err(|_| EgressError::Transport)?;
                    if !on_event(event) {
                        return Err(EgressError::Disconnected);
                    }
                }
                if self.cancellation.is_aborted() {
                    Err(EgressError::Cancelled)
                } else {
                    Ok(())
                }
            },
            self.registration,
        )
        .await
        .map_err(|_| EgressError::Cancelled)?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AllowAll, SpaceSwitch};

    fn scope() -> RunScope {
        RunScope {
            space: Space::Idea,
            work_id: None,
        }
    }
    fn proposal(purpose: CallPurpose) -> ModelProposal {
        ModelProposal {
            model: "fixture-model".into(),
            messages: vec![Message::user("synthetic 中文")],
            max_tokens: Some(32),
            temperature: Some(0.5),
            tools: None,
            purpose,
        }
    }
    fn start() -> (EgressLedger, RunGrant) {
        let mut ledger = EgressLedger::default();
        let grant = ledger
            .begin(&AllowAll, scope(), "fixture-model".into())
            .unwrap();
        (ledger, grant)
    }

    #[test]
    fn begin_checks_gate_scope_and_model_without_creating_a_request() {
        let mut ledger = EgressLedger::default();
        let closed = SpaceSwitch {
            idea: false,
            ..Default::default()
        };
        assert!(matches!(
            ledger.begin(&closed, scope(), "fixture-model".into()),
            Err(EgressError::GateClosed)
        ));
        for invalid in [
            RunScope {
                space: Space::Novel,
                work_id: None,
            },
            RunScope {
                space: Space::Personal,
                work_id: Some("work".into()),
            },
            RunScope {
                space: Space::Novel,
                work_id: Some("../path".into()),
            },
        ] {
            assert!(matches!(
                ledger.begin(&AllowAll, invalid, "fixture-model".into()),
                Err(EgressError::InvalidProposal)
            ));
        }
        assert!(ledger.active.is_none());
        let grant = ledger
            .begin(&AllowAll, scope(), "fixture-model".into())
            .unwrap();
        assert!(ledger.active.as_ref().unwrap().pending.is_none());
        assert!(matches!(
            ledger.begin(&AllowAll, scope(), "fixture-model".into()),
            Err(EgressError::Busy)
        ));
        ledger.end(&grant.id).unwrap();
    }

    #[test]
    fn proposal_cannot_supply_credentials_upload_fields_or_scope() {
        for field in [
            "api_key",
            "headers",
            "endpoint",
            "scope",
            "dsh_session_log",
            "dsh_plugin_packages",
        ] {
            let mut value = serde_json::json!({"model":"fixture-model", "messages":[], "purpose":"conversation"});
            value[field] = serde_json::json!("synthetic-forbidden");
            assert!(serde_json::from_value::<ModelProposal>(value).is_err());
        }
        assert!(
            serde_json::from_value::<ModelProposal>(serde_json::json!({
                "model":"fixture-model", "messages":[]
            }))
            .is_err(),
            "purpose must be explicit, including auxiliary calls"
        );
    }

    #[test]
    fn preview_is_final_wire_snapshot_and_mutating_display_cannot_change_send() {
        let (mut ledger, grant) = start();
        let mut preview = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        assert_eq!(preview.endpoint, OFFICIAL_COMPLETIONS_URL);
        let body: serde_json::Value = serde_json::from_str(&preview.body_json).unwrap();
        assert_eq!(body["messages"][0]["content"], "synthetic 中文");
        assert_eq!(body["stream_options"]["include_usage"], true);
        assert!(body.get("purpose").is_none());
        assert!(body.get("scope").is_none());
        let approved = preview.body_json.clone();
        preview.body_json = "tampered display copy".into();
        let call = ledger.authorize(&AllowAll, &grant.id, &preview.id).unwrap();
        assert_eq!(call.request.body_json(), approved);
    }

    #[test]
    fn foreign_run_and_ticket_do_not_consume_the_valid_preview() {
        let (mut ledger, grant) = start();
        let preview = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        assert!(matches!(
            ledger.authorize(&AllowAll, "foreign", &preview.id),
            Err(EgressError::InvalidTicket)
        ));
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, "foreign"),
            Err(EgressError::InvalidTicket)
        ));
        assert!(ledger.authorize(&AllowAll, &grant.id, &preview.id).is_ok());
    }

    #[test]
    fn newer_preview_and_invalid_new_intent_revoke_old_tickets() {
        let (mut ledger, grant) = start();
        let old = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        let new = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Compaction))
            .unwrap();
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, &old.id),
            Err(EgressError::InvalidTicket)
        ));
        let mut changed = proposal(CallPurpose::Conversation);
        changed.model = "unapproved-model".into();
        assert!(matches!(
            ledger.prepare(&AllowAll, &grant.id, changed),
            Err(EgressError::InvalidProposal)
        ));
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, &new.id),
            Err(EgressError::InvalidTicket)
        ));
    }

    #[test]
    fn authorize_is_once_only_and_auxiliary_calls_require_fresh_confirmation() {
        let (mut ledger, grant) = start();
        for purpose in [
            CallPurpose::Conversation,
            CallPurpose::Compaction,
            CallPurpose::SessionTitle,
        ] {
            let preview = ledger
                .prepare(&AllowAll, &grant.id, proposal(purpose))
                .unwrap();
            let call = ledger.authorize(&AllowAll, &grant.id, &preview.id).unwrap();
            assert!(matches!(
                ledger.authorize(&AllowAll, &grant.id, &preview.id),
                Err(EgressError::Busy)
            ));
            assert!(matches!(
                ledger.prepare(&AllowAll, &grant.id, proposal(purpose)),
                Err(EgressError::Busy)
            ));
            ledger.settle(&grant.id, "wrong-call");
            assert!(matches!(
                ledger.prepare(&AllowAll, &grant.id, proposal(purpose)),
                Err(EgressError::Busy)
            ));
            ledger.settle(&grant.id, &call.id);
            assert!(matches!(
                ledger.authorize(&AllowAll, &grant.id, &preview.id),
                Err(EgressError::InvalidTicket)
            ));
        }
    }

    #[test]
    fn gate_rechecked_on_send_and_rejected_ticket_never_revives() {
        let (mut ledger, grant) = start();
        let preview = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        let closed = SpaceSwitch {
            idea: false,
            ..Default::default()
        };
        assert!(matches!(
            ledger.authorize(&closed, &grant.id, &preview.id),
            Err(EgressError::GateClosed)
        ));
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, &preview.id),
            Err(EgressError::InvalidTicket)
        ));
    }

    #[test]
    fn preview_expiry_and_run_expiry_revoke_authority() {
        let (mut ledger, grant) = start();
        let preview = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        ledger
            .active
            .as_mut()
            .unwrap()
            .pending
            .as_mut()
            .unwrap()
            .issued_at = Instant::now() - PREVIEW_TTL - Duration::from_secs(1);
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, &preview.id),
            Err(EgressError::InvalidTicket)
        ));
        ledger.active.as_mut().unwrap().started = Instant::now() - RUN_TTL - Duration::from_secs(1);
        assert!(matches!(
            ledger.prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation)),
            Err(EgressError::InvalidTicket)
        ));
        assert!(ledger
            .begin(&AllowAll, scope(), "fixture-model".into())
            .is_ok());
    }

    #[test]
    fn oversized_payload_and_invalid_numeric_options_are_rejected() {
        let (mut ledger, grant) = start();
        let mut big = proposal(CallPurpose::Conversation);
        big.messages = vec![Message::user("x".repeat(MAX_BODY_BYTES))];
        assert!(matches!(
            ledger.prepare(&AllowAll, &grant.id, big),
            Err(EgressError::TooLarge)
        ));
        for temperature in [f32::NAN, f32::INFINITY, -0.1, 2.1] {
            let mut invalid = proposal(CallPurpose::Conversation);
            invalid.temperature = Some(temperature);
            assert!(matches!(
                ledger.prepare(&AllowAll, &grant.id, invalid),
                Err(EgressError::InvalidProposal)
            ));
        }
    }

    #[tokio::test]
    async fn end_revokes_pending_and_aborts_authorized_call_before_network() {
        let (mut ledger, grant) = start();
        let preview = ledger
            .prepare(&AllowAll, &grant.id, proposal(CallPurpose::Conversation))
            .unwrap();
        let call = ledger.authorize(&AllowAll, &grant.id, &preview.id).unwrap();
        ledger.end(&grant.id).unwrap();
        // 没有服务监听此端口；取消必须先于连接错误，不会进入 HTTP 请求。
        let client = OpenAiCompatClient::new("http://127.0.0.1:1/v1").unwrap();
        assert_eq!(
            call.execute(&client, "synthetic-not-a-credential", |_| panic!(
                "cancelled request emitted an event"
            ))
            .await,
            Err(EgressError::Cancelled)
        );
        assert!(matches!(
            ledger.authorize(&AllowAll, &grant.id, &preview.id),
            Err(EgressError::InvalidTicket)
        ));
    }
}

impl Drop for EgressLedger {
    fn drop(&mut self) {
        if let Some(flight) = self.active.take().and_then(|run| run.in_flight) {
            flight.abort.abort();
        }
    }
}
