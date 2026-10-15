//! 旧想法候选与用户确认（G07/G08）。
//!
//! 候选只读取用户已导入的消息，不写入记忆。只有明确调用 `confirm_idea` 或
//! `confirm_idea_status` 才会修改 idea 空间；候选文本始终可回到精确消息位置。

use rusqlite::{params, OptionalExtension};
use std::collections::HashSet;

use crate::error::{Error, Result};
use crate::spaces::{validate_status_transition, Memory, Space, Work, IDEA_STATUSES};
use crate::storage::db::Database;

/// 旧想法的语言线索表：用户消息中出现这些短语才可能构成候选。
///
/// 刻意只收录「明确表达意图」的高精度短语，宁缺毋滥——误报候选会打断用户；
/// 表内短语同时也是 trigram FTS 查询词，因此每条都必须 ≥3 个字符（trigram 索引的硬边界）。
const IDEA_CUES: &[&str] = &[
    "我想做一个",
    "有个想法",
    "想写一个",
    "我想试试",
    "我想做",
    "我想写",
    "设计一个",
    "开发一个",
    "做一个",
    "可以做",
];

/// 尚未保存的原文候选；`excerpt` 是原文的连续片段，不是模型总结。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaCandidate {
    pub session_id: String,
    pub message_seq: i64,
    pub excerpt: String,
    /// 点击“查看原文”时展示，永不发送给云模型。
    pub source_text: String,
    pub session_title: Option<String>,
    pub source: String,
    pub timestamp: Option<String>,
}

/// 一条想法的确切出处。原消息若已从索引移除，`text` 为 None，保留已存短引用。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaSource {
    pub session_id: String,
    pub message_seq: i64,
    pub text: Option<String>,
    pub anchor: Option<String>,
    pub session_title: Option<String>,
    pub source: Option<String>,
    pub timestamp: Option<String>,
}

/// 用户从旧想法显式创建的目标；小说目标同时创建作品作用域。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConvertedIdea {
    pub idea: Memory,
    pub target: Memory,
    pub work: Option<Work>,
}

/// 内部结构：旧想法 `payload.convertedTo` 字段的序列化形态。
/// 保存转换目标的指针，供「重新打开目标」时校验空间 / 作品作用域未被篡改。
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConvertedTargetRef {
    space: String,
    memory_id: String,
    work_id: Option<String>,
}

/// 从 payload JSON 中解析转换目标引用；JSON 结构损坏时报 Parse 错误而不是静默丢弃，
/// 否则用户会在「目标已丢失」与「数据损坏」之间得到误导性的 None。
fn converted_target_ref(payload: Option<&serde_json::Value>) -> Result<Option<ConvertedTargetRef>> {
    payload
        .and_then(|value| value.get("convertedTo"))
        .map(|value| {
            serde_json::from_value(value.clone())
                .map_err(|_| Error::parse("旧想法关联的目标信息损坏"))
        })
        .transpose()
}

/// 内部行视图：出处原消息及其所在会话的展示字段。
struct SourceMessage {
    text: String,
    session_title: Option<String>,
    source: String,
    timestamp: Option<String>,
}

/// 按（session_id, message_seq）回读原始用户消息。
///
/// 查询条件里限定 `role = 'user' AND kind = 'message' AND text IS NOT NULL` 是刻意的：
/// 助手消息、工具调用不能冒充用户想法；原文被删时返回 None（调用方降级为短引用）。
fn source_message(
    db: &Database,
    session_id: &str,
    message_seq: i64,
) -> Result<Option<SourceMessage>> {
    db.with_conn(|conn| {
        Ok(conn
            .query_row(
                "SELECT m.text, s.title, s.source, m.timestamp
             FROM messages m JOIN sessions s ON s.id = m.session_id
             WHERE m.session_id = ?1 AND m.sequence = ?2
               AND m.role = 'user' AND m.kind = 'message' AND m.text IS NOT NULL",
                params![session_id, message_seq],
                |r| {
                    Ok(SourceMessage {
                        text: r.get(0)?,
                        session_title: r.get(1)?,
                        source: r.get(2)?,
                        timestamp: r.get(3)?,
                    })
                },
            )
            .optional()?)
    })
}

