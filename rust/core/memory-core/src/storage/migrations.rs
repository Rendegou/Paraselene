//! 索引 schema 与迁移（schema 必须可演进）。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/storage/migrations.rs
//! 移植改动（单机裁剪）：
//! - sessions 表去掉 `machine_id` / `sync_status` / `archived` 列及对应索引；
//! - 去掉 `sync_files` 表（多机同步不在本片范围）；
//! - 迁移日志去掉 tracing 调用（本片依赖清单不含 tracing）。
//!
//! 约定：
//! - 版本号保存在 SQLite 的 `user_version`；
//! - 每个版本对应一个 SQL 脚本，按顺序执行，只增不改；
//! - FTS5 使用 **external content** 表（`content='messages'`）+ 触发器同步，
//!   索引里不重复存储正文，节省约一半磁盘空间，也不会出现索引与正文不一致。

use rusqlite::Connection;

use crate::error::{Error, Result};
use crate::model::INDEX_SCHEMA_VERSION;

/// 迁移脚本列表：下标 + 1 即目标版本号。
///
/// v2（G05 评测结论，2026-09-26）：新增 `message_fts_trigram`（trigram 分词）。
/// unicode61 不做中文分词（题集实测 recall@5 0/24），trigram + n-gram OR 达 23/24，
/// 两表并存：拉丁短词 / 前缀走 unicode61，中文 / 子串走 trigram（查询侧按脚本路由）。
///
/// v3（T02 第一片）：四空间用户确认层（Goal §4.2）。叠加在原始导入会话之上，
/// 原始 messages 表不动；跨空间链接只允许经 spaces::link_memories 显式写入。
///
/// v4（T02 第二片）：trigram 索引瘦身（真实库实测：1.51GB 库中 trigram 约 885MB，
/// 其中 role='tool' 的工具输出占 trigram postings 约 3/4——体积大头且检索价值低）。
/// - tool 角色不进 trigram FTS（精确词检索仍可由 unicode61 的 message_fts 覆盖）；
/// - 文本截 4096 字符入索引（原文完整保留在 messages 表，FTS 只索引前缀）；
/// - 表形态从 external content 改为**独立表**：「索引前缀」与 external content 的
///   rebuild 语义不兼容（rebuild 按内容表全文重建，与触发器写入的截断文本不一致，
///   integrity-check 会失败）；独立表用 DELETE FROM ... WHERE rowid 维护，更直接。
///
/// - v5（T05 第一片）：小说文档的确认版本树和独立试写区。
/// - v6（T06 第一片）：学习练习轨迹；只有后端已判定的测试结果可记录。
/// - v7（T05B 第一片）：长篇工作台底座。
/// - v8（T05C 第一片）：安全 patch 持久化。
/// - v9（T05D 第一片）：设定集与出处锚点。
/// - v10（T05E 第二片）：派生摘要与重建队列。
const MIGRATIONS: &[&str] = &[
    V1_INITIAL,
    V2_TRIGRAM,
    V3_SPACES,
    V4_TRIGRAM_SLIM,
    V5_NOVEL,
    V6_LEARNING,
    V7_NOVEL_WORKBENCH,
    V8_NOVEL_PATCHES,
    V9_LORE_ANCHORS,
    V10_DERIVED_SUMMARIES,
    include_str!("client_mvp_v11.sql"),
    include_str!("client_mvp_v12.sql"),
];

/// 执行迁移（幂等，可重复调用）。
pub fn migrate(conn: &mut Connection) -> Result<()> {
    let current: u32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current > INDEX_SCHEMA_VERSION {
        return Err(Error::config(format!(
            "索引版本 {current} 高于当前程序支持的 {INDEX_SCHEMA_VERSION}，请升级应用"
        )));
    }
    for (index, script) in MIGRATIONS.iter().enumerate() {
        let version = (index + 1) as u32;
        if version <= current {
            continue;
        }
        let tx = conn.transaction()?;
        tx.execute_batch(script)?;
        // user_version 不支持参数绑定，这里只拼接受控的常量数字
        tx.execute_batch(&format!("PRAGMA user_version = {version};"))?;
        tx.commit()?;
    }
    Ok(())
}

/// v1：初始 schema。
const V1_INITIAL: &str = r#"
-- 数据源：探测结果与用户配置的路径
CREATE TABLE IF NOT EXISTS sources (
    id            TEXT PRIMARY KEY,
    display_name  TEXT NOT NULL,
    root_path     TEXT,
    found         INTEGER NOT NULL DEFAULT 0,
    session_hint  INTEGER NOT NULL DEFAULT 0,
    manual        INTEGER NOT NULL DEFAULT 0,
    notes         TEXT,
    detected_at   TEXT
);

