//! 模型流消费：只在明确收到 stop 且正文非空时返回；中断、截断与
//! 工具调用一律拒绝保存，避免不完整候选混入试写。

use futures_util::{Stream, StreamExt};
use paraselene_llm_core as llm;

use crate::MAX_RESPONSE_CHARS;

/// 消费模型流，只在明确收到 stop 且正文非空时返回；中断和截断不会变成试写。
pub async fn collect_complete<S>(stream: S) -> Result<String, String>
where
    S: Stream<Item = llm::Result<llm::StreamEvent>>,
{
    futures_util::pin_mut!(stream);
    let mut body = String::new();
    let mut completed = false;
    while let Some(event) = stream.next().await {
        match event.map_err(|e| e.to_string())? {
            llm::StreamEvent::Delta { content } => {
                body.push_str(&content);
                // 边收边查上限：恶意或失控的流不可能撑爆内存。
                if body.chars().count() > MAX_RESPONSE_CHARS {
                    return Err("模型回复超过试写长度上限，未保存".into());
                }
            }
            // 试写路径不允许工具调用：出现即视为模型偏离契约，整体拒绝。
            llm::StreamEvent::ToolCalls { .. } => {
                return Err("小说试写不接受工具调用，未保存".into())
            }
            // 只有显式 stop 算完整；length 截断、内容过滤等其它终态一律拒绝保存。
            llm::StreamEvent::Done {
                finish_reason: llm::FinishReason::Stop,
                ..
            } => {
                completed = true;
                break;
            }
            llm::StreamEvent::Done { .. } => return Err("模型回复未完整结束，未保存试写".into()),
        }
    }
    if !completed || body.trim().is_empty() {
        return Err("模型回复中断或为空，未保存试写".into());
    }
    Ok(body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generation::prepare_generation;
    use futures_util::stream;
    use paraselene_memory_core::{Database, DraftOrigin, NovelKind};

    #[tokio::test]
    async fn 只接受完整停止的非空回复() {
        let complete = stream::iter(vec![
            Ok(llm::StreamEvent::Delta {
                content: "试写".into(),
            }),
            Ok(llm::StreamEvent::Done {
                finish_reason: llm::FinishReason::Stop,
                usage: None,
            }),
        ]);
        assert_eq!(collect_complete(complete).await.unwrap(), "试写");
        let interrupted = stream::iter(vec![Ok(llm::StreamEvent::Delta {
            content: "半段".into(),
        })]);
        assert!(collect_complete(interrupted).await.is_err());
        let truncated = stream::iter(vec![
            Ok(llm::StreamEvent::Delta {
                content: "半段".into(),
            }),
            Ok(llm::StreamEvent::Done {
                finish_reason: llm::FinishReason::Length,
                usage: None,
            }),
        ]);
        assert!(collect_complete(truncated).await.is_err());
    }

    #[tokio::test]
    async fn 完整模型回复仅进试写_确认后才进入下一次上下文() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let first = prepare_generation(&db, &llm::AllowAll, &chapter.id, "试写", "model").unwrap();
        let body = collect_complete(stream::iter(vec![
            Ok(llm::StreamEvent::Delta {
                content: "AI 候选桥段".into(),
            }),
            Ok(llm::StreamEvent::Done {
                finish_reason: llm::FinishReason::Stop,
                usage: None,
            }),
        ]))
        .await
        .unwrap();
        let draft = db
            .create_novel_draft_at_head(
                &first.document_id,
                first.base_version_id.as_deref(),
                &body,
                DraftOrigin::Ai,
            )
            .unwrap();
        assert!(db.novel_canonical_entries(&work.id).unwrap().is_empty());
        let next = prepare_generation(&db, &llm::AllowAll, &chapter.id, "桥段", "model").unwrap();
        assert!(!format!("{:?}", next.prepared.messages).contains("AI 候选桥段"));
        db.accept_novel_draft(&draft.id).unwrap();
        let accepted =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "桥段", "model").unwrap();
        assert!(format!("{:?}", accepted.prepared.messages).contains("AI 候选桥段"));
        assert_ne!(first.context_versions, accepted.context_versions);
    }
}
