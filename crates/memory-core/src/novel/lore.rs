//! 设定集（Story Bible 底座，T05D）：人物/世界/时间线/禁忌/文风的结构化条目、
//! 不可变版本链与作者确认留痕；出处锚点绑定不可变确认版本。
//! 不变量：
//! - 条目身份是 id：同名异人不做唯一约束、不自动合并（同名查询返回全部，用户分辨）；
//! - AI 产出只能 candidate，作者显式确认才 confirmed；确认留痕在版本上；
//! - 出处锚点校验版本归属、坐标边界与片段 hash；头版本移动后 stale 由查询端计算。

use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{new_id, now};

/// 设定条目类型（Story Bible 分类）。与 `NovelKind` 是两套口径：
/// 文档侧按「写作单元」分（章节/角色卡…），设定侧按「条目语义」分（含 location / style）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LoreKind {
    Character,
    Location,
    World,
    Timeline,
    Taboo,
    Style,
}

impl LoreKind {
    /// 数据库存储形态（小写）。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Character => "character",
            Self::Location => "location",
            Self::World => "world",
            Self::Timeline => "timeline",
            Self::Taboo => "taboo",
            Self::Style => "style",
        }
    }

    /// 从存储形态反解析；未知类型报 Parse 错误。
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "character" => Ok(Self::Character),
            "location" => Ok(Self::Location),
            "world" => Ok(Self::World),
            "timeline" => Ok(Self::Timeline),
            "taboo" => Ok(Self::Taboo),
            "style" => Ok(Self::Style),
            _ => Err(Error::parse("无法识别的设定类型")),
        }
    }
}

/// 设定条目（行视图）。身份是 id 而非 name——同名异人不做唯一约束、不自动合并，
/// `find_lore_by_name` 返回全部同名项由用户分辨。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoreEntry {
    pub id: String,
    pub work_id: String,
    pub kind: String,
    pub name: String,
    pub aliases: Vec<String>,
    pub status: String,
    /// whole = 全程有效；retrospective = 回溯改设定；from:<document_id> = 自该章起改变。
    pub scope: String,
    pub head_version: i64,
    pub created_at: String,
    pub updated_at: String,
}

/// 设定条目的一个不可变版本。版本链只增不删；`confirmed` 是作者核对留痕（origin 与之对应）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoreVersion {
    pub id: String,
    pub entry_id: String,
    pub version: i64,
    pub body: String,
    pub confirmed: bool,
    pub origin: String,
    pub created_at: String,
}

/// 出处锚点 + 查询端计算的可用性。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceAnchor {
    pub id: String,
    pub work_id: String,
    pub document_id: String,
    pub source_version_id: String,
    pub start_char: i64,
    pub end_char: i64,
    pub quote_hash: String,
    pub note: Option<String>,
    pub created_at: String,
    /// true = 来源版本仍是当前确认头；false = 旧版出处（历史可见，需作者重绑定）。
    pub is_current: bool,
}

/// 新建出处锚点的入参（add_source_anchor 的参数包）。
pub struct NewSourceAnchor<'a> {
    pub work_id: &'a str,
    pub document_id: &'a str,
    pub source_version_id: &'a str,
    pub start_char: i64,
    pub end_char: i64,
    pub quote_hash: &'a str,
    pub note: Option<&'a str>,
}