/// 截取以 cue 为中心的前后文片段（按字符数，非字节——中文不能按字节切）。
/// `start` 最多前移 24 字，给前文留一点语境；找不到 cue 时从头取。
fn excerpt_around(text: &str, cue: &str, limit: usize) -> String {
    let byte_index = text.find(cue).unwrap_or(0);
    let char_index = text[..byte_index].chars().count();
    let start = char_index.saturating_sub(24);
    text.chars()
        .skip(start)
        .take(limit)
        .collect::<String>()
        .trim()
        .to_string()
}

impl Database {
    /// 从已导入的用户消息中找一条待确认候选；无匹配时返回 None，不编造。
    /// 只在显式调用时检索，闲置时没有扫描或模型请求。
    pub fn suggest_old_idea(&self, skip: u32) -> Result<Option<IdeaCandidate>> {
        if skip > 100 {
            return Err(Error::parse("一次最多翻阅 100 条候选"));
        }
        let mut seen = HashSet::new();
        let mut remaining = skip;
        for cue in IDEA_CUES {
            // 这里查精确短语，而不是 G05 的宽松 n-gram OR；候选必须真的含这句原文。
            let candidates = self.with_conn(|conn| {
                let mut stmt = conn.prepare_cached(
                    "SELECT m.session_id, m.sequence, m.text, s.title, s.source, m.timestamp
                     FROM message_fts_trigram
                     JOIN messages m ON m.rowid = message_fts_trigram.rowid
                     JOIN sessions s ON s.id = m.session_id
                     WHERE message_fts_trigram MATCH ?1 AND m.role = 'user' AND m.kind = 'message'
                       AND NOT EXISTS (
                         SELECT 1 FROM memory_sources ms JOIN memories mem ON mem.id = ms.memory_id
                         WHERE ms.session_id = m.session_id AND ms.message_seq = m.sequence
                           AND mem.space = 'idea' AND mem.deleted_at IS NULL
                       )
                     ORDER BY rank, m.rowid LIMIT ?2",
                )?;
                let rows = stmt
                    .query_map(params![format!("\"{cue}\""), i64::from(skip) + 1], |r| {
                        Ok((
                            r.get::<_, String>(0)?,
                            r.get::<_, i64>(1)?,
                            r.get::<_, String>(2)?,
                            r.get::<_, Option<String>>(3)?,
                            r.get::<_, String>(4)?,
                            r.get::<_, Option<String>>(5)?,
                        ))
                    })?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                Ok(rows)
            })?;
            for (session_id, message_seq, text, session_title, source, timestamp) in candidates {
                if !text.contains(cue) {
                    continue;
                }
                if !seen.insert((session_id.clone(), message_seq)) {
                    continue;
                }
                if remaining > 0 {
                    remaining -= 1;
                    continue;
                }
                return Ok(Some(IdeaCandidate {
                    session_id,
                    message_seq,
                    excerpt: excerpt_around(&text, cue, 180),
                    source_text: text,
                    session_title,
                    source,
                    timestamp,
                }));
            }
        }
        Ok(None)
    }

