//! 小说作品中的文档、试写和确认版本（T05/G09 的数据边界）。
//!
//! `novel_drafts` 与 `novel_versions` 分表；任何模型生成内容只能先进入 draft。
//! 后续生成上下文只能使用 [`Database::novel_canonical_entries`] 的结果，
//! 该查询只读取每份文档当前 head 指向的确认版本，不碰试写表。
//!
//! 子模块划分（T05A，公开 API 与数据完全兼容）：
//! - 本文件：文档类型、行读取与作品级查询（目录、确认条目）；
//! - [`drafts`]：试写的创建、读取与丢弃；
//! - [`versions`]：确认版本树、采纳与回滚。

mod archive;
mod author_versions;
mod lore_sources;
mod lore_edit;
mod threads;
mod thread_snapshot;
mod derived;
mod directory;
mod drafts;
mod lore;
mod patches;
mod patch_apply;
mod operations;
mod versions;
mod working_copies;

pub use derived::{ChapterSummary, RebuildJob, SUMMARY_ALGORITHM_V1};
pub use lore::{LoreEntry, LoreKind, LoreVersion, NewSourceAnchor, SourceAnchor};
pub use patches::{encode_blocks, NovelPatchRecord};
pub use operations::{NovelOperation, NovelOperationBinding, OperationReference};
pub use working_copies::WorkingCopy;
pub use threads::NovelThread;

use rusqlite::{params, Connection, OptionalExtension, Row};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

pub(crate) const MAX_TITLE_CHARS: usize = 80;
/// 单文档正文上限（20 万字符）：与前端编辑器契约一致，超限拒绝而非截断。
pub(crate) const MAX_BODY_CHARS: usize = 200_000;

/// 作品内文档类型；角色卡、世界设定、时间线、禁忌和章节共享确认流程。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NovelKind {
    /// 章节正文
    Chapter,
    /// 角色卡
    Character,
    /// 世界设定
    World,
    /// 时间线
    Timeline,
    /// 禁忌（写作时不可违反的约束）
    Taboo,
}

impl NovelKind {
    /// 数据库存储形态（小写）。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Chapter => "chapter",
            Self::Character => "character",
            Self::World => "world",
            Self::Timeline => "timeline",
            Self::Taboo => "taboo",
        }
    }

    /// 从存储形态反解析；未知类型报 Parse 错误（调用方必须显式处理，不能默认当章节）。
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "chapter" => Ok(Self::Chapter),
            "character" => Ok(Self::Character),
            "world" => Ok(Self::World),
            "timeline" => Ok(Self::Timeline),
            "taboo" => Ok(Self::Taboo),
            _ => Err(Error::parse("无法识别的小说文档类型")),
        }
    }
}

/// 试写来源。IPC 的用户编辑命令只能传 `User`；模型入口将来传 `Ai`。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DraftOrigin {
    User,
    Ai,
}

impl DraftOrigin {
    /// crate 内部使用（数据库存储形态）；pub(crate) 是刻意的——
    /// IPC 边界只允许 User，AI 来源暂不经 IPC 传入。
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Ai => "ai",
        }
    }
}

/// 文档与当前确认稿；没有确认版本时 `head_body` 为 None。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelDocument {
    pub id: String,
    pub work_id: String,
    pub kind: String,
    pub title: String,
    pub head_version_id: Option<String>,
    pub head_body: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// 未确认文本。只有 `accept_novel_draft` 能将它复制进确认版本树。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelDraft {
    pub id: String,
    pub document_id: String,
    pub base_version_id: Option<String>,
    pub body: String,
    pub origin: String,
    pub status: String,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

/// 章节/设定的一个不可变确认版本；回滚只移动 head，不删除分支。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelVersion {
    pub id: String,
    pub document_id: String,
    pub parent_version_id: Option<String>,
    pub body: String,
    pub origin: String,
    pub created_at: String,
    pub is_head: bool,
}

/// 供后续模型上下文组装的确认条目；不包含任何待决试写。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelCanonicalEntry {
    pub document_id: String,
    pub version_id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
}

/// 目录摘要：左侧栏列表用，**不携带正文**（百万字作品打开目录不传输全文）。
/// `head_body_chars` 是 SQLite length() 的字符数（确认稿），供侧栏显示字数。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelDocumentSummary {
    pub id: String,
    pub work_id: String,
    pub kind: String,
    pub title: String,
    pub head_version_id: Option<String>,
    pub head_body_chars: Option<i64>,
    pub order_index: i64,
    pub archived_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

