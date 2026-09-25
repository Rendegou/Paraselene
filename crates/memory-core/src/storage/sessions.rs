//! 会话与消息的读写、列表查询、分页浏览、流式写入。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/storage/sessions.rs
//! 移植改动（单机裁剪）：
//! - 所有结构去掉 `machine_id` / `archived` / `sync_status` 字段；
//! - 去掉同步与归档专用查询（set_sync_status / sessions_pending_sync / sessions_to_archive /
//!   local_session_files / list_machines / mark_synced_sessions_modified / set_archived）；
//! - `DatabaseSink` 实现 `crate::adapters::MessageSink`（T01 补充片落地适配器层后
//!   已由切片 1 的内在方法升级为 trait impl，与源项目一致）。

use rusqlite::{params, params_from_iter, OptionalExtension, ToSql};

use crate::error::{Error, Result};
use crate::model::{MessageKind, NormalizedMessage, ParsedSessionInfo, Role, SourceKind};
use crate::storage::db::Database;
use crate::storage::types::{ProjectSummary, RawFileRow, SessionStub};

/// 会话摘要（列表 / 搜索结果里的会话信息）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSummary {
    pub id: String,
    pub source: String,
    pub external_id: String,
    pub title: Option<String>,
    pub project_path: Option<String>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub message_count: i64,
    pub partial: bool,
    pub primary_file: Option<String>,
    pub content_hash: Option<String>,
}

/// 会话详情（打开会话时使用）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionDetail {
    #[serde(flatten)]
    pub summary: SessionSummary,
    /// 原始会话目录
    pub source_root: Option<String>,
    /// 归一化阶段保留的元信息
    pub metadata: serde_json::Value,
    /// 参与索引的原始文件
    pub raw_files: Vec<RawFileRow>,
}

/// 消息行（分页浏览用，不整体加载）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageRow {
    pub id: String,
    pub session_id: String,
    pub sequence: i64,
    pub role: String,
    pub kind: String,
    pub text: Option<String>,
    pub tool_name: Option<String>,
    pub timestamp: Option<String>,
    pub raw: Option<serde_json::Value>,
}

/// 会话列表筛选条件。
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SessionFilter {
    /// 数据源：codex / kimi 等
    pub source: Option<String>,
    /// 项目路径（精确匹配）
    pub project_path: Option<String>,
    /// 更新时间下界（RFC3339，含）
    pub from: Option<String>,
    /// 更新时间上界（RFC3339，含）
    pub to: Option<String>,
    /// 标题 / 项目名的模糊匹配（非全文搜索）
    pub text: Option<String>,
}

/// 索引统计。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageStats {
    pub sessions: i64,
    pub messages: i64,
    pub projects: i64,
    pub bytes_on_disk: i64,
}

/// 动态 WHERE 构造器：只绑定参数、绝不拼接用户输入，且仅在需要时加条件（索引友好）。
#[derive(Default)]
struct WhereBuilder {
    clauses: Vec<String>,
    params: Vec<Box<dyn ToSql>>,
}

impl WhereBuilder {
    fn new() -> Self {
        WhereBuilder::default()
    }

    /// 追加一个「列 = 值」条件。
    fn eq(mut self, column: &str, value: Option<&String>) -> Self {
        if let Some(v) = value {
            self.clauses.push(format!("{column} = ?"));
            self.params.push(Box::new(v.clone()));
        }
        self
    }

    /// 追加一个「列 >= 值」条件（时间字符串可直接比较，RFC3339 可排序）。
    fn gte(mut self, column: &str, value: Option<&String>) -> Self {
        if let Some(v) = value {
            self.clauses.push(format!("{column} >= ?"));
            self.params.push(Box::new(v.clone()));
        }
        self
    }

    /// 追加一个「列 <= 值」条件。
    fn lte(mut self, column: &str, value: Option<&String>) -> Self {
        if let Some(v) = value {
            self.clauses.push(format!("{column} <= ?"));
            self.params.push(Box::new(v.clone()));
        }
        self
    }