    /// 用户确认候选后，以一笔事务同时保存状态和精确出处。
    /// `status` 是用户点选的五种状态之一；服务端重读原消息，不相信前端片段。
    ///
    /// 幂等性：同一 (session_id, message_seq) 已存在未删除的 idea 记忆时拒绝重复确认；
    /// 原文在确认瞬间被删则报 NotFound，保证出处链永不断裂。
    pub fn confirm_idea(
        &self,
        session_id: &str,
        message_seq: i64,
        title: &str,
        status: &str,
    ) -> Result<Memory> {
        let title = title.trim();
        if title.is_empty() || title.chars().count() > 80 {
            return Err(Error::parse("想法标题须为 1–80 字"));
        }
        if !IDEA_STATUSES.contains(&status) {
            return Err(Error::parse("无法识别的想法状态"));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();
        self.with_tx(|tx| {
            let text: String = tx
                .query_row(
                    "SELECT text FROM messages
                 WHERE session_id = ?1 AND sequence = ?2
                   AND role = 'user' AND kind = 'message' AND text IS NOT NULL",
                    params![session_id, message_seq],
                    |r| r.get(0),
                )
                .optional()?
                .ok_or_else(|| Error::not_found("原始用户消息不存在"))?;
            if text.trim().is_empty() {
                return Err(Error::parse("原始用户消息为空"));
            }
            let exists: bool = tx.query_row(
                "SELECT EXISTS(
                   SELECT 1 FROM memory_sources ms JOIN memories mem ON mem.id = ms.memory_id
                   WHERE ms.session_id = ?1 AND ms.message_seq = ?2
                     AND mem.space = 'idea' AND mem.deleted_at IS NULL
                 )",
                params![session_id, message_seq],
                |r| r.get(0),
            )?;
            if exists {
                return Err(Error::parse("这条原文已保存为旧想法"));
            }
            let cue = IDEA_CUES
                .iter()
                .find(|cue| text.contains(**cue))
                .copied()
                .unwrap_or("");
            let mut anchor = excerpt_around(&text, cue, 120);
            if anchor.is_empty() {
                anchor = text.trim().chars().take(120).collect();
            }
            tx.execute(
                "INSERT INTO memories (id, space, kind, title, status, created_at, updated_at)
                 VALUES (?1, 'idea', 'old_idea', ?2, ?3, ?4, ?4)",
                params![id, title, status, now],
            )?;
            tx.execute(
                "INSERT INTO memory_sources (memory_id, session_id, message_seq, anchor)
                 VALUES (?1, ?2, ?3, ?4)",
                params![id, session_id, message_seq, anchor],
            )?;
            Ok(())
        })?;
        let saved = self
            .get_memory(&id)?
            .ok_or_else(|| Error::not_found("想法保存后未找到"))?;
        debug_assert_eq!(saved.space, Space::Idea.as_str());
        Ok(saved)
    }

