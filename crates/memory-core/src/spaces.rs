//! 四空间用户确认层（Goal §4.2）：个人记忆 / 旧想法 / 小说记忆 / 学习记忆。
//!
//! 设计红线（Goal §4.2，不可走样）：
//! - 四空间是**叠加在原始导入会话之上的用户确认层**，原始 `messages` 表不动；
//! - **默认不互通（G06）**：`list_memories` 必须显式给 space，本 API 刻意不提供
//!   「查全部空间」的入口——全局视图若未来需要，必须作为显式新产品决策重新评审，
//!   而不是从查询参数里悄悄长出来；
//! - **跨空间引用必须由用户触发**：`memory_links` 只允许经 [`Database::link_memories`]
//!   写入（actor='user'），链接**单向可见**（只见 from 的出链，to 侧不自动出现反向），
//!   由 `四空间_链接单向可见` 测试固化；
//! - **小说角色的话永远不能当成用户个人经历**：novel 空间必须挂 `work_id`
//!   （DDL + API 双重强制），非 novel 空间禁止挂 `work_id`；
//! - 软删（`deleted_at`）后默认查询不可见（G17 依赖），不提供恢复入口（留待评审）。
//!
//! 出处链（G08/G17）：`memory_sources` 记录 记忆 → 会话 + 消息位置 + 短引用 anchor；
//! `session_id` 故意不加外键——出处要在会话被清理 / 重新导入后仍可展示。

use rusqlite::{params, OptionalExtension};
use serde_json::Value;

use crate::error::{Error, Result};
use crate::storage::db::Database;

/// 记忆空间（Goal §4.2 四空间）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Space {
    /// 个人记忆：用户明确说过、收藏或纠正的经历与偏好
    Personal,
    /// 旧想法：来源、状态、提醒偏好、是否已转项目
    Idea,
    /// 小说记忆：按作品隔离，区分设定 / 试写 / 确认稿
    Novel,
    /// 学习记忆：题目、代码、测试、薄弱点、用户认可的目标
    Learning,
}

impl Space {
    pub const ALL: &[Space] = &[Space::Personal, Space::Idea, Space::Novel, Space::Learning];

    pub const fn as_str(self) -> &'static str {
        match self {
            Space::Personal => "personal",
            Space::Idea => "idea",
            Space::Novel => "novel",
            Space::Learning => "learning",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "personal" => Some(Space::Personal),
            "idea" => Some(Space::Idea),
            "novel" => Some(Space::Novel),
            "learning" => Some(Space::Learning),
            _ => None,
        }
    }
}

/// idea 空间的状态机取值（其他空间必须为 NULL）。
pub const IDEA_STATUSES: &[&str] = &["liked", "started", "done", "shelved", "wrong"];

/// 合法的状态迁移（from → to）。同状态赋值视为幂等 no-op，不在此表。
///
/// liked → started → done 是主路径；任何进行中状态可 shelved / wrong；
/// shelved 可重新 started 或判 wrong；done / wrong 是终态。
const STATUS_TRANSITIONS: &[(&str, &str)] = &[
    ("liked", "started"),
    ("liked", "shelved"),
    ("liked", "wrong"),
    ("started", "done"),
    ("started", "shelved"),
    ("started", "wrong"),
    ("shelved", "started"),
    ("shelved", "wrong"),
];

/// 校验 idea 状态迁移，非法迁移报错（Goal：状态机必须显式）。
pub fn validate_status_transition(from: &str, to: &str) -> Result<()> {
    if from == to {
        return Ok(());
    }
    if STATUS_TRANSITIONS.contains(&(from, to)) {
        Ok(())
    } else {
        Err(Error::parse(format!("非法状态迁移: {from} → {to}")))
    }
}

/// 小说作品（novel 空间的作用域）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Work {
    pub id: String,
    pub space: String,
    pub title: String,
    pub created_at: String,
}

/// 四空间记忆。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Memory {
    pub id: String,
    pub space: String,
    pub work_id: Option<String>,
    pub kind: String,
    pub title: String,
    pub summary: Option<String>,
    pub status: Option<String>,
    pub reminder_pref: Option<Value>,
    pub payload: Option<Value>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}