pub(super) fn read_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<LoreEntry> {
    // aliases 以 JSON 文本列存储；解析失败回退空表——别名是展示辅助，
    // 一条坏别名不该让整个条目读不出来。
    let aliases_json: String = row.get(4)?;
    Ok(LoreEntry {
        id: row.get(0)?,
        work_id: row.get(1)?,
        kind: row.get(2)?,
        name: row.get(3)?,
        aliases: serde_json::from_str(&aliases_json).unwrap_or_default(),
        status: row.get(5)?,
        scope: row.get(6)?,
        head_version: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

impl Database {
    /// 新建设定条目并写首版本。作者来源直接 confirmed；AI 来源只能 candidate。
    pub fn create_lore_entry(
        &self,
        work_id: &str,
        kind: LoreKind,
        name: &str,
        body: &str,
        aliases: &[String],
        author_confirmed: bool,
    ) -> Result<LoreEntry> {
        let name = name.trim();
        let body = body.trim();
        if name.is_empty() || name.chars().count() > 80 {
            return Err(Error::parse("设定名称须为 1–80 个字"));
        }
        if body.chars().count() > 20_000 {
            return Err(Error::parse("设定正文不能超过 20000 个字"));
        }
        let id = new_id();
        let version_id = new_id();
        let timestamp = now();
        let status = if author_confirmed { "confirmed" } else { "candidate" };
        let origin = if author_confirmed { "author" } else { "ai" };
        let aliases_json = serde_json::to_string(aliases).map_err(|e| Error::parse(e.to_string()))?;
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
                "INSERT INTO lore_entries (id, work_id, kind, name, aliases, status, scope, head_version, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'whole', 1, ?7, ?7)",
                params![id, work_id, kind.as_str(), name, aliases_json, status, timestamp],
            )?;
            tx.execute(
                "INSERT INTO lore_versions (id, entry_id, version, body, confirmed, origin, created_at)
                 VALUES (?1, ?2, 1, ?3, ?4, ?5, ?6)",
                params![version_id, id, body, author_confirmed as i64, origin, timestamp],
            )?;
            Ok(())
        })?;
        self.get_lore_entry(&id)?
            .ok_or_else(|| Error::not_found("设定条目不存在"))
    }

    /// 按 id 读取设定条目；不存在返回 Ok(None)。
    pub fn get_lore_entry(&self, entry_id: &str) -> Result<Option<LoreEntry>> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT id, work_id, kind, name, aliases, status, scope, head_version, created_at, updated_at
                     FROM lore_entries WHERE id = ?1",
                    [entry_id],
                    read_entry,
                )
                .optional()?)
        })
    }

    /// 列出作品下的设定条目（可按类型过滤）；按创建序稳定排序。
    pub fn list_lore_entries(&self, work_id: &str, kind: Option<LoreKind>) -> Result<Vec<LoreEntry>> {
        fn collect(rows: &mut rusqlite::Rows<'_>) -> rusqlite::Result<Vec<LoreEntry>> {
            let mut out = Vec::new();
            while let Ok(Some(row)) = rows.next() {
                out.push(read_entry(row)?);
            }
            Ok(out)
        }
        self.with_conn(|conn| {
            if let Some(kind) = kind {
                let mut stmt = conn.prepare_cached(
                    "SELECT id, work_id, kind, name, aliases, status, scope, head_version, created_at, updated_at
                     FROM lore_entries WHERE work_id = ?1 AND kind = ?2 ORDER BY created_at, id",
                )?;
                let mut rows = stmt.query(params![work_id, kind.as_str()])?;
                Ok(collect(&mut rows)?)
            } else {
                let mut stmt = conn.prepare_cached(
                    "SELECT id, work_id, kind, name, aliases, status, scope, head_version, created_at, updated_at
                     FROM lore_entries WHERE work_id = ?1 ORDER BY created_at, id",
                )?;
                let mut rows = stmt.query(params![work_id])?;
                Ok(collect(&mut rows)?)
            }
        })
    }

    /// 同名/别名查询：返回全部匹配（同名异人由用户分辨，不自动合并）。
    pub fn find_lore_by_name(&self, work_id: &str, name: &str) -> Result<Vec<LoreEntry>> {
        let needle = name.trim();
        if needle.is_empty() {
            return Ok(Vec::new());
        }
        let all = self.list_lore_entries(work_id, None)?;
        Ok(all
            .into_iter()
            .filter(|entry| entry.name == needle || entry.aliases.iter().any(|alias| alias == needle))
            .collect())
    }

    /// 追加新版本（设定撤销/阶段改变/正文修订）。expected_version 乐观锁；
    /// confirmed 标记作者是否已核对本版本。新版本立即成为 head，历史不删。
    pub fn update_lore_entry(
        &self,
        entry_id: &str,
        expected_version: i64,
        body: &str,
        aliases: &[String],
        scope: &str,
        confirmed: bool,
    ) -> Result<LoreEntry> {
        let body = body.trim();
        if body.chars().count() > 20_000 {
            return Err(Error::parse("设定正文不能超过 20000 个字"));
        }
        if !matches!(scope, "whole" | "retrospective") && !scope.starts_with("from:") {
            return Err(Error::parse("作用范围必须是 whole / retrospective / from:<章节id>"));
        }
        let aliases_json = serde_json::to_string(aliases).map_err(|e| Error::parse(e.to_string()))?;
        let version_id = new_id();
        let timestamp = now();
        self.with_tx(|tx| {
            let (entry_version, status): (i64, String) = tx.query_row(
                "SELECT head_version, status FROM lore_entries WHERE id = ?1",
                [entry_id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            ).optional()?.ok_or_else(|| Error::not_found("设定条目不存在"))?;
            if entry_version != expected_version {
                return Err(Error::parse("设定已被其他修改更新，请刷新后重试"));
            }
            if status == "rejected" {
                return Err(Error::parse("已否决的设定不能再修改；请新建条目"));
            }
            let next = entry_version + 1;
            tx.execute(
                "INSERT INTO lore_versions (id, entry_id, version, body, confirmed, origin, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![version_id, entry_id, next, body, confirmed as i64, if confirmed { "author" } else { "ai" }, timestamp],
            )?;
            let new_status = if confirmed { "confirmed" } else { "candidate" };
            tx.execute(
                "UPDATE lore_entries SET head_version = ?2, status = ?3, aliases = ?4, scope = ?5, updated_at = ?6 WHERE id = ?1",
                params![entry_id, next, new_status, aliases_json, scope, timestamp],
            )?;
            Ok(())
        })?;
        self.get_lore_entry(entry_id)?
            .ok_or_else(|| Error::not_found("设定条目不存在"))
    }

    /// 候选确认或否决（只允许 candidate 出发）。
    ///
    /// WHERE 条件自带 `status = 'candidate'`：确认/否决是竞争敏感操作，
    /// 用单条 UPDATE 的原子性挡掉「两个面板同时确认」的重复处理，
    /// 影响行数为 0 即说明状态已被别人改过。
    pub fn resolve_lore_entry(&self, entry_id: &str, confirm: bool) -> Result<LoreEntry> {
        let timestamp = now();
        let updated = self.with_tx(|tx| {
            Ok(tx.execute(
                "UPDATE lore_entries SET status = ?2, updated_at = ?3 WHERE id = ?1 AND status = 'candidate'",
                params![entry_id, if confirm { "confirmed" } else { "rejected" }, timestamp],
            )?)
        })?;
        if updated == 0 {
            return Err(Error::parse("只能处理候选状态的设定"));
        }
        self.get_lore_entry(entry_id)?
            .ok_or_else(|| Error::not_found("设定条目不存在"))
    }

    /// 列出条目的全部版本（新→旧）。
    pub fn list_lore_versions(&self, entry_id: &str) -> Result<Vec<LoreVersion>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, entry_id, version, body, confirmed, origin, created_at
                 FROM lore_versions WHERE entry_id = ?1 ORDER BY version DESC",
            )?;
            let rows = stmt
                .query_map([entry_id], |r| {
                    Ok(LoreVersion {
                        id: r.get(0)?,
                        entry_id: r.get(1)?,
                        version: r.get(2)?,
                        body: r.get(3)?,
                        confirmed: r.get::<_, i64>(4)? != 0,
                        origin: r.get(5)?,
                        created_at: r.get(6)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 登记出处锚点：校验版本归属、坐标边界与片段 hash（hash 由调用方按版本正文计算）。
    pub fn add_source_anchor(&self, anchor: &NewSourceAnchor) -> Result<SourceAnchor> {
        if anchor.start_char < 0 || anchor.end_char <= anchor.start_char {
            return Err(Error::parse("锚点坐标无效"));
        }
        let version_body: Option<String> = self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT body FROM novel_versions WHERE id = ?1 AND document_id = ?2",
                    params![anchor.source_version_id, anchor.document_id],
                    |r| r.get(0),
                )
                .optional()?)
        })?;
        let body = version_body.ok_or_else(|| Error::not_found("来源版本不存在于该文档"))?;
        // 坐标按字符（非字节）校验与切片：正文是中文文本，按字节切会把 UTF-8 序列切断。
        let chars: Vec<char> = body.chars().collect();
        if anchor.end_char as usize > chars.len() {
            return Err(Error::parse("锚点超出版本正文范围"));
        }
        let slice: String = chars[anchor.start_char as usize..anchor.end_char as usize].iter().collect();
        let actual_hash = blake3::hash(slice.as_bytes()).to_hex().to_string();
        if actual_hash != anchor.quote_hash {
            return Err(Error::parse("锚点片段与版本正文不一致"));
        }
        let id = new_id();
        let timestamp = now();
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO source_anchors (id, work_id, document_id, source_version_id, start_char, end_char, quote_hash, note, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                params![id, anchor.work_id, anchor.document_id, anchor.source_version_id, anchor.start_char, anchor.end_char, anchor.quote_hash, anchor.note, timestamp],
            )?;
            Ok(())
        })?;
        Ok(SourceAnchor {
            id,
            work_id: anchor.work_id.to_string(),
            document_id: anchor.document_id.to_string(),
            source_version_id: anchor.source_version_id.to_string(),
            start_char: anchor.start_char,
            end_char: anchor.end_char,
            quote_hash: anchor.quote_hash.to_string(),
            note: anchor.note.map(str::to_string),
            created_at: timestamp,
            is_current: true,
        })
    }

    /// 文档的出处锚点（含反向引用入口）。is_current 在查询端与当前头比较得出。
    pub fn list_source_anchors(&self, document_id: &str) -> Result<Vec<SourceAnchor>> {
        let head: Option<String> = self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT head_version_id FROM novel_documents WHERE id = ?1",
                    [document_id],
                    |r| r.get(0),
                )
                .optional()?)
        })?;
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, work_id, document_id, source_version_id, start_char, end_char, quote_hash, note, created_at
                 FROM source_anchors WHERE document_id = ?1 ORDER BY created_at, id",
            )?;
            let rows = stmt
                .query_map([document_id], |r| {
                    Ok(SourceAnchor {
                        id: r.get(0)?,
                        work_id: r.get(1)?,
                        document_id: r.get(2)?,
                        source_version_id: r.get(3)?,
                        start_char: r.get(4)?,
                        end_char: r.get(5)?,
                        quote_hash: r.get(6)?,
                        note: r.get(7)?,
                        created_at: r.get(8)?,
                        is_current: false,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows
                .into_iter()
                .map(|mut anchor| {
                    anchor.is_current = head.as_deref() == Some(anchor.source_version_id.as_str());
                    anchor
                })
                .collect())
        })
    }
}