    /// 用户确认一次状态迁移；`expected_status` 防止旧卡片覆盖较新的决定。
    pub fn confirm_idea_status(
        &self,
        id: &str,
        expected_status: &str,
        status: &str,
    ) -> Result<Memory> {
        self.with_tx(|tx| {
            let current: (String, String) = tx
                .query_row(
                    "SELECT space, status FROM memories WHERE id = ?1 AND deleted_at IS NULL",
                    params![id],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?
                .ok_or_else(|| Error::not_found("旧想法不存在或已删除"))?;
            if current.0 != Space::Idea.as_str() {
                return Err(Error::parse("只能更改旧想法状态"));
            }
            if current.1 != expected_status {
                return Err(Error::parse("状态已变化，请刷新后再确认"));
            }
            validate_status_transition(&current.1, status)?;
            tx.execute(
                "UPDATE memories SET status = ?2, updated_at = ?3 WHERE id = ?1",
                params![id, status, chrono::Utc::now().to_rfc3339()],
            )?;
            Ok(())
        })?;
        self.get_memory(id)?
            .ok_or_else(|| Error::not_found("旧想法更新后未找到"))
    }

    /// 用户确认将旧想法发展到另一个空间。作品、目标记忆、出处和用户链接同事务创建。
    /// 不接受自动调用；唯一产品入口是“确认创建”按钮。
    ///
    /// 三类目标空间的 kind 固定映射（novel→inspiration / learning→goal / personal→note），
    /// 只有 novel 需要额外建 `works` 作用域。`convertedTo` 指针写入 idea 的 payload，
    /// 是「已转换」的事实标记——重复转换靠它拦截。
    pub fn convert_idea(&self, idea_id: &str, target_space: &str) -> Result<ConvertedIdea> {
        let (space, kind) = match target_space {
            "novel" => (Space::Novel, "inspiration"),
            "learning" => (Space::Learning, "goal"),
            "personal" => (Space::Personal, "note"),
            _ => return Err(Error::parse("旧想法只能转成小说项目、学习目标或普通记忆卡")),
        };
        let now = chrono::Utc::now().to_rfc3339();
        let target_id = uuid::Uuid::new_v4().to_string();
        let work_id = (space == Space::Novel).then(|| uuid::Uuid::new_v4().to_string());
        self.with_tx(|tx| {
            let (title, raw_payload): (String, Option<String>) = tx.query_row(
                "SELECT title, payload FROM memories WHERE id = ?1 AND space = 'idea' AND deleted_at IS NULL",
                [idea_id], |r| Ok((r.get(0)?, r.get(1)?)),
            ).optional()?.ok_or_else(|| Error::not_found("旧想法不存在或已删除"))?;
            let mut payload = match raw_payload {
                Some(raw) => serde_json::from_str::<serde_json::Value>(&raw)
                    .map_err(|_| Error::parse("旧想法的项目信息损坏"))?,
                None => serde_json::json!({}),
            };
            let fields = payload.as_object_mut().ok_or_else(|| Error::parse("旧想法的项目信息格式错误"))?;
            if fields.contains_key("convertedTo") {
                return Err(Error::parse("这条旧想法已经转为项目或记忆"));
            }
            let source: (String, Option<i64>, Option<String>) = tx.query_row(
                "SELECT session_id, message_seq, anchor FROM memory_sources WHERE memory_id = ?1 ORDER BY message_seq IS NULL, message_seq LIMIT 1",
                [idea_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            ).optional()?.ok_or_else(|| Error::not_found("旧想法没有可追溯的出处"))?;
            if let Some(work_id) = &work_id {
                tx.execute("INSERT INTO works (id, space, title, created_at) VALUES (?1, 'novel', ?2, ?3)",
                    params![work_id, title, now])?;
            }
            tx.execute(
                "INSERT INTO memories (id, space, work_id, kind, title, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                params![target_id, space.as_str(), work_id, kind, title, now],
            )?;
            tx.execute(
                "INSERT INTO memory_sources (memory_id, session_id, message_seq, anchor) VALUES (?1, ?2, ?3, ?4)",
                params![target_id, source.0, source.1, source.2],
            )?;
            tx.execute(
                "INSERT INTO memory_links (from_id, to_id, actor, created_at) VALUES (?1, ?2, 'user', ?3)",
                params![target_id, idea_id, now],
            )?;
            fields.insert("convertedTo".into(), serde_json::json!({
                "space": space.as_str(), "memoryId": target_id, "workId": work_id,
            }));
            tx.execute("UPDATE memories SET payload = ?2, updated_at = ?3 WHERE id = ?1",
                params![idea_id, payload.to_string(), now])?;
            Ok(())
        })?;
        let idea = self
            .get_memory(idea_id)?
            .ok_or_else(|| Error::not_found("转换后的旧想法不存在"))?;
        let target = self
            .get_memory(&target_id)?
            .ok_or_else(|| Error::not_found("目标记忆不存在"))?;
        let work = work_id.map(|id| Work {
            id,
            space: Space::Novel.as_str().to_string(),
            title: target.title.clone(),
            created_at: now,
        });
        Ok(ConvertedIdea { idea, target, work })
    }

    /// 重新打开从旧想法明确创建的目标；关联缺失时返回 None，损坏或跨空间关联报错。
    pub fn converted_target(&self, idea_id: &str) -> Result<Option<Memory>> {
        let idea = self
            .get_memory(idea_id)?
            .ok_or_else(|| Error::not_found("旧想法不存在或已删除"))?;
        if idea.space != Space::Idea.as_str() {
            return Err(Error::parse("只能从旧想法打开目标"));
        }
        let Some(reference) = converted_target_ref(idea.payload.as_ref())? else {
            return Ok(None);
        };
        let Some(target) = self.get_memory(&reference.memory_id)? else {
            return Ok(None);
        };
        if target.space != reference.space || target.work_id != reference.work_id {
            return Err(Error::parse("旧想法关联的目标与空间不一致"));
        }
        let linked = self.with_conn(|conn| {
            Ok(conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM memory_links WHERE from_id = ?1 AND to_id = ?2 AND actor = 'user')",
                params![target.id, idea_id], |row| row.get::<_, bool>(0),
            )?)
        })?;
        if !linked {
            return Err(Error::parse("旧想法关联的目标缺少用户确认记录"));
        }
        Ok(Some(target))
    }

