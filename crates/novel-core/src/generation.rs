//! 生成上下文组装：整章试写与选段编辑的预览共用同一条装配路径。
//! 人物卡与禁忌是系统级硬约束，其余已确认文档为参考；未决议题剔除硬约束
//! 后单列。当前实现拼接全作品确认稿并以 30000 字为上限——这是已知债务
//! （T05E 以分层有界上下文替换），提高常量不算解决。

use paraselene_llm_core as llm;
use paraselene_memory_core::Database;

use crate::context::{
    assemble_context, chinese_char_estimator, AssembleRequest, Budget, ContextManifest,
    DEFAULT_BUDGET_TOKENS,
};
use crate::edit::{validate_selection, EditSelection};
#[cfg(test)]
use crate::quality::open_questions;
use crate::MAX_INSTRUCTION_CHARS;

/// 一次生成的完整计划：目标文档、版本签名、组装好的模型请求与装配清单。
/// 调用方据此发起流式请求；`base_version_id`/`context_versions` 用于事后
/// 核对"预览期间正稿是否变化"，过期计划必须作废重来。
pub struct GenerationPlan {
    pub document_id: String,
    pub work_id: String,
    /// 生成时点的正稿头版本；保存试写时绑定，变化即视为过期。
    pub base_version_id: Option<String>,
    /// 当前作品全部确认文档的 (document_id, version_id) 签名。
    pub context_versions: Vec<(String, String)>,
    pub prepared: llm::PreparedChat,
    /// 分层装配清单（T05E）：预览与审计逐项可见。
    pub manifest: Option<ContextManifest>,
}

/// 当前作品全部已确认文档的版本签名；试写和已丢弃内容不会影响它。
pub fn current_context_versions(
    db: &Database,
    work_id: &str,
) -> Result<Vec<(String, String)>, String> {
    Ok(db
        .novel_canonical_entries(work_id)
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(|entry| (entry.document_id, entry.version_id))
        .collect())
}

/// 构造一章的云模型预览。人物卡和禁忌作为系统级硬约束；其他材料也仅取当前 head。
/// 超出上下文上限时明确报错，不静默丢弃设定或章节。
pub fn prepare_generation(
    db: &Database,
    gate: &dyn llm::CloudGate,
    document_id: &str,
    instruction: &str,
    default_model: &str,
) -> Result<GenerationPlan, String> {
    let instruction = instruction.trim();
    if instruction.is_empty() || instruction.chars().count() > MAX_INSTRUCTION_CHARS {
        return Err("创作要求须为 1–2000 个字".into());
    }
    prepare_with_request(
        db,
        gate,
        document_id,
        instruction,
        "只输出一份待用户审核的试写正文，不宣称已保存为正稿。",
        default_model,
    )
}

