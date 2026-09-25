//! 全文搜索：SQLite FTS5 + 结构化筛选，目标 100 万条消息 < 300ms。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/storage/search.rs
//! 移植改动（单机裁剪）：筛选条件与命中结构去掉 `machine_id` / 归档字段；
//! 新增「写入-搜索-高亮往返」与「中文连续字符串命中」两个行为测试（见文件尾 tests）。

use rusqlite::{params_from_iter, ToSql};

use crate::error::Result;
use crate::storage::db::Database;
use crate::storage::sessions::SessionFilter;

/// 搜索排序方式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum SearchOrder {
    /// 相关度（bm25）
    #[default]
    Relevance,
    /// 时间倒序
    Recent,
}

/// 搜索请求。
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SearchQuery {
    /// 关键词（自然语言，内部会安全转换成 FTS5 查询）
    pub text: String,
    pub filter: SessionFilter,
    pub order: SearchOrder,
    /// 仅搜索用户 / 助手正文（排除工具输出与事件）
    pub messages_only: bool,
    pub limit: i64,
    pub offset: i64,
}

/// 单条命中。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchHit {
    pub session_id: String,
    pub message_id: String,
    pub sequence: i64,
    pub role: String,
    pub kind: String,
    pub timestamp: Option<String>,
    /// 带高亮标记的上下文片段（默认 `<mark>`）
    pub snippet: String,
    /// bm25 相关度（越小越相关，取负值后越大越相关）
    pub score: f64,
    // 会话补充信息：搜索结果里直接展示，避免再查一次
    pub title: Option<String>,
    pub project_path: Option<String>,
    pub source: String,
    pub session_updated_at: Option<String>,
}

/// 搜索响应。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchResponse {
    pub hits: Vec<SearchHit>,
    /// 是否还有更多结果（用于「加载更多」）
    pub has_more: bool,
    pub took_ms: u64,
    /// 实际执行的 FTS5 查询（便于排查「为什么搜不到」）
    pub match_query: String,
}

/// 把用户输入转换成安全的 FTS5 MATCH 表达式。
///
/// 规则：
/// - 按空白切词，每个词用双引号包裹（内部引号翻倍转义），避免 FTS5 语法错误；
/// - 最后一个词追加 `*` 做前缀匹配（边打边搜体验）；
/// - 词之间是隐式 AND，符合「关键词搜索」直觉。
pub fn build_match_query(input: &str) -> String {
    let mut tokens: Vec<String> = Vec::new();
    for raw in input.split_whitespace() {
        // 去掉 FTS5 特殊字符，避免 `NEAR(`、`^`、`:` 之类导致语法错误
        let cleaned: String = raw
            .chars()
            .filter(|c| {
                !matches!(
                    c,
                    '"' | '\'' | '(' | ')' | '*' | '^' | ':' | '{' | '}' | '[' | ']'
                )
            })
            .collect();
        if cleaned.is_empty() {
            continue;
        }
        tokens.push(format!("\"{}\"", cleaned.replace('"', "\"\"")));
    }
    if tokens.is_empty() {
        return String::new();
    }
    // 最后一个词做前缀匹配
    if let Some(last) = tokens.last_mut() {
        last.push('*');
    }
    tokens.join(" ")
}

/// 把用户输入切成的 3–6 字滑窗 n-gram，组成 FTS5 trigram OR 短语查询（G05 中文方案）。
///
/// 与 [`build_match_query`]（unicode61，隐式 AND + 前缀）相对，本构造面向
/// `message_fts_trigram`：
/// - 任意 3 字以上子串都可命中，天然支持中文（unicode61 中文只能整串/前缀，题集实测 recall@5 0/24）；
/// - 词组之间是 OR，任一子串命中即召回，靠 bm25 的 IDF 把「停用感太强」的高频片段自动降权；
/// - 查询短于 3 字时 trigram 无法工作（FTS5 trigram 限制），返回空串，调用方应回退到
///   [`build_match_query`] 走 unicode61。
pub fn build_trigram_match_query(input: &str) -> String {
    let chars: Vec<char> = input
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '_')
        .collect();
    let mut grams: Vec<String> = Vec::new();
    for w in [3usize, 4, 5, 6] {
        if chars.len() < w {
            continue;
        }
        for i in 0..=(chars.len() - w) {
            grams.push(chars[i..i + w].iter().collect());
        }
    }
    grams.sort();
    grams.dedup();
    grams.iter().map(|g| format!("\"{g}\"")).collect::<Vec<_>>().join(" OR ")
}

