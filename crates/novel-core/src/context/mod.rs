//! 分层有界上下文装配（T05E）。替代整书拼接：只装必需材料 + 相关证据，
//! 逐项 manifest、可配置预算、必需超限即拒绝。未来信息默认不过界：
//! 检索只取章序不高于目标章的确认章节。

mod budget;
mod manifest;
mod retrieval;

pub use budget::{chinese_char_estimator, estimate_tokens, Budget, EstimatorInfo, DEFAULT_BUDGET_TOKENS};
pub use manifest::{ContextItem, ContextLayer, ContextManifest, OmittedItem};
pub use retrieval::{expand_query, fit_hits, search_chapters, ChapterRef};

use paraselene_memory_core::Database;

use crate::quality::open_questions;

/// 装配输出：分层文本（供消息拼装）+ manifest（供预览与审计）。
#[derive(Debug)]
pub struct AssembledContext {
    /// 逐项装配清单：装了什么、绑定哪个版本、省略了什么及原因。
    pub manifest: ContextManifest,
    /// 硬约束文本（人物卡/禁忌），注入 system 消息。
    pub constraints_text: String,
    /// 目标章选段正文（当前章确认稿）。
    pub selection_text: String,
    /// 参考材料文本（检索证据 + 非硬约束设定），注入 user 消息。
    pub reference_text: String,
    /// 未决议题 JSON，注入 system 消息提醒模型避开或显式标注待决定。
    pub unresolved_text: String,
}

/// 一次装配请求。预算与估算器由调用方传入，便于测试注入小预算触发拒绝路径。
pub struct AssembleRequest<'a> {
    pub work_id: &'a str,
    /// 目标章文档 id；其确认稿为选段层，其章序为检索上界。
    pub target_document_id: &'a str,
    /// 目标章的章序（检索上界；历史改写更窄范围由调用方收紧）。
    pub target_order: i64,
    /// 用户创作要求；同时作为检索查询词（先做别名扩展）。
    pub instruction: &'a str,
    pub budget: Budget,
    pub estimator: EstimatorInfo,
}

/// 把一个来源的正文登记为清单项，并预计算字符数与估算 token。
fn push_item(
    items: &mut Vec<ContextItem>,
    layer: ContextLayer,
    source_id: String,
    source_version: Option<String>,
    body: String,
    estimator: &EstimatorInfo,
) {
    let chars = body.chars().count() as u64;
    let estimated_tokens = estimate_tokens(estimator, &body);
    items.push(ContextItem {
        layer,
        source_id,
        source_version,
        body,
        chars,
        estimated_tokens,
    });
}

/// 装配。硬约束（人物卡/禁忌文档 + 已确认人物/禁忌设定）与目标选段为必需层，
/// 超预算即整体拒绝；检索与设定层在各自配额内贪心装入，溢出记 omitted。
pub fn assemble_context(
    db: &Database,
    request: &AssembleRequest<'_>,
) -> Result<AssembledContext, String> {
    let entries = db
        .novel_canonical_entries(request.work_id)
        .map_err(|e| e.to_string())?;
    let summaries = db
        .novel_document_summaries(request.work_id)
        .map_err(|e| e.to_string())?;
    let order_of: std::collections::HashMap<String, i64> = summaries
        .iter()
        .map(|summary| (summary.id.clone(), summary.order_index))
        .collect();
    let estimator = request.estimator.clone();
    let mut items: Vec<ContextItem> = Vec::new();
    let mut omitted: Vec<OmittedItem> = Vec::new();

    // 必需层 1：硬约束（人物卡与禁忌确认文档 + 已确认的人物/禁忌 lore）。
    let constraints = collect_hard_constraints(db, request.work_id, &entries, &mut items, &estimator)?;
    // 必需层 2：目标章选段（当前章正文）。章节还没有确认稿时为空
    // （例如对空章发起场景/首章试写），检索仍以章序上界为准。
    let target = entries
        .iter()
        .find(|entry| entry.document_id == request.target_document_id);
    let selection_body = target.map(|entry| entry.body.clone()).unwrap_or_default();
    if let Some(target) = target {
        push_item(
            &mut items,
            ContextLayer::Selection,
            format!("document:{}", target.document_id),
            Some(target.version_id.clone()),
            selection_body.clone(),
            &estimator,
        );
    }

    let mut reference = String::new();
    // 检索层：别名扩展 + 章序上界（不高于目标章）。
    let retrieval_text = collect_retrieval_layer(db, request, &entries, &order_of, &mut items, &mut omitted, &estimator)?;
    reference.push_str(&retrieval_text);
    // 设定层：已确认非硬约束设定（世界/时间线/文风），装入剩余配额。
    reference.push_str(&collect_lore_layer(db, request.work_id, &mut items, &mut omitted, &estimator)?);
    // 必需层预算判定：硬约束 + 选段超总预算即拒绝，不静默丢弃。
    let total: u64 = items.iter().map(|item| item.estimated_tokens).sum();
    if total > request.budget.total {
        return Err(format!(
            "必需材料（硬约束与目标章）预计 {} token，超过本次预算 {}；请缩小范围或提高预算",
            total, request.budget.total
        ));
    }

    let unresolved = open_questions(&entries);
    let unresolved_text = serde_json::to_string(&unresolved).map_err(|e| e.to_string())?;
    let manifest = ContextManifest {
        items,
        omitted,
        total_estimated_tokens: total,
        budget_total: request.budget.total,
        estimator,
    };
    Ok(AssembledContext {
        manifest,
        constraints_text: constraints,
        selection_text: selection_body,
        reference_text: reference,
        unresolved_text,
    })
}