/// 选段编辑预览：验证 Unicode 字符边界与当前确认稿一致，再组装模型请求。
pub fn prepare_edit(
    db: &Database,
    gate: &dyn llm::CloudGate,
    document_id: &str,
    selection: EditSelection,
    instruction: &str,
    default_model: &str,
) -> Result<(GenerationPlan, EditSelection), String> {
    let instruction = instruction.trim();
    if instruction.chars().count() > MAX_INSTRUCTION_CHARS {
        return Err("补充要求不能超过 2000 个字".into());
    }
    let document = db
        .get_novel_document(document_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说文档不存在".to_string())?;
    let body = document
        .head_body
        .as_deref()
        .ok_or_else(|| "请先确认章节正稿，再选择段落".to_string())?;
    validate_selection(body, &selection)?;
    let (mode_request, output_rule) = match selection.mode {
        crate::EditMode::DialogueOnly => (
            "只改下面选段中的对白；对白之外的文字必须逐字不变。",
            "只输出替换选段的完整文字，保留原有对白之外的每一个字符；不要输出解释、标题或整章。",
        ),
        crate::EditMode::PreserveAction => (
            "重写下面选段，保留人物动作、事件因果和行为逻辑。",
            "只输出替换选段的完整文字，不要输出解释、标题或整章。",
        ),
        crate::EditMode::ContinueShort => (
            "接在下面选段之后续写一小段，不重写原文。",
            "只输出新增的短续写文字，不要重复选段、解释或整章。",
        ),
    };
    let request = format!(
        "{mode_request}\n选段：{}\n补充要求：{instruction}",
        serde_json::to_string(&selection.selected_text).map_err(|e| e.to_string())?
    );
    let plan = prepare_with_request(db, gate, document_id, &request, output_rule, default_model)?;
    // 装配期间正稿可能已被他人确认新版本：选段坐标基于旧快照，必须整体作废。
    if plan.base_version_id != document.head_version_id {
        return Err("正稿在选段预览时变化，请重新选择".into());
    }
    Ok((plan, selection))
}

/// 生成与选段编辑共用的装配核心。只接受 chapter 文档；系统消息放硬约束
/// （人物卡/禁忌 + 未决议题处理规则），用户消息放参考材料与请求，两者分离
/// 是为了让"必须遵守"与"仅供参考"在提示词结构中可区分。
pub(crate) fn prepare_with_request(
    db: &Database,
    gate: &dyn llm::CloudGate,
    document_id: &str,
    request: &str,
    output_rule: &str,
    default_model: &str,
) -> Result<GenerationPlan, String> {
    let document = db
        .get_novel_document(document_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说文档不存在".to_string())?;
    if document.kind != "chapter" {
        return Err("请在章节中生成试写；设定和人物卡由你确认编辑".into());
    }
    let context_versions = current_context_versions(db, &document.work_id)?;
    // 目标章序是检索上界（未来信息不过界）；文档缺 summaries 时退化为 0，
    // 意味着检索只可能命中同样无章序的条目，属于保守降级。
    let target_order = db
        .novel_document_summaries(&document.work_id)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|summary| summary.id == document.id)
        .map(|summary| summary.order_index)
        .unwrap_or(0);
    // 分层有界装配：替代整书拼接；必需层超预算即拒绝（不静默丢弃）。
    let assembled = assemble_context(
        db,
        &AssembleRequest {
            work_id: &document.work_id,
            target_document_id: &document.id,
            target_order,
            instruction: request,
            budget: Budget::balanced(DEFAULT_BUDGET_TOKENS),
            estimator: chinese_char_estimator(),
        },
    )?;
    let system = format!(
        "你是小说共写助手。以下人物卡与禁忌是用户已确认的硬约束，必须遵守。未决议题尚无答案：避开相关细节；若无法避开，应在试写中标明待用户决定，不可自行定为正史。不要把未确认试写、被否决桥段或模型猜测当成正史。{output_rule}
<confirmed_constraints>{constraints}
</confirmed_constraints>
<open_questions>{unresolved}</open_questions>",
        constraints = assembled.constraints_text,
        unresolved = assembled.unresolved_text,
    );
    let user = format!(
        "<confirmed_reference>{reference}
</confirmed_reference>
<target_document id=\"{}\" title=\"{}\" />
<request>{request}</request>",
        document.id, document.title,
        reference = assembled.reference_text,
    );
    let prepared = llm::assemble_chat(
        gate,
        llm::ChatRequest {
            space: llm::Space::Novel,
            messages: vec![llm::Message::system(system), llm::Message::user(user)],
            model: None,
            max_tokens: Some(4096),
            temperature: Some(0.7),
            tools: None,
        },
        default_model,
    )
    .map_err(|e| e.to_string())?;
    Ok(GenerationPlan {
        document_id: document.id,
        work_id: document.work_id,
        base_version_id: document.head_version_id,
        context_versions,
        prepared,
        manifest: Some(assembled.manifest),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use paraselene_memory_core::{Database, DraftOrigin, NovelKind};

    #[test]
    fn 只注入本作品已确认内容_人物卡是硬约束() {
        let db = Database::open_in_memory().unwrap();
        let a = db.create_work("甲").unwrap();
        let b = db.create_work("乙").unwrap();
        let card = db
            .create_novel_document(&a.id, NovelKind::Character, "主角")
            .unwrap();
        let chapter = db
            .create_novel_document(&a.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let other = db
            .create_novel_document(&b.id, NovelKind::Character, "乙角色")
            .unwrap();
        let accepted = db
            .create_novel_draft(&card.id, "主角不会杀人", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&accepted.id).unwrap();
        db.create_novel_draft(&card.id, "被否决的主角会杀人", DraftOrigin::Ai)
            .unwrap();
        db.create_novel_draft(&chapter.id, "未确认桥段", DraftOrigin::Ai)
            .unwrap();
        let foreign = db
            .create_novel_draft(&other.id, "乙作品秘密", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&foreign.id).unwrap();
        let plan =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "写一小段", "model").unwrap();
        let text = format!("{:?}", plan.prepared.messages);
        assert!(text.contains("主角不会杀人"));
        assert!(!text.contains("被否决的主角会杀人"));
        assert!(!text.contains("未确认桥段"));
        assert!(!text.contains("乙作品秘密"));
        assert_eq!(plan.prepared.space, llm::Space::Novel);
    }

    #[test]
    fn 待决议题仅来自当前确认版本_进入预览并随回滚消失() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let setting = db
            .create_novel_document(&work.id, NovelKind::World, "城市")
            .unwrap();
        let pending = db
            .create_novel_draft(&setting.id, "城市名字没想好", DraftOrigin::User)
            .unwrap();
        assert!(open_questions(&db.novel_canonical_entries(&work.id).unwrap()).is_empty());
        let first = db.accept_novel_draft(&pending.id).unwrap();
        let entries = db.novel_canonical_entries(&work.id).unwrap();
        assert_eq!(open_questions(&entries).len(), 1);
        let preview =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "继续", "model").unwrap();
        let text = format!("{:?}", preview.prepared.messages);
        assert!(text.contains("<open_questions>"));
        assert!(text.contains("城市名字没想好"));
        assert!(text.contains("避开相关细节"));
        let resolved = db
            .create_novel_draft(&setting.id, "城市叫月港", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&resolved.id).unwrap();
        assert!(open_questions(&db.novel_canonical_entries(&work.id).unwrap()).is_empty());
        db.rollback_novel_document(
            &setting.id,
            first.head_version_id.as_deref().unwrap(),
            db.get_novel_document(&setting.id)
                .unwrap()
                .unwrap()
                .head_version_id
                .as_deref(),
        )
        .unwrap();
        assert_eq!(
            open_questions(&db.novel_canonical_entries(&work.id).unwrap()).len(),
            1
        );
    }

    #[test]
    fn 人物卡未定行不会作为硬约束注入() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let card = db
            .create_novel_document(&work.id, NovelKind::Character, "主角")
            .unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let draft = db
            .create_novel_draft(&card.id, "勇敢\n关系没想好", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        let preview =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "继续", "model").unwrap();
        let system = preview.prepared.messages[0].content.as_deref().unwrap();
        let constraints = system
            .split("<confirmed_constraints>")
            .nth(1)
            .unwrap()
            .split("</confirmed_constraints>")
            .next()
            .unwrap();
        assert!(constraints.contains("勇敢"));
        assert!(!constraints.contains("关系没想好"));
        assert!(system.contains("关系没想好"));
    }

    #[test]
    fn 云开关在组装时阻断() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let gate = llm::SpaceSwitch {
            novel: false,
            ..Default::default()
        };
        assert!(prepare_generation(&db, &gate, &chapter.id, "继续", "model").is_err());
    }

    #[test]
    fn 其他已确认设定变化使预览版本签名失效() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let card = db
            .create_novel_document(&work.id, NovelKind::Character, "主角")
            .unwrap();
        let first = db
            .create_novel_draft(&card.id, "不杀人", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&first.id).unwrap();
        let preview =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "继续", "model").unwrap();
        db.create_novel_draft(&card.id, "未确认变化", DraftOrigin::User)
            .unwrap();
        assert_eq!(
            preview.context_versions,
            current_context_versions(&db, &work.id).unwrap()
        );
        let update = db
            .create_novel_draft(&card.id, "仍不杀人", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&update.id).unwrap();
        assert_ne!(
            preview.context_versions,
            current_context_versions(&db, &work.id).unwrap()
        );
    }

    #[test]
    fn 选段预览绑定当前正稿且仅引用确认设定() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let first = db
            .create_novel_draft(&chapter.id, "她说：“走吧。”", DraftOrigin::User)
            .unwrap();
        let confirmed = db.accept_novel_draft(&first.id).unwrap();
        let selection = EditSelection {
            mode: crate::EditMode::DialogueOnly,
            start_char: 0,
            end_char: "她说：“走吧。”".chars().count(),
            selected_text: "她说：“走吧。”".into(),
        };
        let (plan, _) = prepare_edit(
            &db,
            &llm::AllowAll,
            &chapter.id,
            selection,
            "更温和",
            "model",
        )
        .unwrap();
        assert_eq!(plan.base_version_id, confirmed.head_version_id);
        let preview = format!("{:?}", plan.prepared.messages);
        assert!(preview.contains("只改"));
        assert!(preview.contains("更温和"));
    }
}