    /// 追加 LIKE 条件（自动加通配符）。
    fn like(self, column: &str, value: Option<&String>) -> Self {
        match value {
            Some(v) if !v.trim().is_empty() => {
                let mut me = self;
                me.clauses.push(format!("{column} LIKE ? ESCAPE '\\'"));
                me.params
                    .push(Box::new(format!("%{}%", escape_like(v.trim()))));
                me
            }
            _ => self,
        }
    }

    /// 生成 SQL 片段与参数。
    ///
    /// 注：源项目还有一个 `raw` 方法（追加代码内常量条件），唯一用户是归档 / 同步筛选，
    /// 随单机裁剪一并移除；后续出现「常量条件」筛选需求时再加回。
    fn build(self) -> (String, Vec<Box<dyn ToSql>>) {
        if self.clauses.is_empty() {
            (String::new(), self.params)
        } else {
            (
                format!(" WHERE {}", self.clauses.join(" AND ")),
                self.params,
            )
        }
    }
}

/// 转义 LIKE 通配符，避免用户输入 `%` 造成全表扫描。
fn escape_like(input: &str) -> String {
    input
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

/// 会话表 SELECT 子句（列顺序与 [`map_session`] 一一对应）。
const SESSION_COLUMNS: &str =
    "s.id, s.source, s.external_session_id, s.title, s.project_path, s.created_at, \
     s.updated_at, s.message_count, s.partial, s.primary_file, s.content_hash";

/// 把查询结果映射为 [`SessionSummary`]。
fn map_session(row: &rusqlite::Row<'_>) -> rusqlite::Result<SessionSummary> {
    Ok(SessionSummary {
        id: row.get(0)?,
        source: row.get(1)?,
        external_id: row.get(2)?,
        title: row.get(3)?,
        project_path: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
        message_count: row.get(7)?,
        partial: row.get::<_, i64>(8)? != 0,
        primary_file: row.get(9)?,
        content_hash: row.get(10)?,
    })
}

impl Database {
    // ------------------------------------------------------------------
    // 写入
    // ------------------------------------------------------------------

    /// 写入 / 更新会话占位行（解析开始前调用，保证 messages 外键可用）。
    pub fn upsert_session_stub(&self, stub: &SessionStub) -> Result<()> {
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO sessions (id, source, external_session_id, source_root,
                                       primary_file, indexed_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT (id) DO UPDATE SET
                   source_root  = COALESCE(excluded.source_root, sessions.source_root),
                   primary_file = COALESCE(excluded.primary_file, sessions.primary_file),
                   indexed_at   = excluded.indexed_at",
                params![
                    stub.id,
                    stub.source,
                    stub.external_id,
                    stub.source_root,
                    stub.primary_file,
                    chrono::Utc::now().to_rfc3339()
                ],
            )?;
            Ok(())
        })
    }

    /// 清空某个会话的消息（重新解析前调用；FTS 由触发器同步）。
    pub fn clear_messages(&self, session_id: &str) -> Result<()> {
        self.with_conn(|conn| {
            conn.execute(
                "DELETE FROM messages WHERE session_id = ?1",
                params![session_id],
            )?;
            Ok(())
        })
    }

    /// 批量写入消息（单事务，配合流式解析分批调用）。
    pub fn insert_messages(&self, rows: &[MessageRow]) -> Result<()> {
        if rows.is_empty() {
            return Ok(());
        }
        self.with_tx(|tx| {
            let mut stmt = tx.prepare_cached(
                "INSERT OR REPLACE INTO messages
                   (id, session_id, role, kind, text, tool_name, timestamp, sequence, raw)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )?;
            for row in rows {
                let raw = row.raw.as_ref().map(|v| v.to_string());
                stmt.execute(params![
                    row.id,
                    row.session_id,
                    row.role,
                    row.kind,
                    row.text,
                    row.tool_name,
                    row.timestamp,
                    row.sequence,
                    raw
                ])?;
            }
            Ok(())
        })
    }

    /// 解析完成后写入会话元数据。
    pub fn finalize_session(
        &self,
        session_id: &str,
        info: &ParsedSessionInfo,
        content_hash: Option<&str>,
    ) -> Result<()> {
        let metadata = serde_json::to_string(&info.metadata).unwrap_or_else(|_| "{}".to_string());
        self.with_conn(|conn| {
            conn.execute(
                "UPDATE sessions SET
                   title         = COALESCE(?2, title),
                   project_path  = COALESCE(?3, project_path),
                   created_at    = COALESCE(?4, created_at),
                   updated_at    = COALESCE(?5, updated_at),
                   content_hash  = COALESCE(?6, content_hash),
                   message_count = ?7,
                   partial       = ?8,
                   metadata      = ?9,
                   indexed_at    = ?10
                 WHERE id = ?1",
                params![
                    session_id,
                    info.title,
                    info.project_path,
                    info.created_at,
                    info.updated_at,
                    content_hash,
                    info.message_count as i64,
                    info.partial as i64,
                    metadata,
                    chrono::Utc::now().to_rfc3339()
                ],
            )?;
            Ok(())
        })
    }

    /// 删除会话（原始文件已消失时使用；消息与 FTS 随外键级联清理）。
    pub fn delete_sessions(&self, ids: &[String]) -> Result<usize> {
        if ids.is_empty() {
            return Ok(0);
        }
        self.with_tx(|tx| {
            let mut stmt = tx.prepare_cached("DELETE FROM sessions WHERE id = ?1")?;
            let mut removed = 0;
            for id in ids {
                removed += stmt.execute(params![id])?;
            }
            Ok(removed)
        })
    }

    // ------------------------------------------------------------------
    // 读取
    // ------------------------------------------------------------------

    /// 会话列表（按更新时间倒序，带筛选与分页）。
    pub fn list_sessions(
        &self,
        filter: &SessionFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SessionSummary>> {
        let (where_sql, mut bindings) = WhereBuilder::new()
            .eq("s.source", filter.source.as_ref())
            .eq("s.project_path", filter.project_path.as_ref())
            .gte("s.updated_at", filter.from.as_ref())
            .lte("s.updated_at", filter.to.as_ref())
            .like("s.title", filter.text.as_ref())
            .build();

        let sql = format!(
            "SELECT {SESSION_COLUMNS} FROM sessions s{where_sql}
             ORDER BY COALESCE(s.updated_at, s.created_at, '') DESC, s.id DESC
             LIMIT ? OFFSET ?"
        );
        bindings.push(Box::new(limit));
        bindings.push(Box::new(offset));

        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(&sql)?;
            let rows = stmt
                .query_map(params_from_iter(bindings.iter()), map_session)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 满足筛选条件的会话总数（分页显示用）。
    pub fn count_sessions(&self, filter: &SessionFilter) -> Result<i64> {
        let (where_sql, bindings) = WhereBuilder::new()
            .eq("s.source", filter.source.as_ref())
            .eq("s.project_path", filter.project_path.as_ref())
            .gte("s.updated_at", filter.from.as_ref())
            .lte("s.updated_at", filter.to.as_ref())
            .like("s.title", filter.text.as_ref())
            .build();
        let sql = format!("SELECT count(*) FROM sessions s{where_sql}");
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(&sql)?;
            let count: i64 = stmt.query_row(params_from_iter(bindings.iter()), |r| r.get(0))?;
            Ok(count)
        })
    }

    /// 读取单个会话。
    pub fn get_session(&self, id: &str) -> Result<Option<SessionSummary>> {
        let sql = format!("SELECT {SESSION_COLUMNS} FROM sessions s WHERE s.id = ?1");
        self.with_conn(|conn| {
            let row = conn
                .prepare_cached(&sql)?
                .query_row(params![id], map_session)
                .optional()?;
            Ok(row)
        })
    }

    /// 读取会话详情（含元信息与原始文件）。
    pub fn get_session_detail(&self, id: &str) -> Result<Option<SessionDetail>> {
        let summary = match self.get_session(id)? {
            Some(s) => s,
            None => return Ok(None),
        };
        let (source_root, metadata) = self.with_conn(|conn| {
            let row = conn
                .query_row(
                    "SELECT source_root, metadata FROM sessions WHERE id = ?1",
                    params![id],
                    |r| {
                        Ok((
                            r.get::<_, Option<String>>(0)?,
                            r.get::<_, Option<String>>(1)?,
                        ))
                    },
                )
                .optional()?;
            Ok(row.unwrap_or((None, None)))
        })?;
        let metadata = metadata
            .and_then(|m| serde_json::from_str::<serde_json::Value>(&m).ok())
            .unwrap_or_else(|| serde_json::json!({}));
        let raw_files = self.raw_files_for(id)?;
        Ok(Some(SessionDetail {
            summary,
            source_root,
            metadata,
            raw_files,
        }))
    }

    /// 会话的原始目录（「打开原始文件」用）。
    pub fn session_source_root(&self, id: &str) -> Result<Option<String>> {
        self.with_conn(|conn| {
            let root = conn
                .query_row(
                    "SELECT source_root FROM sessions WHERE id = ?1",
                    params![id],
                    |r| r.get::<_, Option<String>>(0),
                )
                .optional()?
                .flatten();
            Ok(root)
        })
    }

    /// 会话的原始文件清单。
    pub fn raw_files_for(&self, session_id: &str) -> Result<Vec<RawFileRow>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT path, role, size, mtime, hash FROM raw_files WHERE session_id = ?1 ORDER BY path",
            )?;
            let rows = stmt
                .query_map(params![session_id], |r| {
                    Ok(RawFileRow {
                        path: r.get(0)?,
                        role: r.get(1)?,
                        size: r.get::<_, i64>(2)? as u64,
                        mtime: r.get(3)?,
                        hash: r.get(4)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 分页读取消息（浏览器虚拟列表按需加载）。
    pub fn messages_page(
        &self,
        session_id: &str,
        offset: i64,
        limit: i64,
    ) -> Result<Vec<MessageRow>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, session_id, sequence, role, kind, text, tool_name, timestamp, raw
                 FROM messages WHERE session_id = ?1 ORDER BY sequence LIMIT ?2 OFFSET ?3",
            )?;
            let rows = stmt
                .query_map(params![session_id, limit, offset], map_message)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 读取某条消息前后文（搜索结果跳转定位用）。
    pub fn messages_around(
        &self,
        session_id: &str,
        sequence: i64,
        before: i64,
        after: i64,
    ) -> Result<Vec<MessageRow>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, session_id, sequence, role, kind, text, tool_name, timestamp, raw
                 FROM messages WHERE session_id = ?1 AND sequence BETWEEN ?2 AND ?3 ORDER BY sequence",
            )?;
            let rows = stmt
                .query_map(
                    params![session_id, (sequence - before).max(0), sequence + after],
                    map_message,
                )?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 流式遍历会话消息（导出 / 归档时使用，避免整体加载）。
    pub fn for_each_message(
        &self,
        session_id: &str,
        f: &mut dyn FnMut(&MessageRow) -> Result<()>,
    ) -> Result<()> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, session_id, sequence, role, kind, text, tool_name, timestamp, raw
                 FROM messages WHERE session_id = ?1 ORDER BY sequence",
            )?;
            let mut rows = stmt.query(params![session_id])?;
            while let Some(row) = rows.next()? {
                f(&map_message(row)?)?;
            }
            Ok(())
        })
    }

    /// 项目聚合列表（左栏）。
    pub fn list_projects(&self) -> Result<Vec<ProjectSummary>> {
        let sql =
            "SELECT project_path,
                    count(*) AS session_count,
                    max(COALESCE(updated_at, created_at)) AS last_updated,
                    group_concat(DISTINCT source) AS sources
             FROM sessions
             WHERE project_path IS NOT NULL AND project_path <> ''
             GROUP BY project_path
             ORDER BY last_updated DESC";
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(sql)?;
            let rows = stmt
                .query_map([], |r| {
                    let path: String = r.get(0)?;
                    let sources: Option<String> = r.get(3)?;
                    Ok(ProjectSummary {
                        name: project_name(&path),
                        project_path: path,
                        session_count: r.get(1)?,
                        last_updated: r.get(2)?,
                        sources: sources
                            .unwrap_or_default()
                            .split(',')
                            .filter(|s| !s.is_empty())
                            .map(|s| s.to_string())
                            .collect(),
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }
}

/// 映射消息行。
fn map_message(row: &rusqlite::Row<'_>) -> rusqlite::Result<MessageRow> {
    let raw_text: Option<String> = row.get(8)?;
    Ok(MessageRow {
        id: row.get(0)?,
        session_id: row.get(1)?,
        sequence: row.get(2)?,
        role: row.get(3)?,
        kind: row.get(4)?,
        text: row.get(5)?,
        tool_name: row.get(6)?,
        timestamp: row.get(7)?,
        raw: raw_text.and_then(|t| serde_json::from_str(&t).ok()),
    })
}

/// 从路径取项目名（兼容 Windows 反斜杠）。
fn project_name(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    normalized
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(path)
        .to_string()
}

/// 流式写入 sink：把适配器产出的消息分批写入 SQLite。
///
/// 内存占用与批次大小成正比（默认 512 条），因此 100MB 级会话也不会整体进入内存。
///
/// 契约：输入 [`NormalizedMessage`]（id 为空时调用方应先补 `<session>:<seq>` 形式的 id），
/// 输出为 messages 表行（sequence 由 sink 单调分配）；失败时返回 `Err` 且缓冲区保持不变，
/// 可安全重试。副作用：写 SQLite（INSERT OR REPLACE，FTS 由触发器同步）。
pub struct DatabaseSink<'a> {
    db: &'a Database,
    session_id: String,
    buffer: Vec<MessageRow>,
    batch_size: usize,
    sequence: i64,
    pub inserted: u64,
}

impl<'a> DatabaseSink<'a> {
    /// 新建 sink（`batch_size` 建议 256~1024）。
    pub fn new(db: &'a Database, session_id: &str, batch_size: usize) -> Self {
        DatabaseSink {
            db,
            session_id: session_id.to_string(),
            buffer: Vec::with_capacity(batch_size),
            batch_size: batch_size.max(1),
            sequence: 0,
            inserted: 0,
        }
    }

    /// 提交当前批次。
    pub fn flush(&mut self) -> Result<()> {
        if self.buffer.is_empty() {
            return Ok(());
        }
        self.db.insert_messages(&self.buffer)?;
        self.inserted += self.buffer.len() as u64;
        self.buffer.clear();
        Ok(())
    }
}

impl crate::adapters::MessageSink for DatabaseSink<'_> {
    /// 接收一条归一化消息（攒批，满批自动 flush）。
    fn emit(&mut self, message: NormalizedMessage) -> Result<()> {
        let row = MessageRow {
            id: message.id,
            session_id: self.session_id.clone(),
            sequence: self.sequence,
            role: message.role.as_str().to_string(),
            kind: message.kind.as_str().to_string(),
            text: message.text,
            tool_name: message.tool_name,
            timestamp: message.timestamp,
            raw: message.raw,
        };
        self.sequence += 1;
        self.buffer.push(row);
        if self.buffer.len() >= self.batch_size {
            self.flush()?;
        }
        Ok(())
    }
}

/// 把消息行还原为归一化消息（导出快照时使用）。
pub fn row_to_message(row: &MessageRow) -> NormalizedMessage {
    NormalizedMessage {
        id: row.id.clone(),
        role: Role::parse(&row.role),
        kind: MessageKind::parse(&row.kind),
        timestamp: row.timestamp.clone(),
        text: row.text.clone(),
        tool_name: row.tool_name.clone(),
        raw: row.raw.clone(),
    }
}

/// 数据源字符串 → [`SourceKind`]。
pub fn source_kind(source: &str) -> Result<SourceKind> {
    SourceKind::parse(source).ok_or_else(|| Error::parse(format!("未知数据源: {source}")))
}