    /// 只编辑从指定旧想法创建的目标。小说作品名与目标标题同事务更新，出处不变。
    pub fn update_converted_target(
        &self,
        idea_id: &str,
        expected_updated_at: &str,
        title: &str,
        summary: &str,
    ) -> Result<Memory> {
        let title = title.trim();
        let summary = summary.trim();
        if title.is_empty() || title.chars().count() > 80 {
            return Err(Error::parse("目标标题须为 1–80 字"));
        }
        if summary.chars().count() > 2_000 {
            return Err(Error::parse("目标笔记最多 2000 字"));
        }
        let target = self
            .converted_target(idea_id)?
            .ok_or_else(|| Error::not_found("旧想法尚未创建目标，或目标已删除"))?;
        let now = chrono::Utc::now().to_rfc3339();
        self.with_tx(|tx| {
            // 再次在事务里核对关联，避免旧页面覆盖被其他操作改掉的目标。
            let payload: Option<String> = tx.query_row(
                "SELECT payload FROM memories WHERE id = ?1 AND space = 'idea' AND deleted_at IS NULL",
                [idea_id], |row| row.get(0),
            ).optional()?.ok_or_else(|| Error::not_found("旧想法不存在或已删除"))?;
            let parsed = payload
                .as_deref()
                .map(serde_json::from_str::<serde_json::Value>)
                .transpose()
                .map_err(|_| Error::parse("旧想法的目标信息损坏"))?;
            let reference = converted_target_ref(parsed.as_ref())?
                .ok_or_else(|| Error::not_found("旧想法尚未创建目标"))?;
            if reference.memory_id != target.id
                || reference.space != target.space
                || reference.work_id != target.work_id
            {
                return Err(Error::parse("目标关联已变化，请重新打开"));
            }
            let changed = tx.execute(
                "UPDATE memories SET title = ?2, summary = ?3, updated_at = ?4
                 WHERE id = ?1 AND space = ?5 AND updated_at = ?6 AND deleted_at IS NULL",
                params![target.id, title, summary, now, target.space, expected_updated_at],
            )?;
            if changed != 1 {
                return Err(Error::parse("目标内容已变化，请重新打开后再保存"));
            }
            if let Some(work_id) = &target.work_id {
                tx.execute("UPDATE works SET title = ?2 WHERE id = ?1 AND space = 'novel'",
                    params![work_id, title])?;
            }
            Ok(())
        })?;
        self.get_memory(&target.id)?
            .ok_or_else(|| Error::not_found("更新后的目标不存在"))
    }