/// 检索层：别名扩展查询词，只取章序不高于目标章的确认章节，预算内贪心装入。
fn collect_retrieval_layer(
    db: &Database,
    request: &AssembleRequest<'_>,
    entries: &[paraselene_memory_core::NovelCanonicalEntry],
    order_of: &std::collections::HashMap<String, i64>,
    items: &mut Vec<ContextItem>,
    omitted: &mut Vec<OmittedItem>,
    estimator: &EstimatorInfo,
) -> Result<String, String> {
    let lore_names: Vec<(String, Vec<String>)> = db
        .list_lore_entries(request.work_id, None)
        .map(|entries| entries.into_iter().map(|e| (e.name, e.aliases)).collect())
        .unwrap_or_default();
    let terms = expand_query(request.instruction, &lore_names);
    let chapters: Vec<ChapterRef> = entries
        .iter()
        .filter(|entry| entry.kind == "chapter")
        .filter(|entry| order_of.get(&entry.document_id).copied().unwrap_or(0) <= request.target_order)
        .map(|entry| ChapterRef {
            entry,
            order_index: order_of.get(&entry.document_id).copied().unwrap_or(0),
        })
        .collect();
    let hits = search_chapters(chapters.into_iter(), &terms, 24);
    let (kept, dropped) = fit_hits(hits, request.budget.retrieval_max, estimator);
    let mut reference = String::new();
    for hit in &kept {
        push_item(
            items,
            ContextLayer::Retrieval,
            format!("document:{}#{}-{}", hit.document_id, hit.start_char, hit.end_char),
            Some(hit.version_id.clone()),
            hit.snippet.clone(),
            estimator,
        );
        reference.push_str(&format!("
{}
", serde_json::json!({
            "title": hit.title, "snippet": hit.snippet,
        })));
    }
    for hit in dropped {
        omitted.push(OmittedItem {
            layer: ContextLayer::Retrieval,
            source_id: format!("document:{}", hit.document_id),
            reason: "检索配额已满，省略较远证据".to_string(),
        });
    }
    Ok(reference)
}

/// 硬约束层：人物卡与禁忌确认文档（未定行剥离，只进未决议题）+ 已确认人物/禁忌 lore。
fn collect_hard_constraints(
    db: &Database,
    work_id: &str,
    entries: &[paraselene_memory_core::NovelCanonicalEntry],
    items: &mut Vec<ContextItem>,
    estimator: &EstimatorInfo,
) -> Result<String, String> {
    let mut constraints = String::new();
    for entry in entries {
        if matches!(entry.kind.as_str(), "character" | "taboo") {
            let resolved = crate::quality::resolved_body(&entry.body);
            push_item(
                items,
                ContextLayer::HardConstraints,
                format!("document:{}", entry.document_id),
                Some(entry.version_id.clone()),
                resolved.clone(),
                estimator,
            );
            constraints.push_str(&format!("
{}
", serde_json::json!({
                "kind": entry.kind, "title": entry.title, "body": resolved,
            })));
        }
    }
    let lore = db.list_lore_entries(work_id, None).map_err(|e| e.to_string())?;
    for entry in lore {
        if entry.status != "confirmed" || !matches!(entry.kind.as_str(), "character" | "taboo") {
            continue;
        }
        let head = db
            .list_lore_versions(&entry.id)
            .ok()
            .and_then(|versions| versions.into_iter().find(|v| v.version == entry.head_version));
        if let Some(version) = head {
            push_item(
                items,
                ContextLayer::HardConstraints,
                format!("lore:{}", entry.id),
                Some(format!("lore-v{}", version.version)),
                version.body.clone(),
                estimator,
            );
            constraints.push_str(&format!("
{}
", serde_json::json!({
                "lore": entry.name, "body": version.body,
            })));
        }
    }
    Ok(constraints)
}