/// 新建记忆的输入。
#[derive(Debug, Clone)]
pub struct NewMemory {
    pub space: Space,
    /// novel 空间必填（且必须存在）；其他空间必须为 None（DDL + API 双重强制）。
    pub work_id: Option<String>,
    pub kind: String,
    pub title: String,
    pub summary: Option<String>,
    /// 仅 idea 空间可用；None 时默认 `liked`。其他空间必须 None。
    pub status: Option<String>,
    pub reminder_pref: Option<Value>,
    pub payload: Option<Value>,
}

/// 更新记忆的输入（`None` = 不改动；`Some` = 整体替换该字段）。
/// `work_id` 与 `space` 不可变——空间作用域是隔离边界，不允许改挂。
#[derive(Debug, Clone, Default)]
pub struct UpdateMemory {
    pub kind: Option<String>,
    pub title: Option<String>,
    pub summary: Option<String>,
    pub status: Option<String>,
    pub reminder_pref: Option<Value>,
    pub payload: Option<Value>,
}

/// 出处链条目：记忆 → 会话 + 消息位置 + 短引用。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemorySource {
    pub memory_id: String,
    pub session_id: String,
    pub message_seq: Option<i64>,
    pub anchor: Option<String>,
}

/// 链接视图（from 的出链，附带 to 侧摘要；to 侧已软删的链接不出现）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoryLinkView {
    pub from_id: String,
    pub to_id: String,
    pub to_space: String,
    pub to_title: String,
    pub actor: String,
    pub created_at: String,
}

fn now() -> String {
    chrono::Utc::now().to_rfc3339()
}

fn parse_json_col(text: Option<String>) -> Option<Value> {
    text.and_then(|t| serde_json::from_str(&t).ok())
}

fn memory_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Memory> {
    Ok(Memory {
        id: row.get(0)?,
        space: row.get(1)?,
        work_id: row.get(2)?,
        kind: row.get(3)?,
        title: row.get(4)?,
        summary: row.get(5)?,
        status: row.get(6)?,
        reminder_pref: parse_json_col(row.get(7)?),
        payload: parse_json_col(row.get(8)?),
        created_at: row.get(9)?,
        updated_at: row.get(10)?,
        deleted_at: row.get(11)?,
    })
}

const MEMORY_COLUMNS: &str =
    "id, space, work_id, kind, title, summary, status, reminder_pref, payload, created_at, updated_at, deleted_at";

impl Database {
    // ------------------------------------------------------------------
    // 作品（novel 空间作用域）
    // ------------------------------------------------------------------