-- 会话
CREATE TABLE IF NOT EXISTS sessions (
    id                  TEXT PRIMARY KEY,
    source              TEXT NOT NULL,
    external_session_id TEXT NOT NULL,
    title               TEXT,
    project_path        TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    content_hash        TEXT,
    message_count       INTEGER NOT NULL DEFAULT 0,
    partial             INTEGER NOT NULL DEFAULT 0,
    metadata            TEXT,
    source_root         TEXT,
    primary_file        TEXT,
    indexed_at          TEXT,
    UNIQUE (source, external_session_id)
);
CREATE INDEX IF NOT EXISTS idx_sessions_updated   ON sessions (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_source    ON sessions (source, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_project   ON sessions (project_path, updated_at DESC);

-- 消息
CREATE TABLE IF NOT EXISTS messages (
    id         TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    role       TEXT NOT NULL,
    kind       TEXT NOT NULL,
    text       TEXT,
    tool_name  TEXT,
    timestamp  TEXT,
    sequence   INTEGER NOT NULL,
    raw        TEXT
);
CREATE INDEX IF NOT EXISTS idx_messages_session_seq ON messages (session_id, sequence);

-- 原始文件与指纹（增量扫描的核心）
CREATE TABLE IF NOT EXISTS raw_files (
    path       TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    source     TEXT NOT NULL,
    role       TEXT NOT NULL,
    size       INTEGER NOT NULL,
    mtime      INTEGER NOT NULL,
    hash       TEXT,
    indexed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_raw_files_session ON raw_files (session_id);

-- 键值设置（运行状态）
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- 全文索引：external content，正文不重复存储
CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
    text,
    session_id UNINDEXED,
    content='messages',
    content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2'
);

-- 触发器保持 FTS 与 messages 一致
CREATE TRIGGER IF NOT EXISTS messages_fts_ai AFTER INSERT ON messages BEGIN
    INSERT INTO message_fts (rowid, text, session_id) VALUES (new.rowid, new.text, new.session_id);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_ad AFTER DELETE ON messages BEGIN
    INSERT INTO message_fts (message_fts, rowid, text, session_id)
    VALUES ('delete', old.rowid, old.text, old.session_id);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_au AFTER UPDATE ON messages BEGIN
    INSERT INTO message_fts (message_fts, rowid, text, session_id)
    VALUES ('delete', old.rowid, old.text, old.session_id);
    INSERT INTO message_fts (rowid, text, session_id) VALUES (new.rowid, new.text, new.session_id);
END;
"#;

/// v2：trigram 全文索引（G05 中文检索方案，与 unicode61 并存）。
///
/// trigram 把文本切成重叠三元组，天然支持任意子串匹配（中文整串成词问题不复存在）；
/// 代价是查询词必须 ≥3 字符，所以短拉丁词仍走 unicode61 的 message_fts。
const V2_TRIGRAM: &str = r#"
CREATE VIRTUAL TABLE IF NOT EXISTS message_fts_trigram USING fts5(
    text,
    session_id UNINDEXED,
    content='messages',
    content_rowid='rowid',
    tokenize='trigram'
);

CREATE TRIGGER IF NOT EXISTS messages_fts_tri_ai AFTER INSERT ON messages BEGIN
    INSERT INTO message_fts_trigram (rowid, text, session_id) VALUES (new.rowid, new.text, new.session_id);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_tri_ad AFTER DELETE ON messages BEGIN
    INSERT INTO message_fts_trigram (message_fts_trigram, rowid, text, session_id)
    VALUES ('delete', old.rowid, old.text, old.session_id);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_tri_au AFTER UPDATE ON messages BEGIN
    INSERT INTO message_fts_trigram (message_fts_trigram, rowid, text, session_id)
    VALUES ('delete', old.rowid, old.text, old.session_id);
    INSERT INTO message_fts_trigram (rowid, text, session_id) VALUES (new.rowid, new.text, new.session_id);
END;

-- 存量数据回填（external content 表建表后必须 rebuild 一次才有索引；
-- 注意不能用 SELECT count(*) 判断是否需要 rebuild——external content 表的
-- count 读的是内容表 messages，永远非零）
INSERT INTO message_fts_trigram (message_fts_trigram) VALUES ('rebuild');
"#;

/// v3：四空间用户确认层（Goal §4.2）。
///
/// 设计要点：
/// - 四空间是**叠加在原始导入会话之上的用户确认层**，原始 messages 表不动；
/// - 隔离规则尽量下沉到 DDL CHECK（space 枚举、novel⇒work_id 必填、非 novel⇒
///   禁止 work_id、anchor 长度、禁止自链接），API 层再补人话错误信息；
/// - `memory_links` 只允许通过显式用户动作 API 写入（`spaces::link_memories`、
///   `ideas::convert_idea`）——跨空间引用必须由用户触发（Goal §4.2 红线），
///   任何自动/批量写入路径都不得碰这张表；
/// - `memory_sources.session_id` 故意**不加外键**：出处链要在会话被清理 /
///   重新导入后仍然可展示（session_id 字符串 + anchor 已足够定位来源），
///   级联删除反而会把用户确认过的出处证据抹掉。
const V3_SPACES: &str = r#"
-- 小说作品作用域（小说记忆按作品隔离，Goal §4.2）
CREATE TABLE IF NOT EXISTS works (
    id          TEXT PRIMARY KEY,
    space       TEXT NOT NULL DEFAULT 'novel' CHECK (space = 'novel'),
    title       TEXT NOT NULL,
    created_at  TEXT NOT NULL
);

-- 四空间记忆（用户确认层）
CREATE TABLE IF NOT EXISTS memories (
    id             TEXT PRIMARY KEY,
    space          TEXT NOT NULL CHECK (space IN ('personal','idea','novel','learning')),
    work_id        TEXT REFERENCES works (id),
    kind           TEXT NOT NULL,
    title          TEXT NOT NULL,
    summary        TEXT,
    -- 状态机仅 idea 空间使用（liked|started|done|shelved|wrong），其他空间必须为 NULL
    status         TEXT CHECK (status IS NULL OR status IN ('liked','started','done','shelved','wrong')),
    reminder_pref  TEXT,
    payload        TEXT,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL,
    deleted_at     TEXT,
    -- 小说记忆必须挂在作品下；其他空间禁止挂作品（作品是小说空间的隔离边界）
    CHECK (space != 'novel' OR work_id IS NOT NULL),
    CHECK (space = 'novel' OR work_id IS NULL)
);
CREATE INDEX IF NOT EXISTS idx_memories_space_status ON memories (space, status);

-- 出处链：记忆 → 会话 + 消息位置 + 短引用（G08/G17 依赖）
CREATE TABLE IF NOT EXISTS memory_sources (
    id           INTEGER PRIMARY KEY,
    memory_id    TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
    session_id   TEXT NOT NULL,
    message_seq  INTEGER,
    anchor       TEXT CHECK (anchor IS NULL OR length(anchor) <= 120)
);
CREATE INDEX IF NOT EXISTS idx_memory_sources_memory ON memory_sources (memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_sources_session ON memory_sources (session_id);
-- 同一出处只允许一条（message_seq 为 NULL 时用 -1 归一，避免 SQLite UNIQUE 对 NULL 不去重）
CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_sources_dedup
    ON memory_sources (memory_id, session_id, IFNULL(message_seq, -1));

-- 跨空间链接（红线：只允许显式 API 写入，Goal §4.2「跨空间引用必须由用户触发」）
CREATE TABLE IF NOT EXISTS memory_links (
    from_id    TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
    to_id      TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
    actor      TEXT NOT NULL DEFAULT 'user',
    created_at TEXT NOT NULL,
    PRIMARY KEY (from_id, to_id),
    CHECK (from_id <> to_id)
);
CREATE INDEX IF NOT EXISTS idx_memory_links_to ON memory_links (to_id);
"#;

/// v4：trigram 索引瘦身（测量依据见 examples/measure_fts.rs 与 docs 记录）。
///
/// 两条规则在触发器与回填 SQL 中必须逐字一致：
/// 1. role='tool' 不进 trigram（工具输出占 trigram postings 约 3/4，检索价值低；
///    精确词检索仍由 unicode61 的 message_fts 全量覆盖）；
/// 2. 文本截 4096 **字符**入索引（SUBSTR 按字符计；原文完整保留在 messages 表）。
const V4_TRIGRAM_SLIM: &str = r#"
DROP TRIGGER IF EXISTS messages_fts_tri_ai;
DROP TRIGGER IF EXISTS messages_fts_tri_ad;
DROP TRIGGER IF EXISTS messages_fts_tri_au;
DROP TABLE IF EXISTS message_fts_trigram;

-- 独立 trigram 表（自带截断文本；不再 external content——前缀索引与 rebuild 语义不兼容）
CREATE VIRTUAL TABLE message_fts_trigram USING fts5(
    text,
    session_id UNINDEXED,
    tokenize='trigram'
);

-- 独立 FTS 表直接用 DELETE ... WHERE rowid 维护（external content 的 'delete' 命令
-- 需要与插入值完全匹配，独立表没这个负担）
CREATE TRIGGER messages_fts_tri_ai AFTER INSERT ON messages
WHEN new.role != 'tool' AND new.text IS NOT NULL BEGIN
    INSERT INTO message_fts_trigram (rowid, text, session_id)
    VALUES (new.rowid, SUBSTR(new.text, 1, 4096), new.session_id);
END;

CREATE TRIGGER messages_fts_tri_ad AFTER DELETE ON messages BEGIN
    DELETE FROM message_fts_trigram WHERE rowid = old.rowid;
END;

CREATE TRIGGER messages_fts_tri_au AFTER UPDATE ON messages BEGIN
    DELETE FROM message_fts_trigram WHERE rowid = old.rowid;
    INSERT INTO message_fts_trigram (rowid, text, session_id)
    SELECT new.rowid, SUBSTR(new.text, 1, 4096), new.session_id
    WHERE new.role != 'tool' AND new.text IS NOT NULL;
END;

-- 存量回填（与触发器同一套规则）
INSERT INTO message_fts_trigram (rowid, text, session_id)
SELECT rowid, SUBSTR(text, 1, 4096), session_id FROM messages
WHERE role != 'tool' AND text IS NOT NULL;
"#;

/// v5：试写不在正稿表中，后续上下文只能从文档当前 head 读取。
const V5_NOVEL: &str = r#"
CREATE TABLE novel_documents (
    id              TEXT PRIMARY KEY,
    work_id         TEXT NOT NULL REFERENCES works (id) ON DELETE CASCADE,
    kind            TEXT NOT NULL CHECK (kind IN ('chapter','character','world','timeline','taboo')),
    title           TEXT NOT NULL,
    head_version_id TEXT,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);
CREATE INDEX idx_novel_documents_work ON novel_documents (work_id, kind, updated_at);

CREATE TABLE novel_versions (
    id                TEXT PRIMARY KEY,
    document_id       TEXT NOT NULL REFERENCES novel_documents (id) ON DELETE CASCADE,
    parent_version_id TEXT REFERENCES novel_versions (id),
    body              TEXT NOT NULL,
    origin            TEXT NOT NULL CHECK (origin IN ('user','accepted_draft')),
    created_at        TEXT NOT NULL
);
CREATE INDEX idx_novel_versions_document ON novel_versions (document_id, created_at);

CREATE TABLE novel_drafts (
    id              TEXT PRIMARY KEY,
    document_id     TEXT NOT NULL REFERENCES novel_documents (id) ON DELETE CASCADE,
    base_version_id TEXT,
    body            TEXT NOT NULL,
    origin          TEXT NOT NULL CHECK (origin IN ('user','ai')),
    status          TEXT NOT NULL CHECK (status IN ('pending','accepted','discarded')),
    created_at      TEXT NOT NULL,
    resolved_at     TEXT
);
CREATE INDEX idx_novel_drafts_document ON novel_drafts (document_id, status, created_at);
"#;

/// v6：与旧想法转成的 learning goal 关联，不复用跨空间记忆 payload。
const V6_LEARNING: &str = r#"
CREATE TABLE learning_attempts (
    id             TEXT PRIMARY KEY,
    goal_memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
    exercise_id    TEXT NOT NULL,
    code           TEXT NOT NULL,
    passed         INTEGER NOT NULL CHECK (passed IN (0, 1)),
    passed_count   INTEGER NOT NULL CHECK (passed_count >= 0),
    total_count    INTEGER NOT NULL CHECK (total_count > 0 AND passed_count <= total_count),
    hint_level     INTEGER NOT NULL CHECK (hint_level BETWEEN 0 AND 3),
    weak_topic     TEXT,
    created_at     TEXT NOT NULL
);
CREATE INDEX idx_learning_attempts_goal ON learning_attempts (goal_memory_id, created_at, id);
"#;

/// v7：长篇工作台底座（T05B）。
/// - 显式章序 `order_index`：目录顺序是用户承诺，不再由创建时间隐含表达；
///   存量行按升级前的既有展示顺序（类型分组 + created_at + id）回填，保持观感不变。
/// - `working_copies`：本机编辑稿（自动保存），乐观锁 revision；不是正稿，
///   只有用户确认才进入 novel_versions。
const V7_NOVEL_WORKBENCH: &str = r#"
ALTER TABLE novel_documents ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0;
UPDATE novel_documents SET order_index = (
    SELECT COUNT(*) FROM novel_documents older
    WHERE older.work_id = novel_documents.work_id
      AND (CASE older.kind WHEN 'character' THEN 0 WHEN 'world' THEN 1 WHEN 'timeline' THEN 2 WHEN 'taboo' THEN 3 ELSE 4 END,
           older.created_at, older.id)
        < (CASE novel_documents.kind WHEN 'character' THEN 0 WHEN 'world' THEN 1 WHEN 'timeline' THEN 2 WHEN 'taboo' THEN 3 ELSE 4 END,
           novel_documents.created_at, novel_documents.id)
);
CREATE INDEX idx_novel_documents_order ON novel_documents (work_id, order_index, created_at, id);

CREATE TABLE working_copies (
    document_id       TEXT PRIMARY KEY REFERENCES novel_documents (id) ON DELETE CASCADE,
    base_head_version TEXT,
    revision          INTEGER NOT NULL CHECK (revision > 0),
    body              TEXT NOT NULL,
    content_hash      TEXT NOT NULL,
    saved_at          TEXT NOT NULL
);
"#;

/// v8：安全 patch。块与绑定条件整体存 JSON（块结构由 novel-core 定义并演进）；
/// status 机 pending→applied/rejected 由命令层原子翻转，防重复应用。
const V8_NOVEL_PATCHES: &str = r#"
CREATE TABLE novel_patches (
    id                    TEXT PRIMARY KEY,
    document_id           TEXT NOT NULL REFERENCES novel_documents (id) ON DELETE CASCADE,
    base_head_version     TEXT,
    base_working_revision INTEGER,
    quote_hash            TEXT NOT NULL,
    blocks_json           TEXT NOT NULL,
    status                TEXT NOT NULL CHECK (status IN ('pending','applied','rejected')),
    created_at            TEXT NOT NULL,
    resolved_at           TEXT
);
CREATE INDEX idx_novel_patches_document ON novel_patches (document_id, created_at);
"#;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::INDEX_SCHEMA_VERSION;

    #[test]
    fn 迁移可重复执行且版本正确() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap(); // 幂等
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);
    }

    #[test]
    fn fts5_可用且触发器同步() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('kimi:1','kimi','1')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:1#0','kimi:1','user','message','Redisson watchdog TTL lazy deletion',0)",
            [],
        )
        .unwrap();
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH 'lazy'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 1, "FTS5 索引应能查到刚插入的消息");

        // 删除消息后索引同步移除
        conn.execute("DELETE FROM messages WHERE id = 'kimi:1#0'", [])
            .unwrap();
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH 'lazy'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 0);
    }

    #[test]
    fn insert_or_replace_不会让_fts_残留旧内容() {
        // 回归测试：SQLite 默认在 REPLACE 冲突时**不触发** DELETE 触发器，
        // 会让 FTS5 外部内容表残留旧索引项（索引与正文不一致）。
        // 因此数据库连接必须开启 `recursive_triggers`（见 storage::db::Database::prepare）。
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        conn.execute_batch("PRAGMA recursive_triggers = ON;")
            .unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('kimi:r','kimi','r')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:r#0','kimi:r','user','message','旧的唯一词 alpha',0)",
            [],
        )
        .unwrap();
        // 同 id 覆盖写入：旧文本必须从索引里消失
        conn.execute(
            "INSERT OR REPLACE INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:r#0','kimi:r','user','message','新的唯一词 beta',0)",
            [],
        )
        .unwrap();

        let old_hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH 'alpha'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let new_hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH 'beta'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(old_hits, 0, "REPLACE 后旧内容不应残留");
        assert_eq!(new_hits, 1, "REPLACE 后新内容应可检索");

        // 索引完整性检查（不一致时会报错）
        conn.execute_batch("INSERT INTO message_fts (message_fts) VALUES ('integrity-check');")
            .unwrap();
    }

    #[test]
    fn 级联删除会话消息() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('codex:1','codex','1')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, sequence)
             VALUES ('codex:1#0','codex:1','user','message',0)",
            [],
        )
        .unwrap();
        conn.execute("DELETE FROM sessions WHERE id = 'codex:1'", [])
            .unwrap();
        let left: i64 = conn
            .query_row("SELECT count(*) FROM messages", [], |r| r.get(0))
            .unwrap();
        assert_eq!(left, 0);
    }

    #[test]
    fn trigram_表随迁移创建且触发器同步() {
        // G05 中文方案：trigram 支持任意子串匹配（unicode61 只能整串/前缀）
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('chatgpt:t','chatgpt','t')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('chatgpt:t#0','chatgpt:t','user','message','幻月桌宠的记忆引擎',0)",
            [],
        )
        .unwrap();
        // 句中子串（unicode61 命中不了，trigram 必须命中）
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH '\"桌宠的记\"'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 1, "trigram 应支持句中子串匹配");
        // 触发器同步：删除后索引移除
        conn.execute("DELETE FROM messages WHERE id = 'chatgpt:t#0'", [])
            .unwrap();
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH '\"桌宠的记\"'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 0);
    }

    #[test]
    fn trigram_瘦身规则_tool不进索引且文本截断() {
        // V4 规则：role='tool' 不进 trigram（体积大头、检索价值低），
        // 文本截 4096 字符入索引（原文完整保留在 messages 表）。
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('kimi:v4','kimi','v4')",
            [],
        )
        .unwrap();
        // tool 角色：unicode61 可命中，trigram 不可命中
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:v4#0','kimi:v4','tool','tool_result','工具输出的唯一锚词 zvqtool',0)",
            [],
        )
        .unwrap();
        // 长文本：前缀内可命中，超出 4096 字符的部分不进索引
        // （前×4097 占满字符位 1..=4097，尾部锚词从 4098 起，必在截断点之后）
        let long_text = format!("{}{}", "前".repeat(4097), "尾部唯一锚词 zvqtail");
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:v4#1','kimi:v4','user','message',?1,1)",
            [&long_text],
        )
        .unwrap();

        let tri = |gram: &str| -> i64 {
            conn.query_row(
                "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH ?1",
                [format!("\"{gram}\"")],
                |r| r.get(0),
            )
            .unwrap()
        };
        let uni = |term: &str| -> i64 {
            conn.query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH ?1",
                [term],
                |r| r.get(0),
            )
            .unwrap()
        };
        assert_eq!(tri("vqtool"), 0, "tool 角色不应进 trigram");
        assert_eq!(
            uni("zvqtool"),
            1,
            "tool 角色仍应被 unicode61 覆盖（精确词检索）"
        );
        assert_eq!(
            tri("尾部唯一锚"),
            0,
            "超出 4096 字符的部分不应入 trigram 索引"
        );
        assert_eq!(tri("前前前"), 1, "前缀内的内容应正常入 trigram 索引");
        // 原文不受索引规则影响：messages 表仍存全文
        let full: String = conn
            .query_row(
                "SELECT text FROM messages WHERE id = 'kimi:v4#1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert!(
            full.contains("尾部唯一锚词"),
            "原文必须完整保留在 messages 表"
        );
    }

    #[test]
    fn v1_库升级后_trigram_回填存量数据() {
        // 模拟已有 v1 库（只有 unicode61 索引）：迁移到 v2 时 rebuild 必须回填存量消息，
        // 否则老库升级后 trigram 检索为空（external content 表建表时索引是空的）。
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(V1_INITIAL).unwrap();
        conn.execute_batch("PRAGMA user_version = 1;").unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('chatgpt:old','chatgpt','old')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('chatgpt:old#0','chatgpt:old','user','message','存量消息的任意子串锚点xyz',0)",
            [],
        )
        .unwrap();

        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH '\"意子串锚\"'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 1, "迁移 rebuild 必须回填存量消息");
    }

    #[test]
    fn v2_库升级后_四空间表就绪且数据不丢() {
        // 模拟已有 v2 库（有会话与消息，无四空间表）：迁移到 v3 后
        // 存量数据一条不丢，新表可用，DDL 级 CHECK 约束生效。
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(V1_INITIAL).unwrap();
        conn.execute_batch(V2_TRIGRAM).unwrap();
        conn.execute_batch("PRAGMA user_version = 2;").unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('kimi:keep','kimi','keep')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:keep#0','kimi:keep','user','message','迁移前数据',0)",
            [],
        )
        .unwrap();

        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);

        // 存量数据不丢
        let sessions: i64 = conn
            .query_row("SELECT count(*) FROM sessions", [], |r| r.get(0))
            .unwrap();
        let messages: i64 = conn
            .query_row("SELECT count(*) FROM messages", [], |r| r.get(0))
            .unwrap();
        assert_eq!(sessions, 1);
        assert_eq!(messages, 1);
        // 旧索引仍可用
        let hits: i64 = conn
            .query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH '迁移前数据'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(hits, 1);

        // 新表可用：works / memories / memory_sources / memory_links
        conn.execute(
            "INSERT INTO works (id, space, title, created_at) VALUES ('w1','novel','作品','2026-09-26T00:00:00Z')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO memories (id, space, work_id, kind, title, created_at, updated_at)
             VALUES ('m1','novel','w1','setting','设定','2026-09-26T00:00:00Z','2026-09-26T00:00:00Z')",
            [],
        )
        .unwrap();
        // DDL 级约束：novel 无 work_id 必须失败
        let bad = conn.execute(
            "INSERT INTO memories (id, space, kind, title, created_at, updated_at)
             VALUES ('m2','novel','setting','无作品','2026-09-26T00:00:00Z','2026-09-26T00:00:00Z')",
            [],
        );
        assert!(bad.is_err(), "novel 记忆缺少 work_id 应被 DDL 拒绝");
        // DDL 级约束：非 novel 挂 work_id 必须失败
        let bad2 = conn.execute(
            "INSERT INTO memories (id, space, work_id, kind, title, created_at, updated_at)
             VALUES ('m3','personal','w1','note','个人挂作品','2026-09-26T00:00:00Z','2026-09-26T00:00:00Z')",
            [],
        );
        assert!(bad2.is_err(), "非 novel 记忆挂 work_id 应被 DDL 拒绝");
        // DDL 级约束：anchor 超 120 字必须失败
        let long_anchor = "长".repeat(121);
        let bad3 = conn.execute(
            "INSERT INTO memory_sources (memory_id, session_id, message_seq, anchor)
             VALUES ('m1','kimi:keep',0,?1)",
            [&long_anchor],
        );
        assert!(bad3.is_err(), "anchor 超 120 字应被 DDL 拒绝");
        // 出处链正常写入 + 外键级联（记忆删除 → 出处删除）
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn.execute(
            "INSERT INTO memory_sources (memory_id, session_id, message_seq, anchor)
             VALUES ('m1','kimi:keep',0,'短引用')",
            [],
        )
        .unwrap();
        conn.execute("DELETE FROM memories WHERE id = 'm1'", [])
            .unwrap();
        let sources: i64 = conn
            .query_row("SELECT count(*) FROM memory_sources", [], |r| r.get(0))
            .unwrap();
        assert_eq!(sources, 0, "记忆删除后出处应级联删除");
        // DDL 级约束：自链接必须失败
        let bad4 = conn.execute(
            "INSERT INTO memory_links (from_id, to_id, created_at) VALUES ('m1','m1','2026-09-26T00:00:00Z')",
            [],
        );
        assert!(bad4.is_err(), "自链接应被 DDL 拒绝");
    }

    #[test]
    fn v3_库升级后_trigram_瘦身重建() {
        // 模拟已有 v3 库（external content trigram）：迁移到 v4 后
        // trigram 表换为独立表并按瘦身规则回填——tool 行不进索引、长文本只索引前缀，
        // 存量消息一条不丢，unicode61 索引不受影响。
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(V1_INITIAL).unwrap();
        conn.execute_batch(V2_TRIGRAM).unwrap();
        conn.execute_batch(V3_SPACES).unwrap();
        conn.execute_batch("PRAGMA user_version = 3;").unwrap();
        conn.execute(
            "INSERT INTO sessions (id, source, external_session_id) VALUES ('kimi:v3','kimi','v3')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:v3#0','kimi:v3','user','message','用户消息锚词 zvquser',0)",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO messages (id, session_id, role, kind, text, sequence)
             VALUES ('kimi:v3#1','kimi:v3','tool','tool_result','工具输出锚词 zvqtool',1)",
            [],
        )
        .unwrap();

        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);

        // 表形态：独立表（不再引用 messages 作为内容表）
        let sql: String = conn
            .query_row(
                "SELECT sql FROM sqlite_master WHERE name = 'message_fts_trigram'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert!(
            !sql.contains("content='messages'"),
            "v4 起 trigram 必须是独立表"
        );

        // 数据不丢
        let messages: i64 = conn
            .query_row("SELECT count(*) FROM messages", [], |r| r.get(0))
            .unwrap();
        assert_eq!(messages, 2);

        // 回填规则：user 在、tool 不在、unicode61 两者都在
        let tri = |gram: &str| -> i64 {
            conn.query_row(
                "SELECT count(*) FROM message_fts_trigram WHERE message_fts_trigram MATCH ?1",
                [format!("\"{gram}\"")],
                |r| r.get(0),
            )
            .unwrap()
        };
        let uni = |term: &str| -> i64 {
            conn.query_row(
                "SELECT count(*) FROM message_fts WHERE message_fts MATCH ?1",
                [term],
                |r| r.get(0),
            )
            .unwrap()
        };
        assert_eq!(tri("vquser"), 1, "存量 user 消息应回填进 trigram");
        assert_eq!(tri("vqtool"), 0, "存量 tool 消息不应回填进 trigram");
        assert_eq!(uni("zvquser"), 1);
        assert_eq!(
            uni("zvqtool"),
            1,
            "unicode61 索引不受影响，tool 仍可精确检索"
        );

        // 新触发器在迁移后依然同步（独立表按 rowid 删除）
        conn.execute("DELETE FROM messages WHERE id = 'kimi:v3#0'", [])
            .unwrap();
        assert_eq!(tri("vquser"), 0, "删除消息后 trigram 同步移除");
    }

    #[test]
    fn v4_库升级后_小说表可用且原作品记忆不丢() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn.execute_batch(V1_INITIAL).unwrap();
        conn.execute_batch(V2_TRIGRAM).unwrap();
        conn.execute_batch(V3_SPACES).unwrap();
        conn.execute_batch(V4_TRIGRAM_SLIM).unwrap();
        conn.execute_batch("PRAGMA user_version = 4;").unwrap();
        conn.execute(
            "INSERT INTO works (id, title, created_at) VALUES ('old-work', '旧作品', '2026-09-26')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO memories (id, space, work_id, kind, title, created_at, updated_at)
             VALUES ('old-note', 'novel', 'old-work', 'inspiration', '原有灵感', '2026-09-26', '2026-09-26')", [],
        ).unwrap();

        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        let old_work: i64 = conn
            .query_row(
                "SELECT count(*) FROM works WHERE id = 'old-work'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let old_note: i64 = conn
            .query_row(
                "SELECT count(*) FROM memories WHERE id = 'old-note'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);
        assert_eq!((old_work, old_note), (1, 1));
        conn.execute(
            "INSERT INTO novel_documents (id, work_id, kind, title, created_at, updated_at)
             VALUES ('chapter-1', 'old-work', 'chapter', '开头', '2026-09-27', '2026-09-27')",
            [],
        )
        .unwrap();
        let docs: i64 = conn
            .query_row(
                "SELECT count(*) FROM novel_documents WHERE work_id = 'old-work'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(docs, 1);
    }

    #[test]
    fn v5_升级到学习轨迹不改旧小说与学习目标() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        for script in [V1_INITIAL, V2_TRIGRAM, V3_SPACES, V4_TRIGRAM_SLIM, V5_NOVEL] {
            conn.execute_batch(script).unwrap();
        }
        conn.execute_batch("PRAGMA user_version = 5;").unwrap();
        conn.execute(
            "INSERT INTO works (id, title, created_at) VALUES ('work', '旧作品', '2026-09-27')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO novel_documents (id, work_id, kind, title, created_at, updated_at)
            VALUES ('chapter', 'work', 'chapter', '开头', '2026-09-27', '2026-09-27')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO memories (id, space, kind, title, created_at, updated_at)
            VALUES ('goal', 'learning', 'goal', '练 Python', '2026-09-27', '2026-09-27')",
            [],
        )
        .unwrap();
        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        let old_chapter: i64 = conn
            .query_row(
                "SELECT count(*) FROM novel_documents WHERE id = 'chapter'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let old_goal: i64 = conn
            .query_row("SELECT count(*) FROM memories WHERE id = 'goal'", [], |r| {
                r.get(0)
            })
            .unwrap();
        let attempts: i64 = conn
            .query_row("SELECT count(*) FROM learning_attempts", [], |r| r.get(0))
            .unwrap();
        assert_eq!(
            (version, old_chapter, old_goal, attempts),
            (INDEX_SCHEMA_VERSION, 1, 1, 0)
        );
    }

    #[test]
    fn v7_升级后_章序保持既有展示顺序() {
        // 模拟已有 v6 库：一部作品下三份章节，created_at 乱序插入；
        // 迁移到 v7 后 order_index 必须复现旧查询（类型分组 + created_at + id）的
        // 相对顺序——升级不改观感，只把顺序从"隐含"变为"可重排的显式承诺"。
        let mut conn = Connection::open_in_memory().unwrap();
        for script in [
            V1_INITIAL,
            V2_TRIGRAM,
            V3_SPACES,
            V4_TRIGRAM_SLIM,
            V5_NOVEL,
            V6_LEARNING,
        ] {
            conn.execute_batch(script).unwrap();
        }
        conn.execute_batch("PRAGMA user_version = 6;").unwrap();
        conn.execute(
            "INSERT INTO works (id, space, title, created_at) VALUES ('w1','novel','作品','2026-10-01T00:00:00Z')",
            [],
        )
        .unwrap();
        for (id, title, created) in [
            ("c1", "第一章", "2026-10-02T00:00:00Z"),
            ("c2", "第二章", "2026-10-01T00:00:00Z"),
            ("c3", "第三章", "2026-10-03T00:00:00Z"),
        ] {
            conn.execute(
                "INSERT INTO novel_documents (id, work_id, kind, title, created_at, updated_at)
                 VALUES (?1,'w1','chapter',?2,?3,?3)",
                rusqlite::params![id, title, created],
            )
            .unwrap();
        }

        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap(); // 幂等
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, INDEX_SCHEMA_VERSION);

        let mut stmt = conn
            .prepare(
                "SELECT id FROM novel_documents WHERE work_id = 'w1'
                 ORDER BY order_index, created_at, id",
            )
            .unwrap();
        let ordered: Vec<String> = stmt
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(|row| row.unwrap())
            .collect();
        assert_eq!(ordered, vec!["c2", "c1", "c3"], "回填顺序应等于旧展示顺序");
    }

    #[test]
    fn v7_编辑稿表就绪且随文档级联删除() {
        let mut conn = Connection::open_in_memory().unwrap();
        for script in [
            V1_INITIAL,
            V2_TRIGRAM,
            V3_SPACES,
            V4_TRIGRAM_SLIM,
            V5_NOVEL,
            V6_LEARNING,
        ] {
            conn.execute_batch(script).unwrap();
        }
        conn.execute_batch("PRAGMA user_version = 6;").unwrap();
        conn.execute(
            "INSERT INTO works (id, space, title, created_at) VALUES ('w1','novel','作品','2026-10-01T00:00:00Z')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO novel_documents (id, work_id, kind, title, created_at, updated_at)
             VALUES ('c1','w1','chapter','第一章','2026-10-01T00:00:00Z','2026-10-01T00:00:00Z')",
            [],
        )
        .unwrap();

        migrate(&mut conn).unwrap();
        conn.execute(
            "INSERT INTO novel_versions (id, document_id, parent_version_id, body, origin, created_at)
             VALUES ('v1','c1',NULL,'正文','user','2026-10-01T01:00:00Z')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO working_copies (document_id, base_head_version, revision, body, content_hash, saved_at)
             VALUES ('c1','v1',1,'编辑稿','h','2026-10-03T00:00:00Z')",
            [],
        )
        .unwrap();
        let wc: (String, i64) = conn
            .query_row(
                "SELECT body, revision FROM working_copies WHERE document_id = 'c1'",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(wc, ("编辑稿".to_string(), 1));
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        conn.execute("DELETE FROM novel_documents WHERE id = 'c1'", [])
            .unwrap();
        let left: i64 = conn
            .query_row("SELECT count(*) FROM working_copies", [], |r| r.get(0))
            .unwrap();
        assert_eq!(left, 0, "文档删除后编辑稿应级联删除");
    }
}

/// v9：设定集与出处锚点。
/// - lore_entries 身份是 id（同名异人不做唯一约束、不自动合并）；别名 JSON。
/// - lore_versions 不可变版本链；作者确认在版本上留痕（AI 候选与作者确认分离）。
/// - source_anchors 绑定不可变确认版本；正稿头移动后由查询端计算 stale，不删历史。
///
/// 注意（可疑处，待核）：`LoreKind::parse` 接受 `location`，但 v9 DDL 的
/// kind CHECK 列表里没有 'location'——建 Location 条目会在 DDL 层被拒；
/// 疑似 CHECK 清单漏配，需与迁移作者确认是有意裁剪还是疏漏。
const V9_LORE_ANCHORS: &str = r#"
CREATE TABLE lore_entries (
    id            TEXT PRIMARY KEY,
    work_id       TEXT NOT NULL REFERENCES works (id) ON DELETE CASCADE,
    kind          TEXT NOT NULL CHECK (kind IN ('character','world','timeline','taboo','style')),
    name          TEXT NOT NULL,
    aliases       TEXT NOT NULL DEFAULT '[]',
    status        TEXT NOT NULL CHECK (status IN ('candidate','confirmed','rejected')),
    scope         TEXT NOT NULL DEFAULT 'whole',
    head_version  INTEGER NOT NULL CHECK (head_version > 0),
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL
);
CREATE INDEX idx_lore_entries_work ON lore_entries (work_id, kind, status);

CREATE TABLE lore_versions (
    id         TEXT PRIMARY KEY,
    entry_id   TEXT NOT NULL REFERENCES lore_entries (id) ON DELETE CASCADE,
    version    INTEGER NOT NULL,
    body       TEXT NOT NULL,
    confirmed  INTEGER NOT NULL CHECK (confirmed IN (0, 1)),
    origin     TEXT NOT NULL CHECK (origin IN ('author','ai')),
    created_at TEXT NOT NULL,
    UNIQUE (entry_id, version)
);

CREATE TABLE source_anchors (
    id                TEXT PRIMARY KEY,
    work_id           TEXT NOT NULL REFERENCES works (id) ON DELETE CASCADE,
    document_id       TEXT NOT NULL REFERENCES novel_documents (id) ON DELETE CASCADE,
    source_version_id TEXT NOT NULL,
    start_char        INTEGER NOT NULL CHECK (start_char >= 0),
    end_char          INTEGER NOT NULL CHECK (end_char > start_char),
    quote_hash        TEXT NOT NULL,
    note              TEXT,
    created_at        TEXT NOT NULL
);
CREATE INDEX idx_source_anchors_document ON source_anchors (document_id, created_at);
"#;

/// v10：派生摘要与重建队列。摘要不是原文：必须记来源版本与算法版本；
/// 依赖的确认稿变化即 dirty；重建发布前再次核对来源，拒绝过期产物。
const V10_DERIVED_SUMMARIES: &str = r#"
CREATE TABLE chapter_summaries (
    id              TEXT PRIMARY KEY,
    work_id         TEXT NOT NULL REFERENCES works (id) ON DELETE CASCADE,
    document_id     TEXT NOT NULL REFERENCES novel_documents (id) ON DELETE CASCADE,
    source_version_id TEXT NOT NULL,
    scope           TEXT NOT NULL DEFAULT 'chapter' CHECK (scope IN ('chapter','cumulative')),
    body            TEXT NOT NULL,
    algorithm       TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('ready','dirty','failed')),
    built_at        TEXT NOT NULL
);
CREATE INDEX idx_chapter_summaries_document ON chapter_summaries (document_id, scope, status);

CREATE TABLE rebuild_jobs (
    id         TEXT PRIMARY KEY,
    work_id    TEXT NOT NULL REFERENCES works (id) ON DELETE CASCADE,
    summary_id TEXT NOT NULL REFERENCES chapter_summaries (id) ON DELETE CASCADE,
    status     TEXT NOT NULL CHECK (status IN ('queued','running','done','failed')),
    attempts   INTEGER NOT NULL DEFAULT 0,
    claim_info TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_rebuild_jobs_status ON rebuild_jobs (status, created_at);
"#;

#[cfg(test)]
#[path = "client_mvp_migration_tests.rs"]
mod client_mvp_migration_tests;
