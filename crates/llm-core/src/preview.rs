//! 一次性预览票据：发送命令只能消费已预览的原始内容。

use std::time::{Duration, Instant};

use serde::Serialize;
use uuid::Uuid;

use crate::PreparedChat;

const PREVIEW_TTL: Duration = Duration::from_secs(5 * 60);

#[derive(Debug, Clone, Serialize)]
pub struct IssuedPreview {
    pub id: String,
    pub prepared: PreparedChat,
}

struct PendingPreview {
    id: String,
    prepared: PreparedChat,
    issued_at: Instant,
}

/// 单卡片一次只保留最新预览；新预览会使旧票据失效。
#[derive(Default)]
pub struct PreviewLedger {
    pending: Option<PendingPreview>,
}

impl PreviewLedger {
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
        (pending.issued_at.elapsed() <= PREVIEW_TTL).then_some(pending.prepared)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{assemble_chat, AllowAll, ChatRequest, Message, Space};

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
