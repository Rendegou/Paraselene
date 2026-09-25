//! trigram 索引瘦身测量（T02 第二片，先测量再动手）。
//!
//! 在真实库的**备份副本**上测量（只读源库，绝不在真实库上建实验表）：
//! 1. messages 表按 role 的行数 / 文本量 / raw 量分布（脱敏，只有计数与字节数）；
//! 2. trigram FTS 变体体积对比（重建单类索引到临时库，page_count × page_size）。
//!    **注意：index_bytes 是整个临时库（含 scratch messages 全文副本），
//!     postings 体积 ≈ index_bytes − scratch messages 表体积（约 455MB）**；
//!    - all        全量消息、全文（≈ 现网 trigram postings + 副本）
//!    - no_tool    排除 role='tool'
//!    - cap4k      全文截 4096 字符
//!    - no_tool_cap4k  排除 tool + 截断（候选组合）
//!    - tool_only  仅 tool（验证「工具输出是体积大头」假设）
//!    - standalone_no_tool_cap4k  候选组合按 V4 生产形态（独立表存截断文本）实测
//!
//! 用法: cargo run --example measure_fts -- <真实库备份副本路径> <临时目录>

use rusqlite::Connection;

/// 与候选 V4 设计一致的截断长度（字符）。
const CAP_CHARS: i64 = 4096;

fn db_bytes(conn: &Connection) -> i64 {
    let page_count: i64 = conn
        .query_row("PRAGMA page_count", [], |r| r.get(0))
        .unwrap();
    let page_size: i64 = conn
        .query_row("PRAGMA page_size", [], |r| r.get(0))
        .unwrap();
    page_count * page_size
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let src = args.next().ok_or("用法: measure_fts <库副本> <临时目录>")?;
    let tmp = args.next().ok_or("用法: measure_fts <库副本> <临时目录>")?;

    let conn = Connection::open(&src)?;

    // ---- 1. messages 按 role 分布（行数 / 文本字节 / raw 字节）----
    println!("== messages 按 role 分布 ==");
    println!("{:<10} {:>8} {:>14} {:>12} {:>10}", "role", "rows", "text_bytes", "raw_bytes", "avg_text");
    let mut stmt = conn.prepare(
        "SELECT role, count(*), COALESCE(SUM(LENGTH(CAST(text AS BLOB))),0), COALESCE(SUM(LENGTH(CAST(raw AS BLOB))),0)
         FROM messages GROUP BY role ORDER BY 3 DESC",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?))
    })?;
    let mut total_rows = 0i64;
    let mut total_text = 0i64;
    let mut total_raw = 0i64;
    for r in rows {
        let (role, n, text_b, raw_b) = r?;
        total_rows += n;
        total_text += text_b;
        total_raw += raw_b;
        println!(
            "{:<10} {:>8} {:>14} {:>12} {:>10}",
            role,
            n,
            text_b,
            raw_b,
            if n > 0 { text_b / n } else { 0 }
        );
    }
    println!("{:<10} {:>8} {:>14} {:>12}", "TOTAL", total_rows, total_text, total_raw);

    // 文本量分档（看 4KB 截断能覆盖多少）
    let buckets = [
        ("<=1KB", "LENGTH(CAST(text AS BLOB)) <= 1024"),
        ("1-4KB", "LENGTH(CAST(text AS BLOB)) > 1024 AND LENGTH(CAST(text AS BLOB)) <= 4096"),
        ("4-16KB", "LENGTH(CAST(text AS BLOB)) > 4096 AND LENGTH(CAST(text AS BLOB)) <= 16384"),
        ("16-64KB", "LENGTH(CAST(text AS BLOB)) > 16384 AND LENGTH(CAST(text AS BLOB)) <= 65536"),
        (">64KB", "LENGTH(CAST(text AS BLOB)) > 65536"),
    ];
    println!("\n== 文本量分档（按 text 字节）==");
    for (label, cond) in buckets {
        let n: i64 = conn.query_row(
            &format!("SELECT count(*) FROM messages WHERE {cond}"),
            [],
            |r| r.get(0),
        )?;
        println!("{label:<8} {n:>8}");
    }

    // ---- 2. trigram 变体体积（临时库重建）----
    println!("\n== trigram 索引变体体积（external content 模型 ≈ postings）==");
    let variants: &[(&str, &str, &str)] = &[
        // (名称, WHERE 子句, 文本变换)
        ("all", "1=1", "text"),
        ("no_tool", "role != 'tool'", "text"),
        ("cap4k", "1=1", &format!("SUBSTR(text,1,{CAP_CHARS})")),
        ("no_tool_cap4k", "role != 'tool'", &format!("SUBSTR(text,1,{CAP_CHARS})")),
        ("tool_only", "role = 'tool'", "text"),
    ];
    for (name, filter, transform) in variants {
        let scratch = format!("{tmp}/measure_{name}.db");
        let _ = std::fs::remove_file(&scratch);
        conn.execute_batch(&format!("ATTACH '{scratch}' AS s"))?;
        conn.execute_batch(
            "DROP TABLE IF EXISTS s.messages;
             CREATE TABLE s.messages (rowid INTEGER PRIMARY KEY, text TEXT);",
        )?;
        conn.execute_batch(&format!(
            "INSERT INTO s.messages SELECT rowid, {transform} FROM main.messages WHERE {filter}"
        ))?;
        conn.execute_batch("DETACH s")?;
        // FTS 特殊命令（'rebuild'）不支持带 schema 前缀的列引用， detach 后单独执行
        let s = Connection::open(&scratch)?;
        s.execute_batch(
            "CREATE VIRTUAL TABLE fts USING fts5(
                text, content='messages', content_rowid='rowid', tokenize='trigram');
             INSERT INTO fts (fts) VALUES ('rebuild');",
        )?;
        let bytes = db_bytes(&s);
        let rows: i64 = s.query_row("SELECT count(*) FROM messages", [], |r| r.get(0))?;
        println!("{name:<16} rows={rows:<8} index_bytes={bytes}");
        drop(s);
        let _ = std::fs::remove_file(&scratch);
    }

    // ---- 3. 候选组合的 V4 生产形态（独立表，存截断文本）----
    println!("\n== 候选组合按 V4 生产形态（standalone 独立表）==");
    let scratch = format!("{tmp}/measure_standalone.db");
    let _ = std::fs::remove_file(&scratch);
    conn.execute_batch(&format!("ATTACH '{scratch}' AS s"))?;
    conn.execute_batch(
        "CREATE VIRTUAL TABLE s.fts USING fts5(text, session_id UNINDEXED, tokenize='trigram');
         INSERT INTO s.fts (rowid, text, session_id)
         SELECT rowid, SUBSTR(text,1,CAP), session_id FROM main.messages
         WHERE role != 'tool' AND text IS NOT NULL;"
            .replace("CAP", &CAP_CHARS.to_string())
            .as_str(),
    )?;
    conn.execute_batch("DETACH s")?;
    let s = Connection::open(&scratch)?;
    println!(
        "standalone_no_tool_cap4k index_bytes={}",
        db_bytes(&s)
    );
    drop(s);
    let _ = std::fs::remove_file(&scratch);

    // 真实库当前体积（对照）
    println!("\n== 真实库当前体积 ==");
    println!("db_bytes={}", db_bytes(&conn));
    Ok(())
}