impl Database {
    /// 执行全文搜索。
    pub fn search(&self, query: &SearchQuery) -> Result<SearchResponse> {
        let start = std::time::Instant::now();
        let match_query = build_match_query(&query.text);
        if match_query.is_empty() {
            return Ok(SearchResponse {
                hits: Vec::new(),
                has_more: false,
                took_ms: 0,
                match_query,
            });
        }

        // 动态筛选：只拼接代码内常量列名，用户数据一律走参数绑定
        let mut clauses: Vec<String> = Vec::new();
        let mut bindings: Vec<Box<dyn ToSql>> = Vec::new();
        bindings.push(Box::new(match_query.clone())); // ?1 = MATCH

        if let Some(source) = query.filter.source.as_ref() {
            clauses.push("s.source = ?".to_string());
            bindings.push(Box::new(source.clone()));
        }
        if let Some(project) = query.filter.project_path.as_ref() {
            clauses.push("s.project_path = ?".to_string());
            bindings.push(Box::new(project.clone()));
        }
        if let Some(from) = query.filter.from.as_ref() {
            clauses.push("COALESCE(s.updated_at, s.created_at, '') >= ?".to_string());
            bindings.push(Box::new(from.clone()));
        }
        if let Some(to) = query.filter.to.as_ref() {
            clauses.push("COALESCE(s.updated_at, s.created_at, '') <= ?".to_string());
            bindings.push(Box::new(to.clone()));
        }
        if query.messages_only {
            clauses.push("m.kind = 'message'".to_string());
        }

        let extra = if clauses.is_empty() {
            String::new()
        } else {
            format!(" AND {}", clauses.join(" AND "))
        };
        // 多取一条用于判断 has_more
        let limit = query.limit.clamp(1, 500);
        // 排序：
        // - 相关度用 FTS5 的 `rank` 列（即 bm25），**不要**写成 `ORDER BY bm25(...)` 或它的别名：
        //   实测（100 万条消息 / 20 万命中）`ORDER BY rank` 约 280ms，而 `ORDER BY bm25()` 或别名约 520ms，
        //   因为后者会让 SQLite 无法复用同一次打分结果。
        // - 时间序不需要打分，直接按消息时间排序。
        let order = match query.order {
            SearchOrder::Relevance => "rank ASC",
            SearchOrder::Recent => "COALESCE(m.timestamp, '') DESC",
        };
        let sql = format!(
            "SELECT m.session_id, m.id, m.sequence, m.role, m.kind, m.timestamp,
                    snippet(message_fts, 0, '<mark>', '</mark>', '…', 18) AS snippet,
                    bm25(message_fts) AS score,
                    s.title, s.project_path, s.source, s.updated_at
             FROM message_fts
             JOIN messages m ON m.rowid = message_fts.rowid
             JOIN sessions s ON s.id = m.session_id
             WHERE message_fts MATCH ?1{extra}
             ORDER BY {order}
             LIMIT ? OFFSET ?"
        );
        bindings.push(Box::new(limit + 1));
        bindings.push(Box::new(query.offset.max(0)));

        let mut hits = self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(&sql)?;
            let rows = stmt
                .query_map(params_from_iter(bindings.iter()), |r| {
                    Ok(SearchHit {
                        session_id: r.get(0)?,
                        message_id: r.get(1)?,
                        sequence: r.get(2)?,
                        role: r.get(3)?,
                        kind: r.get(4)?,
                        timestamp: r.get(5)?,
                        snippet: r.get::<_, Option<String>>(6)?.unwrap_or_default(),
                        // bm25 越小越相关；取负值让「越大越相关」更符合直觉
                        score: -r.get::<_, f64>(7).unwrap_or(0.0),
                        title: r.get(8)?,
                        project_path: r.get(9)?,
                        source: r.get(10)?,
                        session_updated_at: r.get(11)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })?;

        let has_more = hits.len() as i64 > limit;
        if has_more {
            hits.truncate(limit as usize);
        }
        Ok(SearchResponse {
            hits,
            has_more,
            took_ms: start.elapsed().as_millis() as u64,
            match_query,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::sessions::MessageRow;
    use crate::storage::types::SessionStub;

    #[test]
    fn fts_查询构造安全() {
        // 普通关键词：全部加引号，最后词前缀匹配
        assert_eq!(build_match_query("lazy deletion"), "\"lazy\" \"deletion\"*");
        // 特殊字符被清理，不会构造出非法 FTS5 语法
        assert_eq!(build_match_query("NEAR(a b)"), "\"NEARa\" \"b\"*");
        assert_eq!(build_match_query("^foo:bar"), "\"foobar\"*");
        // 空白输入返回空串（调用方据此跳过搜索）
        assert_eq!(build_match_query("   "), "");
        // 引号被转义而非报错
        let q = build_match_query("\"quoted\"");
        assert!(q.starts_with('"'));
    }

    #[test]
    fn trigram_查询构造() {
        // 中文问题：滑窗 n-gram 全部加引号、OR 连接、去重（4 字 → 两个 3-gram + 一个 4-gram）
        let q = build_trigram_match_query("沙箱问题");
        assert_eq!(q, "\"沙箱问\" OR \"沙箱问题\" OR \"箱问题\"");
        // 过短输入（<3 字）trigram 无法工作，返回空串由调用方回退 unicode61
        assert_eq!(build_trigram_match_query("沙箱"), "");
        assert_eq!(build_trigram_match_query(""), "");
        // 混合输入：标点与空白被滤掉，拉丁与 CJK 统一成滑窗
        let q = build_trigram_match_query("codex 沙箱");
        assert!(q.contains("\"cod\""));
        assert!(q.contains("\"沙箱\"") == false, "2 字片段不足 3 字不应成词: {q}");
        assert!(q.contains(" OR "));
    }

    #[test]
    fn trigram_查询构造_端到端() {
        // 官方 schema（v2 起）自带 message_fts_trigram：构造查询 → MATCH → 句中子串命中
        let db = crate::storage::db::Database::open_in_memory().unwrap();
        db.upsert_session_stub(&crate::storage::types::SessionStub {
            id: "chatgpt:tri".into(),
            source: "chatgpt".into(),
            external_id: "tri".into(),
            source_root: None,
            primary_file: None,
        })
        .unwrap();
        db.insert_messages(&[MessageRow {
            id: "chatgpt:tri#0".into(),
            session_id: "chatgpt:tri".into(),
            sequence: 0,
            role: "user".into(),
            kind: "message".into(),
            text: Some("幻月桌宠的记忆引擎".into()),
            tool_name: None,
            timestamp: None,
            raw: None,
        }])
        .unwrap();

        let q = build_trigram_match_query("桌宠的记忆");
        assert!(!q.is_empty());
        let hits: i64 = db
            .with_conn(|conn| {
                Ok(conn.query_row(
                    "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH ?1",
                    [&q],
                    |r| r.get(0),
                )?)
            })
            .unwrap();
        assert_eq!(hits, 1, "trigram 端到端应命中句中子串");
    }

    /// 建一个只有一条消息的内存库。
    fn db_with_one_message(text: &str) -> Database {
        let db = Database::open_in_memory().unwrap();
        db.upsert_session_stub(&SessionStub {
            id: "kimi:rt".into(),
            source: "kimi".into(),
            external_id: "rt".into(),
            source_root: None,
            primary_file: None,
        })
        .unwrap();
        db.insert_messages(&[MessageRow {
            id: "kimi:rt#0".into(),
            session_id: "kimi:rt".into(),
            sequence: 0,
            role: "user".into(),
            kind: "message".into(),
            text: Some(text.into()),
            tool_name: None,
            timestamp: Some("2026-09-26T10:00:00+00:00".into()),
            raw: None,
        }])
        .unwrap();
        db
    }

    #[test]
    fn 写入_搜索_高亮往返() {
        let db = db_with_one_message("Redisson watchdog TTL lazy deletion 问题排查记录");
        let resp = db
            .search(&SearchQuery {
                text: "lazy deletion".into(),
                limit: 10,
                offset: 0,
                ..Default::default()
            })
            .unwrap();

        assert_eq!(resp.match_query, "\"lazy\" \"deletion\"*");
        assert_eq!(resp.hits.len(), 1, "应命中刚写入的消息");
        let hit = &resp.hits[0];
        assert_eq!(hit.session_id, "kimi:rt");
        assert_eq!(hit.message_id, "kimi:rt#0");
        assert_eq!(hit.role, "user");
        assert_eq!(hit.source, "kimi");
        assert!(
            hit.snippet.contains("<mark>"),
            "snippet 应带 <mark> 高亮: {}",
            hit.snippet
        );
        assert!(hit.score > 0.0, "bm25 取负后应大于 0: {}", hit.score);
        assert!(!resp.has_more);
    }

    #[test]
    fn 中文按连续字符串命中_已知限制行为基线() {
        // 已知限制（lib.rs 模块文档 / G05）：FTS5 unicode61 分词器不做中文分词，
        // 连续中文整体成为一个词元 —— 只有「从头开始的前缀」查询可命中，
        // 句中 / 句尾词检索不到。本测试固化当前行为基线；
        // 中文检索方案（字符 n-gram / 关键词 / 语义召回对比）待题集验证后替换（G05）。
        let db = db_with_one_message("幻月桌宠的记忆引擎");

        // 全串精确查询：命中（完整词元）
        let full = db
            .search(&SearchQuery {
                text: "幻月桌宠的记忆引擎".into(),
                limit: 10,
                offset: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(full.hits.len(), 1, "完整连续串应命中");

        // 从头前缀查询：命中（build_match_query 给末词加 *，前缀匹配词元）
        let prefix = db
            .search(&SearchQuery {
                text: "幻月".into(),
                limit: 10,
                offset: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(prefix.hits.len(), 1, "词元开头的前缀应命中");

        // 句中词：不命中（unicode61 不切开词元，已知限制）
        let mid = db
            .search(&SearchQuery {
                text: "桌宠".into(),
                limit: 10,
                offset: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(mid.hits.len(), 0, "句中词命中不了是已知限制的行为基线");

        // 句尾词：不命中（同上）
        let tail = db
            .search(&SearchQuery {
                text: "记忆引擎".into(),
                limit: 10,
                offset: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(tail.hits.len(), 0, "句尾词命中不了是已知限制的行为基线");
    }
}