    /// 用户明确决定是否允许未来主动提起这条想法；当前版本无后台提醒。
    pub fn set_idea_reminder(&self, idea_id: &str, never: bool) -> Result<Memory> {
        self.with_tx(|tx| {
            let exists: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM memories WHERE id = ?1 AND space = 'idea' AND deleted_at IS NULL)",
                [idea_id], |r| r.get(0),
            )?;
            if !exists { return Err(Error::not_found("旧想法不存在或已删除")); }
            let mode = if never { "never" } else { "manual" };
            tx.execute(
                "UPDATE memories SET reminder_pref = ?2, updated_at = ?3 WHERE id = ?1",
                params![idea_id, serde_json::json!({"mode": mode}).to_string(), chrono::Utc::now().to_rfc3339()],
            )?;
            Ok(())
        })?;
        self.get_memory(idea_id)?
            .ok_or_else(|| Error::not_found("提醒设置后未找到旧想法"))
    }

    /// 展开保存的旧想法出处。原消息消失时只返回当时存的 anchor，并标明 text 缺失。
    pub fn idea_source(&self, idea_id: &str) -> Result<Option<IdeaSource>> {
        let Some(memory) = self.get_memory(idea_id)? else {
            return Ok(None);
        };
        if memory.space != Space::Idea.as_str() {
            return Err(Error::parse("只能查看旧想法出处"));
        }
        let Some(link) = self.get_sources(idea_id)?.into_iter().next() else {
            return Ok(None);
        };
        let message = match link.message_seq {
            Some(seq) => source_message(self, &link.session_id, seq)?,
            None => None,
        };
        Ok(Some(IdeaSource {
            session_id: link.session_id,
            message_seq: link.message_seq.unwrap_or(-1),
            text: message.as_ref().map(|m| m.text.clone()),
            anchor: link.anchor,
            session_title: message.as_ref().and_then(|m| m.session_title.clone()),
            source: message.as_ref().map(|m| m.source.clone()),
            timestamp: message.and_then(|m| m.timestamp),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{MessageRow, SessionStub};

    fn seed() -> Database {
        let db = Database::open_in_memory().unwrap();
        db.upsert_session_stub(&SessionStub {
            id: "chatgpt:idea".into(),
            source: "chatgpt".into(),
            external_id: "idea".into(),
            source_root: None,
            primary_file: None,
        })
        .unwrap();
        db.insert_messages(&[
            MessageRow {
                id: "chatgpt:idea#0".into(),
                session_id: "chatgpt:idea".into(),
                sequence: 0,
                role: "user".into(),
                kind: "message".into(),
                text: Some("有个想法，把月相做成一只会睡觉的桌宠。".into()),
                tool_name: None,
                timestamp: None,
                raw: None,
            },
            MessageRow {
                id: "chatgpt:idea#1".into(),
                session_id: "chatgpt:idea".into(),
                sequence: 1,
                role: "assistant".into(),
                kind: "message".into(),
                text: Some("我想做一个完全不同的虚构方案。".into()),
                tool_name: None,
                timestamp: None,
                raw: None,
            },
        ])
        .unwrap();
        db
    }

    #[test]
    fn 候选不落库_确认后出处可回到原消息() {
        let db = seed();
        let candidate = db.suggest_old_idea(0).unwrap().unwrap();
        assert_eq!(candidate.message_seq, 0, "助手的话不能作为用户旧想法");
        assert!(candidate.excerpt.contains("月相"));
        assert_eq!(
            candidate.source_text,
            "有个想法，把月相做成一只会睡觉的桌宠。"
        );
        assert!(db.list_memories(Space::Idea, None).unwrap().is_empty());
        let saved = db
            .confirm_idea(
                &candidate.session_id,
                candidate.message_seq,
                "月相桌宠",
                "liked",
            )
            .unwrap();
        assert_eq!(saved.status.as_deref(), Some("liked"));
        let source = db.idea_source(&saved.id).unwrap().unwrap();
        assert_eq!(source.message_seq, 0);
        assert_eq!(
            source.text.as_deref(),
            Some("有个想法，把月相做成一只会睡觉的桌宠。")
        );
        assert!(
            db.suggest_old_idea(0).unwrap().is_none(),
            "保存后不能再次推荐同一条"
        );
        assert!(db
            .confirm_idea(&candidate.session_id, 0, "重复", "liked")
            .is_err());
    }

    #[test]
    fn 空库不编造_确认拒绝助手及非法状态() {
        let empty = Database::open_in_memory().unwrap();
        assert!(empty.suggest_old_idea(0).unwrap().is_none());
        let db = seed();
        assert!(db
            .confirm_idea("chatgpt:idea", 1, "助手说的", "liked")
            .is_err());
        assert!(db
            .confirm_idea("chatgpt:idea", 0, "无效", "invented")
            .is_err());
        assert!(db.list_memories(Space::Idea, None).unwrap().is_empty());
        db.with_conn(|conn| {
            conn.execute("DELETE FROM messages WHERE role = 'user'", [])?;
            Ok(())
        })
        .unwrap();
        assert!(
            db.suggest_old_idea(0).unwrap().is_none(),
            "助手文本不能冒充用户候选"
        );
    }

    #[test]
    fn 原文移除后只报告保留的出处短引用() {
        let db = seed();
        let idea = db
            .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
            .unwrap();
        db.with_conn(|conn| {
            conn.execute("DELETE FROM messages WHERE session_id = 'chatgpt:idea'", [])?;
            Ok(())
        })
        .unwrap();
        let source = db.idea_source(&idea.id).unwrap().unwrap();
        assert!(source.text.is_none(), "已删除的原文不能由短引用伪装出来");
        assert!(source.anchor.as_deref().unwrap_or("").contains("月相"));
    }

    #[test]
    fn 翻阅候选不会反复给出同一条() {
        let db = seed();
        db.insert_messages(&[MessageRow {
            id: "chatgpt:idea#2".into(),
            session_id: "chatgpt:idea".into(),
            sequence: 2,
            role: "user".into(),
            kind: "message".into(),
            text: Some("我想做一只会打招呼的小兽。".into()),
            tool_name: None,
            timestamp: None,
            raw: None,
        }])
        .unwrap();
        let first = db.suggest_old_idea(0).unwrap().unwrap();
        let second = db.suggest_old_idea(1).unwrap().unwrap();
        assert_ne!(
            (first.session_id, first.message_seq),
            (second.session_id, second.message_seq)
        );
        assert!(db.suggest_old_idea(2).unwrap().is_none());
        assert!(db.list_memories(Space::Idea, None).unwrap().is_empty());
    }

    #[test]
    fn 状态只经确认迁移_旧状态无法覆盖() {
        let db = seed();
        let idea = db
            .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
            .unwrap();
        let started = db
            .confirm_idea_status(&idea.id, "liked", "started")
            .unwrap();
        assert_eq!(started.status.as_deref(), Some("started"));
        assert!(db.confirm_idea_status(&idea.id, "liked", "done").is_err());
        assert!(db
            .confirm_idea_status(&idea.id, "started", "liked")
            .is_err());
        let done = db.confirm_idea_status(&idea.id, "started", "done").unwrap();
        assert_eq!(done.status.as_deref(), Some("done"));
    }

    #[test]
    fn 用户确认后才跨空间创建小说作品_保留出处且不重复() {
        let db = seed();
        let idea = db
            .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
            .unwrap();
        assert!(db.list_works().unwrap().is_empty());
        assert!(db.list_memories(Space::Novel, None).unwrap().is_empty());
        let converted = db.convert_idea(&idea.id, "novel").unwrap();
        let work = converted.work.unwrap();
        assert_eq!(converted.target.space, "novel");
        assert_eq!(converted.target.work_id.as_deref(), Some(work.id.as_str()));
        assert_eq!(
            db.get_sources(&converted.target.id).unwrap()[0].message_seq,
            Some(0)
        );
        let links = db.get_links(&converted.target.id).unwrap();
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].to_id, idea.id);
        assert_eq!(links[0].actor, "user");
        assert!(db.convert_idea(&idea.id, "novel").is_err());
        assert_eq!(db.list_works().unwrap().len(), 1);
        assert_eq!(db.list_memories(Space::Novel, None).unwrap().len(), 1);
    }

    #[test]
    fn 其他目标空间与免打扰由用户显式设置() {
        for (target, space) in [("learning", Space::Learning), ("personal", Space::Personal)] {
            let db = seed();
            let idea = db
                .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
                .unwrap();
            assert!(db.convert_idea(&idea.id, "unsupported").is_err());
            let converted = db.convert_idea(&idea.id, target).unwrap();
            assert_eq!(converted.target.space, space.as_str());
            assert!(converted.work.is_none());
            assert_eq!(db.list_memories(space, None).unwrap().len(), 1);
            let never = db.set_idea_reminder(&idea.id, true).unwrap();
            assert_eq!(never.reminder_pref.unwrap()["mode"], "never");
            let manual = db.set_idea_reminder(&idea.id, false).unwrap();
            assert_eq!(manual.reminder_pref.unwrap()["mode"], "manual");
            assert!(db.set_idea_reminder(&converted.target.id, true).is_err());
        }
    }

    #[test]
    fn 已转换目标可重新打开与编辑_作品名同步且出处不变() {
        let db = seed();
        let idea = db
            .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
            .unwrap();
        let converted = db.convert_idea(&idea.id, "novel").unwrap();
        let before_source = db.get_sources(&converted.target.id).unwrap();
        let reopened = db.converted_target(&idea.id).unwrap().unwrap();
        assert_eq!(reopened.id, converted.target.id);
        let updated = db
            .update_converted_target(
                &idea.id,
                &reopened.updated_at,
                " 月相故事 ",
                " 第一幕：小兽醒来。 ",
            )
            .unwrap();
        assert_eq!(updated.title, "月相故事");
        assert_eq!(updated.summary.as_deref(), Some("第一幕：小兽醒来。"));
        assert_eq!(db.list_works().unwrap()[0].title, "月相故事");
        assert_eq!(
            db.converted_target(&idea.id).unwrap().unwrap().summary,
            updated.summary
        );
        assert_eq!(
            db.get_sources(&updated.id).unwrap()[0].session_id,
            before_source[0].session_id
        );
        assert_eq!(db.get_sources(&updated.id).unwrap()[0].message_seq, Some(0));
        assert_eq!(db.get_links(&updated.id).unwrap()[0].to_id, idea.id);
    }

    #[test]
    fn 目标编辑只能经已转换旧想法且校验长度与删除状态() {
        let db = seed();
        let idea = db
            .confirm_idea("chatgpt:idea", 0, "月相桌宠", "liked")
            .unwrap();
        assert!(db.converted_target(&idea.id).unwrap().is_none());
        assert!(db
            .update_converted_target(&idea.id, "unused", "错误", "笔记")
            .is_err());
        let converted = db.convert_idea(&idea.id, "learning").unwrap();
        assert!(db.converted_target(&converted.target.id).is_err());
        assert!(db
            .update_converted_target(&idea.id, &converted.target.updated_at, " ", "笔记")
            .is_err());
        assert!(db
            .update_converted_target(
                &idea.id,
                &converted.target.updated_at,
                "目标",
                &"字".repeat(2001)
            )
            .is_err());
        let updated = db
            .update_converted_target(
                &idea.id,
                &converted.target.updated_at,
                "Python 练习",
                "先写一个函数",
            )
            .unwrap();
        assert_eq!(updated.space, "learning");
        assert_eq!(updated.summary.as_deref(), Some("先写一个函数"));
        assert!(db
            .update_converted_target(
                &idea.id,
                &converted.target.updated_at,
                "旧页覆盖",
                "不应保存"
            )
            .is_err());
        assert_eq!(
            db.converted_target(&idea.id).unwrap().unwrap().title,
            "Python 练习"
        );
        db.soft_delete_memory(&updated.id).unwrap();
        assert!(db.converted_target(&idea.id).unwrap().is_none());
        assert!(db
            .update_converted_target(&idea.id, &updated.updated_at, "目标", "笔记")
            .is_err());
    }
}