pub(crate) fn read_document(row: &Row<'_>) -> rusqlite::Result<NovelDocument> {
    // 列序与下方两条 SELECT（document_query / list_novel_documents）强绑定，改动需同步。
    Ok(NovelDocument {
        id: row.get(0)?,
        work_id: row.get(1)?,
        kind: row.get(2)?,
        title: row.get(3)?,
        head_version_id: row.get(4)?,
        head_body: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

pub(crate) fn read_draft(row: &Row<'_>) -> rusqlite::Result<NovelDraft> {
    // 列序与各 draft SELECT 强绑定（8 列：draft 全字段，无 join）。
    Ok(NovelDraft {
        id: row.get(0)?,
        document_id: row.get(1)?,
        base_version_id: row.get(2)?,
        body: row.get(3)?,
        origin: row.get(4)?,
        status: row.get(5)?,
        created_at: row.get(6)?,
        resolved_at: row.get(7)?,
    })
}

/// 按 id 读文档（含当前 head 的正文）；JOIN 条件带 `v.document_id = d.id` 是刻意的——
/// 防止 head_version_id 被脏数据指向别份文档的版本时串文。
pub(crate) fn document_query(
    conn: &Connection,
    document_id: &str,
) -> Result<Option<NovelDocument>> {
    Ok(conn.query_row(
        "SELECT d.id, d.work_id, d.kind, d.title, d.head_version_id, v.body, d.created_at, d.updated_at
         FROM novel_documents d LEFT JOIN novel_versions v
           ON v.id = d.head_version_id AND v.document_id = d.id
         WHERE d.id = ?1",
        [document_id], read_document,
    ).optional()?)
}

/// 校验文档标题：trim 后 1–80 字符；返回 trim 后的切片供调用方直接使用。
pub(crate) fn validate_title(title: &str) -> Result<&str> {
    let title = title.trim();
    if title.is_empty() || title.chars().count() > MAX_TITLE_CHARS {
        return Err(Error::parse("标题须为 1–80 个字"));
    }
    Ok(title)
}

/// 校验正文：trim 后非空且 ≤20 万字符。空正文没有保存意义（删除走专门的归档/删除路径）。\r
pub(crate) fn validate_body(body: &str) -> Result<()> {
    if body.trim().is_empty() || body.chars().count() > MAX_BODY_CHARS {
        return Err(Error::parse("正文须为 1–200000 个字"));
    }
    Ok(())
}

pub(crate) fn now() -> String {
    chrono::Utc::now().to_rfc3339()
}
/// 主键统一走 UUID v4；novel 域所有表共用。
pub(crate) fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

impl Database {
    /// 在已有小说作品下创建空文档；不会自动把任何文字视为确认稿。
    /// 作品必须属于 novel 空间（novel 域只挂在小说空间下）。
    pub fn create_novel_document(
        &self,
        work_id: &str,
        kind: NovelKind,
        title: &str,
    ) -> Result<NovelDocument> {
        let title = validate_title(title)?;
        let id = new_id();
        let timestamp = now();
        self.with_tx(|tx| {
            let exists: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM works WHERE id = ?1 AND space = 'novel')",
                [work_id],
                |r| r.get(0),
            )?;
            if !exists {
                return Err(Error::not_found("小说作品不存在"));
            }
            tx.execute(
                "INSERT INTO novel_documents (id, work_id, kind, title, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
                params![id, work_id, kind.as_str(), title, timestamp],
            )?;
            Ok(())
        })?;
        self.get_novel_document(&id)?
            .ok_or_else(|| Error::not_found("小说文档不存在"))
    }

    /// 列出一部作品的文档和当前确认稿；未知作品报错，不跨作品读取。
    /// 顺序为显式 order_index（用户可重排），同组内按回填时的既有顺序稳定。
    /// 类型排序 CASE 是展示口径：设定类（角色→世界→时间线→禁忌）在前、章节在后。
    pub fn list_novel_documents(&self, work_id: &str) -> Result<Vec<NovelDocument>> {
        self.with_conn(|conn| {
            let exists: bool = conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM works WHERE id = ?1 AND space = 'novel')",
                [work_id], |r| r.get(0),
            )?;
            if !exists { return Err(Error::not_found("小说作品不存在")); }
            let mut stmt = conn.prepare_cached(
                "SELECT d.id, d.work_id, d.kind, d.title, d.head_version_id, v.body, d.created_at, d.updated_at
                 FROM novel_documents d LEFT JOIN novel_versions v
                   ON v.id = d.head_version_id AND v.document_id = d.id
                 WHERE d.work_id = ?1
                 ORDER BY CASE d.kind WHEN 'character' THEN 0 WHEN 'world' THEN 1
                   WHEN 'timeline' THEN 2 WHEN 'taboo' THEN 3 ELSE 4 END, d.order_index, d.created_at, d.id",
            )?;
            let rows = stmt.query_map([work_id], read_document)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 按文档 ID 读取当前确认版本，缺失时返回 None。
    pub fn get_novel_document(&self, document_id: &str) -> Result<Option<NovelDocument>> {
        self.with_conn(|conn| document_query(conn, document_id))
    }

    /// 只返回指定作品当前确认版本；不查询 novel_drafts，不会带入被否决桥段。
    /// 上下文签名的排序口径保持按创建序（内容签名不受 order_index 影响）。
    pub fn novel_canonical_entries(&self, work_id: &str) -> Result<Vec<NovelCanonicalEntry>> {
        self.with_conn(|conn| {
            let exists: bool = conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM works WHERE id = ?1 AND space = 'novel')",
                [work_id],
                |r| r.get(0),
            )?;
            if !exists {
                return Err(Error::not_found("小说作品不存在"));
            }
            let mut stmt = conn.prepare_cached(
                "SELECT d.id, v.id, d.kind, d.title, v.body
                 FROM novel_documents d JOIN novel_versions v
                   ON v.id = d.head_version_id AND v.document_id = d.id
                 WHERE d.work_id = ?1
                 ORDER BY CASE d.kind WHEN 'character' THEN 0 WHEN 'taboo' THEN 1
                   WHEN 'world' THEN 2 WHEN 'timeline' THEN 3 ELSE 4 END, d.created_at, d.id",
            )?;
            let rows = stmt
                .query_map([work_id], |r| {
                    Ok(NovelCanonicalEntry {
                        document_id: r.get(0)?,
                        version_id: r.get(1)?,
                        kind: r.get(2)?,
                        title: r.get(3)?,
                        body: r.get(4)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::{DraftOrigin, NovelKind};
    use crate::storage::db::Database;

    fn work_with_chapters() -> (Database, String, Vec<String>) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let mut ids = Vec::new();
        for title in ["第一章", "第二章", "第三章"] {
            let doc = db
                .create_novel_document(&work.id, NovelKind::Chapter, title)
                .unwrap();
            ids.push(doc.id);
        }
        (db, work.id, ids)
    }

    #[test]
    fn 目录摘要不含正文但带字数与顺序() {
        let (db, work_id, ids) = work_with_chapters();
        let draft = db
            .create_novel_draft(&ids[0], "第一章正文\n共两行", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();

        let summaries = db.novel_document_summaries(&work_id).unwrap();
        assert_eq!(summaries.len(), 3);
        assert_eq!(
            summaries[0].head_body_chars,
            Some("第一章正文\n共两行".chars().count() as i64)
        );
        assert!(summaries[1].head_body_chars.is_none());
        assert_eq!(summaries[0].order_index, 0);
        // 摘要与全文列表的文档顺序一致（同一排序口径）。
        let full = db.list_novel_documents(&work_id).unwrap();
        assert_eq!(
            summaries.iter().map(|s| s.id.clone()).collect::<Vec<_>>(),
            full.iter().map(|d| d.id.clone()).collect::<Vec<_>>()
        );
    }

    #[test]
    fn 重排必须是全集精确排列且顺序生效() {
        let (db, work_id, ids) = work_with_chapters();
        let reversed = vec![ids[2].clone(), ids[1].clone(), ids[0].clone()];
        db.reorder_novel_documents(&work_id, &reversed).unwrap();
        let summaries = db.novel_document_summaries(&work_id).unwrap();
        assert_eq!(
            summaries.iter().map(|s| s.id.clone()).collect::<Vec<_>>(),
            reversed
        );
        // 部分列表 / 混入外部 id 都拒绝。
        assert!(db.reorder_novel_documents(&work_id, &ids[..2]).is_err());
        let mut forged = ids.clone();
        forged[0] = "foreign".into();
        assert!(db.reorder_novel_documents(&work_id, &forged).is_err());
        // 非本作品文档列表拒绝（排序按作品作用域）。
        assert!(db.reorder_novel_documents("missing-work", &ids).is_err());
    }

    #[test]
    fn 重命名更新标题且不触碰版本树() {
        let (db, _work_id, ids) = work_with_chapters();
        let draft = db
            .create_novel_draft(&ids[0], "正文", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        let versions_before = db.list_novel_versions(&ids[0]).unwrap().len();

        let renamed = db.rename_novel_document(&ids[0], "第一章·改").unwrap();
        assert_eq!(renamed.title, "第一章·改");
        assert_eq!(
            db.list_novel_versions(&ids[0]).unwrap().len(),
            versions_before
        );
        assert!(db.rename_novel_document(&ids[0], "   ").is_err());
        assert!(db.rename_novel_document("missing", "新标题").is_err());
    }
}
