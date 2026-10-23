//! 一次性预览票据：发送命令只能消费已预览的原始内容。

use std::time::{Duration, Instant};

use serde::Serialize;
use uuid::Uuid;

use crate::PreparedChat;

/// 票据有效期 5 分钟：预览是「发送前快照」，隔太久再确认已不代表用户意图，过期即视为放弃。
const PREVIEW_TTL: Duration = Duration::from_secs(5 * 60);

/// 已签发的预览票据：IPC 预览命令的返回，含完整预览内容与一次性票据编号。
#[derive(Debug, Clone, Serialize)]
pub struct IssuedPreview {
    /// 票据编号（Uuid v4）：发送命令凭它领取内容，只能消费一次。
    pub id: String,
    /// 预览内容本体：用户看到的就是这一份，发送时原样消费（防漂移）。
    pub prepared: PreparedChat,
}

/// 内存中的待消费票据：比 IssuedPreview 多记签发时间，用于 TTL 判定。
struct PendingPreview {
    id: String,
    prepared: PreparedChat,
    /// 签发时刻：超过 PREVIEW_TTL 未消费即过期。
    issued_at: Instant,
}

/// 单卡片一次只保留最新预览；新预览会使旧票据失效。
#[derive(Default)]
pub struct PreviewLedger {
    pending: Option<PendingPreview>,
}

impl PreviewLedger {
    /// 签发新预览票据；同卡片旧票据立即失效（ledger 只保留最新一份预览）。
    pub fn issue(&mut self, prepared: PreparedChat) -> IssuedPreview {
        let id = Uuid::new_v4().to_string();
        self.pending = Some(PendingPreview {
            id: id.clone(),
            prepared: prepared.clone(),
            issued_at: Instant::now(),
        });
        IssuedPreview { id, prepared }
    }

    /// 消费一次；无效、过期或已消费的编号都不能获取待发送内容。
    pub fn take(&mut self, id: &str) -> Option<PreparedChat> {
        let pending = self.pending.as_ref()?;
        if pending.id != id {
            return None;
        }
        let pending = self.pending.take()?;
        // 过期也一并消耗掉：take 先取出票据再判 TTL，过期编号不能反复试探
        (pending.issued_at.elapsed() <= PREVIEW_TTL).then_some(pending.prepared)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{assemble_chat, AllowAll, ChatRequest, Message, Space};

    /// 测试构造：组一个最小 PreparedChat（personal 空间 + 单条 user 消息）。
    fn prepared(text: &str) -> PreparedChat {
        assemble_chat(
            &AllowAll,
            ChatRequest {
                space: Space::Personal,
                messages: vec![Message::user(text)],
                model: None,
                max_tokens: None,
                temperature: None,
                tools: None,
            },
            "test-model",
        )
        .unwrap()
    }

    #[test]
    fn ticket_returns_exact_preview_once() {
        let mut ledger = PreviewLedger::default();
        let issued = ledger.issue(prepared("原始内容"));
        assert_eq!(ledger.take(&issued.id), Some(issued.prepared));
        assert!(ledger.take(&issued.id).is_none());
    }

    #[test]
    fn new_preview_invalidates_previous_ticket() {
        let mut ledger = PreviewLedger::default();
        let old = ledger.issue(prepared("旧内容"));
        let new = ledger.issue(prepared("新内容"));
        assert!(ledger.take(&old.id).is_none());
        assert_eq!(ledger.take(&new.id), Some(new.prepared));
    }

    #[test]
    fn expired_ticket_cannot_send() {
        let mut ledger = PreviewLedger::default();
        let issued = ledger.issue(prepared("已过期"));
        ledger.pending.as_mut().unwrap().issued_at =
            Instant::now() - PREVIEW_TTL - Duration::from_secs(1);
        assert!(ledger.take(&issued.id).is_none());
        assert!(ledger.take(&issued.id).is_none());
    }
}