    /// 新建小说作品。
    pub fn create_work(&self, title: &str) -> Result<Work> {
        let title = title.trim();
        if title.is_empty() {
            return Err(Error::parse("作品标题不能为空"));
        }
        let work = Work {
            id: uuid::Uuid::new_v4().to_string(),
            space: "novel".to_string(),
            title: title.to_string(),
            created_at: now(),
        };
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO works (id, space, title, created_at) VALUES (?1, ?2, ?3, ?4)",
                params![work.id, work.space, work.title, work.created_at],
            )?;
            Ok(())
        })?;
        Ok(work)
    }

    /// 全部作品（按创建时间倒序）。作品只属于 novel 空间，无跨空间问题。
    pub fn list_works(&self) -> Result<Vec<Work>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, space, title, created_at FROM works ORDER BY created_at DESC",
            )?;
            let rows = stmt
                .query_map([], |r| {
                    Ok(Work {
                        id: r.get(0)?,
                        space: r.get(1)?,
                        title: r.get(2)?,
                        created_at: r.get(3)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    // ------------------------------------------------------------------
    // 记忆 CRUD（list 强制 space 过滤，无全空间入口——见模块文档红线）
    // ------------------------------------------------------------------

    /// 新建记忆。按空间强制校验 work_id / status 规则（错误信息比 DDL CHECK 更人话）。
    pub fn create_memory(&self, new: NewMemory) -> Result<Memory> {
        let title = new.title.trim();
        if title.is_empty() {
            return Err(Error::parse("记忆标题不能为空"));
        }
        let kind = new.kind.trim();
        if kind.is_empty() {
            return Err(Error::parse("记忆 kind 不能为空"));
        }
        // 作品作用域：novel 必填，其他空间禁止（Goal §4.2：小说按作品隔离）
        match new.space {
            Space::Novel => {
                let wid = new
                    .work_id
                    .as_deref()
                    .ok_or_else(|| Error::parse("novel 空间的记忆必须指定 work_id"))?;
                if wid.trim().is_empty() {
                    return Err(Error::parse("work_id 不能为空"));
                }
                self.work_exists(wid)?
                    .then_some(())
                    .ok_or_else(|| Error::not_found(format!("作品 {wid} 不存在")))?;
            }
            _ => {
                if new.work_id.is_some() {
                    return Err(Error::parse("只有 novel 空间的记忆可以挂 work_id"));
                }
            }
        }
        // 状态机仅 idea 空间
        let status = match new.space {
            Space::Idea => {
                let s = new.status.as_deref().unwrap_or("liked");
                if !IDEA_STATUSES.contains(&s) {
                    return Err(Error::parse(format!("无法识别的想法状态: {s}")));
                }
                Some(s.to_string())
            }
            _ => {
                if new.status.is_some() {
                    return Err(Error::parse("status 仅 idea 空间可用"));
                }
                None
            }
        };

        let memory = Memory {
            id: uuid::Uuid::new_v4().to_string(),
            space: new.space.as_str().to_string(),
            work_id: new.work_id,
            kind: kind.to_string(),
            title: title.to_string(),
            summary: new.summary,
            status,
            reminder_pref: new.reminder_pref,
            payload: new.payload,
            created_at: now(),
            updated_at: now(),
            deleted_at: None,
        };
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO memories (id, space, work_id, kind, title, summary, status, reminder_pref, payload, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![
                    memory.id,
                    memory.space,
                    memory.work_id,
                    memory.kind,
                    memory.title,
                    memory.summary,
                    memory.status,
                    memory.reminder_pref.as_ref().map(|v| v.to_string()),
                    memory.payload.as_ref().map(|v| v.to_string()),
                    memory.created_at,
                    memory.updated_at
                ],
            )?;
            Ok(())
        })?;
        Ok(memory)
    }

    fn work_exists(&self, id: &str) -> Result<bool> {
        self.with_conn(|conn| {
            let n: i64 = conn.query_row(
                "SELECT count(*) FROM works WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )?;
            Ok(n > 0)
        })
    }

    /// 读取单条记忆（**软删即不可见**：查不到返回 `Ok(None)`，恢复通道留待 G17 评审）。
    pub fn get_memory(&self, id: &str) -> Result<Option<Memory>> {
        self.with_conn(|conn| {
            let row = conn
                .prepare_cached(&format!(
                    "SELECT {MEMORY_COLUMNS} FROM memories WHERE id = ?1 AND deleted_at IS NULL"
                ))?
                .query_row(params![id], memory_from_row)
                .optional()?;
            Ok(row)
        })
    }

    /// 按空间列出记忆（**强制 space 过滤，无全空间入口**；软删不可见；updated_at 倒序）。
    ///
    /// `status` 仅 idea 空间可过滤（其他空间传 Some 会报错，避免拼出恒空查询）。
    pub fn list_memories(&self, space: Space, status: Option<&str>) -> Result<Vec<Memory>> {
        if status.is_some() && space != Space::Idea {
            return Err(Error::parse("status 过滤仅 idea 空间可用"));
        }
        self.with_conn(|conn| {
            let sql = format!(
                "SELECT {MEMORY_COLUMNS} FROM memories
                 WHERE space = ?1 AND deleted_at IS NULL {} ORDER BY updated_at DESC",
                if status.is_some() { "AND status = ?2" } else { "" }
            );
            let mut stmt = conn.prepare_cached(&sql)?;
            let rows = match status {
                Some(s) => stmt
                    .query_map(params![space.as_str(), s], memory_from_row)?
                    .collect::<std::result::Result<Vec<_>, _>>()?,
                None => stmt
                    .query_map(params![space.as_str()], memory_from_row)?
                    .collect::<std::result::Result<Vec<_>, _>>()?,
            };
            Ok(rows)
        })
    }

    /// 更新记忆（部分字段；`work_id` / `space` 不可变）。
    /// idea 空间的 status 改动走状态机校验，非法迁移报错。
    pub fn update_memory(&self, id: &str, upd: UpdateMemory) -> Result<Memory> {
        let current = self
            .get_memory(id)?
            .ok_or_else(|| Error::not_found(format!("记忆 {id} 不存在或已删除")))?;
        let mut next = current.clone();

        if let Some(kind) = &upd.kind {
            let kind = kind.trim();
            if kind.is_empty() {
                return Err(Error::parse("记忆 kind 不能为空"));
            }
            next.kind = kind.to_string();
        }
        if let Some(title) = &upd.title {
            let title = title.trim();
            if title.is_empty() {
                return Err(Error::parse("记忆标题不能为空"));
            }
            next.title = title.to_string();
        }
        if let Some(summary) = &upd.summary {
            next.summary = Some(summary.clone());
        }
        if let Some(status) = &upd.status {
            if current.space != Space::Idea.as_str() {
                return Err(Error::parse("status 仅 idea 空间可用"));
            }
            let from = current.status.as_deref().unwrap_or("liked");
            validate_status_transition(from, status)?;
            next.status = Some(status.clone());
        }
        if let Some(rp) = &upd.reminder_pref {
            next.reminder_pref = Some(rp.clone());
        }
        if let Some(p) = &upd.payload {
            next.payload = Some(p.clone());
        }
        next.updated_at = now();

        self.with_conn(|conn| {
            conn.execute(
                "UPDATE memories SET kind = ?2, title = ?3, summary = ?4, status = ?5,
                     reminder_pref = ?6, payload = ?7, updated_at = ?8
                 WHERE id = ?1 AND deleted_at IS NULL",
                params![
                    next.id,
                    next.kind,
                    next.title,
                    next.summary,
                    next.status,
                    next.reminder_pref.as_ref().map(|v| v.to_string()),
                    next.payload.as_ref().map(|v| v.to_string()),
                    next.updated_at
                ],
            )?;
            Ok(())
        })?;
        Ok(next)
    }

    /// 软删（G17 依赖）：`deleted_at` 打时间戳；默认查询从此不可见。
    /// 幂等：已软删的记忆再次调用返回 Ok。
    pub fn soft_delete_memory(&self, id: &str) -> Result<()> {
        let now = now();
        self.with_conn(|conn| {
            conn.execute(
                "UPDATE memories SET deleted_at = ?2, updated_at = ?2 WHERE id = ?1 AND deleted_at IS NULL",
                params![id, now],
            )?;
            Ok(())
        })
    }

    // ------------------------------------------------------------------
    // 出处链（G08/G17）
    // ------------------------------------------------------------------

    /// 给记忆添加出处（会话 + 消息位置 + ≤120 字短引用）。
    ///
    /// 幂等：同一 (memory, session, seq) 重复添加视为更新 anchor。
    /// `session_id` 必须已存在于索引（防手滑）；但不加外键——会话被清理后
    /// 出处链仍可展示（见模块文档）。
    pub fn add_source(
        &self,
        memory_id: &str,
        session_id: &str,
        message_seq: Option<i64>,
        anchor: Option<&str>,
    ) -> Result<()> {
        self.get_memory(memory_id)?
            .ok_or_else(|| Error::not_found(format!("记忆 {memory_id} 不存在或已删除")))?;
        if self.get_session(session_id)?.is_none() {
            return Err(Error::not_found(format!("会话 {session_id} 不存在")));
        }
        if let Some(a) = anchor {
            if a.chars().count() > 120 {
                return Err(Error::parse(format!(
                    "anchor 不能超过 120 字（当前 {} 字）",
                    a.chars().count()
                )));
            }
        }
        self.with_conn(|conn| {
            conn.execute(
                "INSERT OR REPLACE INTO memory_sources (memory_id, session_id, message_seq, anchor)
                 VALUES (?1, ?2, ?3, ?4)",
                params![memory_id, session_id, message_seq, anchor],
            )?;
            Ok(())
        })
    }

    /// 读取记忆的全部出处（G08/G17 的「这句记忆哪来的」）。
    /// 排序：具体消息引用在前，整会话引用（message_seq 为 NULL）在后。
    pub fn get_sources(&self, memory_id: &str) -> Result<Vec<MemorySource>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT memory_id, session_id, message_seq, anchor FROM memory_sources
                 WHERE memory_id = ?1 ORDER BY session_id, message_seq IS NULL, message_seq",
            )?;
            let rows = stmt
                .query_map(params![memory_id], |r| {
                    Ok(MemorySource {
                        memory_id: r.get(0)?,
                        session_id: r.get(1)?,
                        message_seq: r.get(2)?,
                        anchor: r.get(3)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    // ------------------------------------------------------------------
    // 跨空间链接（红线：只允许本 API 显式写入，actor='user'，Goal §4.2）
    // ------------------------------------------------------------------

    /// 建立记忆链接（**跨空间引用必须由用户触发**，任何自动/批量路径不得调用）。
    ///
    /// 单向可见：只见 from 的出链（to 侧不自动出现反向，见模块文档）。
    /// 重复链接报错（显式优于静默）；禁止自链接。
    pub fn link_memories(&self, from_id: &str, to_id: &str) -> Result<()> {
        if from_id == to_id {
            return Err(Error::parse("不能链接记忆自身"));
        }
        for id in [from_id, to_id] {
            self.get_memory(id)?
                .ok_or_else(|| Error::not_found(format!("记忆 {id} 不存在或已删除")))?;
        }
        let exists: bool = self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT count(*) > 0 FROM memory_links WHERE from_id = ?1 AND to_id = ?2",
                    params![from_id, to_id],
                    |r| r.get(0),
                )?)
        })?;
        if exists {
            return Err(Error::parse("链接已存在"));
        }
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO memory_links (from_id, to_id, actor, created_at) VALUES (?1, ?2, 'user', ?3)",
                params![from_id, to_id, now()],
            )?;
            Ok(())
        })
    }

    /// from 记忆的出链（单向可见；to 侧已软删的不出现）。
    pub fn get_links(&self, from_id: &str) -> Result<Vec<MemoryLinkView>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT l.from_id, l.to_id, m.space, m.title, l.actor, l.created_at
                 FROM memory_links l
                 JOIN memories m ON m.id = l.to_id AND m.deleted_at IS NULL
                 WHERE l.from_id = ?1
                 ORDER BY l.created_at DESC",
            )?;
            let rows = stmt
                .query_map(params![from_id], |r| {
                    Ok(MemoryLinkView {
                        from_id: r.get(0)?,
                        to_id: r.get(1)?,
                        to_space: r.get(2)?,
                        to_title: r.get(3)?,
                        actor: r.get(4)?,
                        created_at: r.get(5)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::types::SessionStub;

    fn db() -> Database {
        Database::open_in_memory().unwrap()
    }

    fn new_memory(space: Space, title: &str) -> NewMemory {
        NewMemory {
            space,
            work_id: None,
            kind: "note".into(),
            title: title.into(),
            summary: None,
            status: None,
            reminder_pref: None,
            payload: None,
        }
    }

    /// 造一个真实会话（出处链要用）。
    fn seed_session(db: &Database, id: &str) {
        db.upsert_session_stub(&SessionStub {
            id: id.into(),
            source: "kimi".into(),
            external_id: id.trim_start_matches("kimi:").into(),
            source_root: None,
            primary_file: None,
        })
        .unwrap();
    }

    #[test]
    fn 四空间_按_space_查询互不返回对方数据() {
        // G06 核心证据：四个空间各建数据，按 space 查询互不返回对方数据。
        let db = db();
        let work = db.create_work("测试作品").unwrap();
        db.create_memory(new_memory(Space::Personal, "个人偏好")).unwrap();
        db.create_memory(new_memory(Space::Idea, "旧想法")).unwrap();
        db.create_memory(NewMemory {
            work_id: Some(work.id.clone()),
            ..new_memory(Space::Novel, "小说设定")
        })
        .unwrap();
        db.create_memory(new_memory(Space::Learning, "学习薄弱点")).unwrap();

        for space in Space::ALL {
            let list = db.list_memories(*space, None).unwrap();
            assert_eq!(list.len(), 1, "空间 {} 应只看到自己的数据", space.as_str());
            assert_eq!(list[0].space, space.as_str());
        }
        // novel 空间的数据挂在作品下
        let novel = db.list_memories(Space::Novel, None).unwrap();
        assert_eq!(novel[0].work_id.as_deref(), Some(work.id.as_str()));
    }

    #[test]
    fn 未链接时跨空间不可达_链接后单向可见() {
        // G06：默认不互通；link_memories（用户显式触发）后 from 侧可见出链，
        // to 侧不自动出现反向（单向可见，本测试固化该语义）。
        let db = db();
        let a = db.create_memory(new_memory(Space::Personal, "个人 A")).unwrap();
        let b = db.create_memory(new_memory(Space::Idea, "想法 B")).unwrap();

        // 未链接：两边都看不到对方
        assert!(db.get_links(&a.id).unwrap().is_empty());
        assert!(db.get_links(&b.id).unwrap().is_empty());
        // 跨空间查询也互不可达（list 互不返回）
        assert!(db.list_memories(Space::Personal, None).unwrap().iter().all(|m| m.id != b.id));
        assert!(db.list_memories(Space::Idea, None).unwrap().iter().all(|m| m.id != a.id));

        // 用户显式链接 A → B
        db.link_memories(&a.id, &b.id).unwrap();
        let links_a = db.get_links(&a.id).unwrap();
        assert_eq!(links_a.len(), 1, "from 侧应看到出链");
        assert_eq!(links_a[0].to_id, b.id);
        assert_eq!(links_a[0].to_space, "idea");
        assert_eq!(links_a[0].actor, "user", "链接必须记录 actor=user");
        // 单向可见：to 侧不出现反向链接
        assert!(db.get_links(&b.id).unwrap().is_empty(), "单向可见：to 侧不应有反向链接");

        // 链接不改变 list 的隔离性（A 仍不出现在 idea 空间）
        assert!(db.list_memories(Space::Idea, None).unwrap().iter().all(|m| m.id != a.id));

        // 重复链接与自链接报错
        assert!(db.link_memories(&a.id, &b.id).is_err(), "重复链接应报错");
        assert!(db.link_memories(&a.id, &a.id).is_err(), "自链接应报错");
    }

    #[test]
    fn 软删后默认查询不可见() {
        let db = db();
        let m = db.create_memory(new_memory(Space::Personal, "将被删除")).unwrap();
        db.soft_delete_memory(&m.id).unwrap();
        assert!(db.get_memory(&m.id).unwrap().is_none(), "软删后 get 不可见");
        assert!(db.list_memories(Space::Personal, None).unwrap().is_empty(), "软删后 list 不可见");
        // 幂等：重复软删不报错
        db.soft_delete_memory(&m.id).unwrap();
    }

    #[test]
    fn idea_状态机_合法与非法迁移() {
        let db = db();
        let m = db.create_memory(new_memory(Space::Idea, "想法")).unwrap();
        assert_eq!(m.status.as_deref(), Some("liked"), "默认状态 liked");

        // 主路径 liked → started → done
        let m = db.update_memory(&m.id, UpdateMemory { status: Some("started".into()), ..Default::default() }).unwrap();
        assert_eq!(m.status.as_deref(), Some("started"));
        let m = db.update_memory(&m.id, UpdateMemory { status: Some("done".into()), ..Default::default() }).unwrap();
        assert_eq!(m.status.as_deref(), Some("done"));

        // 终态不可再迁移
        assert!(db.update_memory(&m.id, UpdateMemory { status: Some("started".into()), ..Default::default() }).is_err());
        // 非法取值
        assert!(db.update_memory(&m.id, UpdateMemory { status: Some("nonsense".into()), ..Default::default() }).is_err());

        // liked 可直接 wrong / shelved；shelved 可重新 started
        let m2 = db.create_memory(new_memory(Space::Idea, "想法2")).unwrap();
        let m2 = db.update_memory(&m2.id, UpdateMemory { status: Some("shelved".into()), ..Default::default() }).unwrap();
        assert_eq!(m2.status.as_deref(), Some("shelved"));
        let m2 = db.update_memory(&m2.id, UpdateMemory { status: Some("started".into()), ..Default::default() }).unwrap();
        assert_eq!(m2.status.as_deref(), Some("started"));
        assert!(db.update_memory(&m2.id, UpdateMemory { status: Some("liked".into()), ..Default::default() }).is_err(), "不能回退到 liked");

        // 同状态赋值是幂等 no-op
        db.update_memory(&m2.id, UpdateMemory { status: Some("started".into()), ..Default::default() }).unwrap();

        // 非 idea 空间禁止 status
        let p = db.create_memory(new_memory(Space::Personal, "个人")).unwrap();
        assert!(db.update_memory(&p.id, UpdateMemory { status: Some("started".into()), ..Default::default() }).is_err());
    }

    #[test]
    fn novel_必须挂作品_其他空间禁止挂作品() {
        let db = db();
        // novel 无 work_id → 错
        assert!(db.create_memory(new_memory(Space::Novel, "无作品")).is_err());
        // work_id 不存在 → 错
        assert!(db
            .create_memory(NewMemory {
                work_id: Some("不存在".into()),
                ..new_memory(Space::Novel, "作品不存在")
            })
            .is_err());
        // 其他空间挂 work_id → 错
        let work = db.create_work("作品甲").unwrap();
        assert!(db
            .create_memory(NewMemory {
                work_id: Some(work.id.clone()),
                ..new_memory(Space::Personal, "个人挂作品")
            })
            .is_err());
        // 正常路径
        let m = db
            .create_memory(NewMemory {
                work_id: Some(work.id),
                ..new_memory(Space::Novel, "设定集")
            })
            .unwrap();
        assert!(m.work_id.is_some());
        assert_eq!(db.list_works().unwrap().len(), 1);
    }

    #[test]
    fn 出处链_添加读取与anchor限制() {
        let db = db();
        seed_session(&db, "kimi:src1");
        let m = db.create_memory(new_memory(Space::Personal, "带出处")).unwrap();

        db.add_source(&m.id, "kimi:src1", Some(7), Some("短引用")).unwrap();
        // 幂等：同出处重复添加 = 更新 anchor
        db.add_source(&m.id, "kimi:src1", Some(7), Some("更新后的引用")).unwrap();
        // 会话级出处（无 message_seq）
        db.add_source(&m.id, "kimi:src1", None, None).unwrap();

        let sources = db.get_sources(&m.id).unwrap();
        assert_eq!(sources.len(), 2, "同 (memory, session, seq) 应去重");
        assert_eq!(sources[0].session_id, "kimi:src1");
        assert_eq!(sources[0].message_seq, Some(7));
        assert_eq!(sources[0].anchor.as_deref(), Some("更新后的引用"));

        // anchor 超 120 字报错
        let long = "长".repeat(121);
        assert!(db.add_source(&m.id, "kimi:src1", Some(9), Some(&long)).is_err());
        // 记忆不存在 / 会话不存在 → 错
        assert!(db.add_source("不存在", "kimi:src1", None, None).is_err());
        assert!(db.add_source(&m.id, "kimi:不存在", None, None).is_err());
    }

    #[test]
    fn search_命中携带会话元数据可反查() {
        // 出处检索的另一半：search 命中的 message 自带会话元数据，且能反查会话。
        let db = db();
        seed_session(&db, "kimi:meta1");
        db.insert_messages(&[crate::storage::MessageRow {
            id: "kimi:meta1#0".into(),
            session_id: "kimi:meta1".into(),
            sequence: 0,
            role: "user".into(),
            kind: "message".into(),
            text: Some("zxqw 合成锚点".into()),
            tool_name: None,
            timestamp: None,
            raw: None,
        }])
        .unwrap();
        // finalize 标题（search 命中要带 title）
        let mut info = crate::model::ParsedSessionInfo::new();
        info.title = Some("元数据会话".into());
        db.finalize_session("kimi:meta1", &info, None).unwrap();

        let resp = db
            .search(&crate::storage::SearchQuery {
                text: "zxqw".into(),
                limit: 5,
                offset: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(resp.hits.len(), 1);
        let hit = &resp.hits[0];
        assert_eq!(hit.session_id, "kimi:meta1");
        assert_eq!(hit.title.as_deref(), Some("元数据会话"), "命中应携带会话标题");
        assert_eq!(hit.source, "kimi");
        // 反查：命中 → 会话详情
        let detail = db.get_session_detail(&hit.session_id).unwrap().unwrap();
        assert_eq!(detail.summary.title.as_deref(), Some("元数据会话"));
    }
}