/// 设定层：已确认非硬约束设定（世界/时间线/文风），预算内贪心装入。
fn collect_lore_layer(
    db: &Database,
    work_id: &str,
    items: &mut Vec<ContextItem>,
    omitted: &mut Vec<OmittedItem>,
    estimator: &EstimatorInfo,
) -> Result<String, String> {
    let mut reference = String::new();
    let lore = db.list_lore_entries(work_id, None).map_err(|e| e.to_string())?;
    for entry in lore {
        if entry.status != "confirmed" || matches!(entry.kind.as_str(), "character" | "taboo") {
            continue;
        }
        let head = db
            .list_lore_versions(&entry.id)
            .ok()
            .and_then(|versions| versions.into_iter().find(|v| v.version == entry.head_version));
        let Some(version) = head else { continue };
        let cost = estimate_tokens(estimator, &version.body);
        if cost > DEFAULT_BUDGET_TOKENS / 4 {
            omitted.push(OmittedItem {
                layer: ContextLayer::Lore,
                source_id: format!("lore:{}", entry.id),
                reason: "设定条目过长，超过单层配额".to_string(),
            });
            continue;
        }
        push_item(
            items,
            ContextLayer::Lore,
            format!("lore:{}", entry.id),
            Some(format!("lore-v{}", version.version)),
            version.body.clone(),
            estimator,
        );
        reference.push_str(&format!("
{}
", serde_json::json!({
            "lore": entry.name, "body": version.body,
        })));
    }
    Ok(reference)
}

#[cfg(test)]
mod tests {
    use super::*;
    use paraselene_memory_core::{Database, DraftOrigin, NovelKind};

    fn work_with_late_reveal() -> (Database, String, String, String) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let mut ids = Vec::new();
        for (title, body) in [
            ("第一章", "她走进月港城门。"),
            ("第二章", "钟声从河面漂过来。"),
            ("第三章", "远方的反转尚未发生。"),
        ] {
            let chapter = db
                .create_novel_document(&work.id, NovelKind::Chapter, title)
                .unwrap();
            let draft = db
                .create_novel_draft(&chapter.id, body, DraftOrigin::User)
                .unwrap();
            db.accept_novel_draft(&draft.id).unwrap();
            ids.push(chapter.id);
        }
        let card = db
            .create_novel_document(&work.id, NovelKind::Character, "主角")
            .unwrap();
        let draft = db
            .create_novel_draft(&card.id, "主角不轻易杀人", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        (db, work.id, ids[0].clone(), ids[2].clone())
    }

    fn request<'a>(work_id: &'a str, target: &'a str, order: i64, budget: u64) -> AssembleRequest<'a> {
        AssembleRequest {
            work_id,
            target_document_id: target,
            target_order: order,
            instruction: "城门",
            budget: Budget::balanced(budget),
            estimator: chinese_char_estimator(),
        }
    }

    #[test]
    fn 装配只含目标章序以内的检索证据() {
        let (db, work_id, first, _third) = work_with_late_reveal();
        let assembled = assemble_context(&db, &request(&work_id, &first, 0, 4000)).unwrap();
        let titles: Vec<&str> = assembled
            .manifest
            .items
            .iter()
            .filter(|item| item.layer == ContextLayer::Retrieval)
            .map(|item| item.source_id.as_str())
            .collect();
        assert!(titles.iter().all(|id| !id.contains("远方的反转")), "未来章证据不得越界");
        assert!(assembled.constraints_text.contains("不轻易杀人"));
        assert!(assembled.selection_text.contains("月港"));
    }

    #[test]
    fn 必需材料超预算即拒绝并给出原因() {
        let (db, work_id, first, _) = work_with_late_reveal();
        // 目标章很长 + 极小预算：必拒绝。
        let big = db
            .create_novel_document(&work_id, NovelKind::Chapter, "巨章")
            .unwrap();
        let draft = db
            .create_novel_draft(&big.id, &"长".repeat(9000), DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        let err = assemble_context(&db, &request(&work_id, &big.id, 9, 100)).unwrap_err();
        assert!(err.contains("必需材料"), "必须说明是必需层超限");
    }

    #[test]
    fn manifest记录估算器身份与省略原因() {
        let (db, work_id, first, _) = work_with_late_reveal();
        let assembled = assemble_context(&db, &request(&work_id, &first, 0, 4000)).unwrap();
        assert_eq!(assembled.manifest.estimator.name, "chinese-char-v1");
        assert!(assembled.manifest.total_estimated_tokens <= assembled.manifest.budget_total);
        for omitted in &assembled.manifest.omitted {
            assert!(!omitted.reason.is_empty());
        }
    }
}
