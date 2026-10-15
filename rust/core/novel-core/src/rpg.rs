//! 两阶段跑团：场景提案与玩家回复。临时场景只扮演世界与编剧，
//! 不替玩家决定主角内心/行动；场景与未确认互动不进下一章上下文（契约见测试）。

use paraselene_llm_core as llm;
use paraselene_memory_core::Database;
use serde::{Deserialize, Serialize};

use crate::generation::prepare_with_request;

/// 跑团场景的结构化内容：场景描述 + 2–3 个可选走向。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpgSceneContent {
    pub scene: String,
    pub options: Vec<String>,
}

/// 场景只扮演世界与编剧，不代替玩家决定主角的内心或行动。
pub fn prepare_rpg_scene(
    db: &Database,
    gate: &dyn llm::CloudGate,
    document_id: &str,
    direction: &str,
    default_model: &str,
) -> Result<crate::GenerationPlan, String> {
    let direction = direction.trim();
    if direction.is_empty() || direction.chars().count() > 500 {
        return Err("场景方向须为 1–500 个字".into());
    }
    prepare_with_request(db, gate, document_id, direction,
        "你只扮演世界与编剧：给出当前场景和 2–3 个可选走向，不替主角决定内心或行动，等待玩家回答。只输出 JSON 对象：{\"scene\":\"不超过1200字的场景\",\"options\":[\"选项一\",\"选项二\"]}；每个选项不超过80字。不要使用 Markdown 代码块。此场景尚非正稿。",
        default_model)
}

/// 解析并校验模型返回的场景 JSON：场景 1–1200 字、选项 2–3 个且每个
/// 不超过 80 字。任何不符都视为模型未遵守输出契约，拒绝保存并要求重试。
pub fn parse_rpg_scene(body: &str) -> Result<RpgSceneContent, String> {
    let parsed: RpgSceneContent = serde_json::from_str(body.trim())
        .map_err(|_| "场景回复不是指定的 JSON 格式，未保存；请重试".to_string())?;
    if parsed.scene.trim().is_empty()
        || parsed.scene.chars().count() > 1200
        || !(2..=3).contains(&parsed.options.len())
        || parsed
            .options
            .iter()
            .any(|option| option.trim().is_empty() || option.chars().count() > 80)
    {
        return Err("场景或选项超出格式限制，未保存；请重试".into());
    }
    Ok(parsed)
}

/// 玩家短回复被解释为主角内心/行动；临时场景不是确认史实。
pub fn prepare_rpg_response(
    db: &Database,
    gate: &dyn llm::CloudGate,
    document_id: &str,
    scene: &RpgSceneContent,
    player_reply: &str,
    default_model: &str,
) -> Result<crate::GenerationPlan, String> {
    let reply = player_reply.trim();
    if reply.is_empty() || reply.chars().count() > 300 {
        return Err("主角回复须为 1–300 个字".into());
    }
    let request = format!(
        "以下场景是本轮临时提案，尚未确认，不可作为其他章节的正史。你先前给出的场景和选项：{}\n玩家的短回复（即主角的内心或行动）：{}\n根据玩家选择，将这轮互动写成可审核的章节试写。",
        serde_json::to_string(scene).map_err(|e| e.to_string())?,
        serde_json::to_string(reply).map_err(|e| e.to_string())?,
    );
    prepare_with_request(db, gate, document_id, &request,
        "只输出章节试写正文，不输出选项或解释；玩家回复定义主角本轮内心/行动，不得擅自替换。结果只进入待确认试写。",
        default_model)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generation::prepare_generation;
    use paraselene_memory_core::{Database, DraftOrigin, NovelKind};

    #[test]
    fn 跑团场景格式与玩家回复的边界() {
        let scene =
            parse_rpg_scene(r#"{"scene":"雨夜抵达城门。","options":["敲门","绕路"]}"#).unwrap();
        assert_eq!(scene.options.len(), 2);
        assert!(parse_rpg_scene("```json\n{}\n```").is_err());
        assert!(parse_rpg_scene(r#"{"scene":"好","options":["仅一个"]}"#).is_err());
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let plan = prepare_rpg_response(
            &db,
            &llm::AllowAll,
            &chapter.id,
            &scene,
            "我先敲门",
            "model",
        )
        .unwrap();
        let text = format!("{:?}", plan.prepared.messages);
        assert!(text.contains("雨夜抵达城门"));
        assert!(text.contains("我先敲门"));
        assert!(text.contains("尚未确认"));
        assert!(
            prepare_rpg_response(&db, &llm::AllowAll, &chapter.id, &scene, "", "model").is_err()
        );
    }

    #[test]
    fn 跑团临时场景和玩家回复不污染下一章上下文() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let scene_plan =
            prepare_rpg_scene(&db, &llm::AllowAll, &chapter.id, "雨夜城门", "model").unwrap();
        assert!(format!("{:?}", scene_plan.prepared.messages).contains("不替主角决定"));
        let scene =
            parse_rpg_scene(r#"{"scene":"雨夜的城门关闭了。","options":["敲门","绕路"]}"#).unwrap();
        let reply_plan = prepare_rpg_response(
            &db,
            &llm::AllowAll,
            &chapter.id,
            &scene,
            "我轻轻敲门",
            "model",
        )
        .unwrap();
        let draft = db
            .create_novel_draft_at_context(
                &chapter.id,
                reply_plan.base_version_id.as_deref(),
                &reply_plan.context_versions,
                "她轻轻敲门。",
                DraftOrigin::Ai,
            )
            .unwrap();
        let next = prepare_generation(&db, &llm::AllowAll, &chapter.id, "敲门", "model").unwrap();
        let next_text = format!("{:?}", next.prepared.messages);
        assert!(!next_text.contains("城门关闭了"));
        assert!(!next_text.contains("她轻轻敲门"));
        db.accept_novel_draft(&draft.id).unwrap();
        let accepted =
            prepare_generation(&db, &llm::AllowAll, &chapter.id, "敲门", "model").unwrap();
        assert!(format!("{:?}", accepted.prepared.messages).contains("她轻轻敲门"));
    }
}
