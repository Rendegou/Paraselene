//! 中文检索题集召回对比评测（T01 第三片，G05 索引方案选型）。
//!
//! 变体 A（基线）：现有 unicode61 FTS + `build_match_query` 查询构造（整串/前缀命中）。
//! 变体 B（trigram）：同一 messages 表上新建 `message_fts_trigram`
//! （external content 同款，`tokenize='trigram'`），查询侧把问题切成 3–6 字滑窗
//! n-gram 组 OR 查询，bm25 排序。常见 grams 的高文档频率由 bm25 的 IDF 自动降权
//! （等效「去停用感太强片段」，无需维护停用词表）。
//!
//! 隐私红线（AGENTS.md §4）：输出只含题号 / 文件名 / 布尔值 / 计数；
//! snippet 仅用于内部布尔判断（是否包含 anchor），绝不打印内容。
//!
//! 用法：
//!   cargo run --example retrieval_eval -- <testset.json> <库目录>
//! 库目录即 import-smoke 工作目录（内含 index.db）。

use std::collections::HashMap;
use std::io::Read;
use std::path::PathBuf;

use paraselene_memory_core::imports::parse_input;
use paraselene_memory_core::storage::search::SearchQuery;
use paraselene_memory_core::Database;

#[derive(serde::Deserialize)]
struct Testset {
    #[allow(dead_code)]
    version: u32,
    source_corpus: String,
    questions: Vec<Question>,
}

#[derive(serde::Deserialize)]
struct Question {
    id: String,
    tier: String,
    question: String,
    expected_files: Vec<String>,
    must_hit_anchor: String,
}

/// 单题单变体结果（只有布尔与文件名，无内容）。
#[derive(Default, Clone)]
struct QResult {
    recall5: bool,
    top1: bool,
    anchor: bool,
    /// 诊断补充：top-1 命中时，该消息**全文**是否含 anchor（区分「片段窗口太窄」与「消息不对」）
    anchor_msg: bool,
    /// 诊断补充：top-1 命中时，anchor 是否出现在该会话**任意**消息（anchor 是会话级标注时的公平口径）
    anchor_sess: bool,
    hit_file: Option<String>,
}

/// 判定一题：top-5 是否含期望会话、top-1 是否命中、top-1 snippet 是否含 anchor。
fn judge(hits: &[(String, String, String)], expected: &[(String, String)], anchor: &str) -> QResult {
    let mut r = QResult::default();
    for (sid, _, _) in hits {
        for (file, exp_sid) in expected {
            if sid == exp_sid {
                r.recall5 = true;
                if r.hit_file.is_none() {
                    r.hit_file = Some(file.clone());
                }
            }
        }
    }
    if let Some((sid, _, snippet)) = hits.first() {
        r.top1 = expected.iter().any(|(_, exp)| exp == sid);
        r.anchor = snippet.contains(anchor);
    }
    r
}

/// top-1 命中时取该消息/会话全文，计算 anchor_msg（消息级）与 anchor_sess（会话级），
/// 用于区分「snippet 窗口太窄」「anchor 在同会话其他消息」「消息不对」三种情况（布尔，不输出内容）。
fn fill_anchor_msg(db: &Database, hits: &[(String, String, String)], r: &mut QResult, anchor: &str) {
    if !r.top1 {
        return;
    }
    let Some((sid, msg_id, _)) = hits.first() else { return };
    let msg_hit: Option<bool> = db
        .with_conn(|conn| {
            Ok(conn.query_row(
                "SELECT count(*) > 0 FROM messages WHERE id = ?1 AND instr(text, ?2) > 0",
                rusqlite::params![msg_id, anchor],
                |row| row.get(0),
            )?)
        })
        .ok();
    r.anchor_msg = msg_hit.unwrap_or(false);
    let sess_hit: Option<bool> = db
        .with_conn(|conn| {
            Ok(conn.query_row(
                "SELECT count(*) > 0 FROM messages WHERE session_id = ?1 AND instr(text, ?2) > 0",
                rusqlite::params![sid, anchor],
                |row| row.get(0),
            )?)
        })
        .ok();
    r.anchor_sess = sess_hit.unwrap_or(false);
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let testset_path = PathBuf::from(args.next().ok_or("用法: retrieval_eval <testset.json> <库目录>")?);
    let lib_dir = PathBuf::from(args.next().ok_or("用法: retrieval_eval <testset.json> <库目录>")?);

    let testset: Testset = serde_json::from_str(&std::fs::read_to_string(&testset_path)?)?;
    let db = Database::open(&lib_dir.join("index.db"))?;

    // ---- 文件名 → 会话 id 映射 ----
    // 托管副本与 sessions 表都不存原始文件名，必须重放 zip 解析来重建映射。
    // 注意：必须与导入时走完全相同的 parse_input 路径（含 zip 条目 mtime 兜底日期），
    // 否则内容哈希派生的 external_id 会不同，映射全部失配。
    let file_map = build_file_map(&testset.source_corpus)?;
    let stats = db.stats()?;
    println!("== 题集: {} 题（{}）==", testset.questions.len(), testset_path.display());
    println!(
        "== 库: {}（会话 {} / 消息 {}）==",
        lib_dir.display(),
        stats.sessions,
        stats.messages
    );

    // ---- 变体 B 准备：trigram 表由迁移负责建（V2 引入、V4 瘦身为独立表），
    // 这里只做存在性断言，不再 ad hoc 建表（避免与正式 schema 漂移）。----
    assert!(
        db.with_conn(|conn| {
            Ok(conn.query_row(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='message_fts_trigram'",
                [],
                |r| r.get::<_, i64>(0),
            )? > 0)
        })?,
        "message_fts_trigram 应由迁移创建"
    );

    // ---- 逐题评测 ----
    let mut results: Vec<(Question, QResult, QResult)> = Vec::new();
    let mut map_misses: Vec<String> = Vec::new();
    for q in &testset.questions {
        let expected: Vec<(String, String)> = q
            .expected_files
            .iter()
            .map(|f| {
                let sid = file_map.get(f).cloned();
                if sid.is_none() && !map_misses.contains(f) {
                    map_misses.push(f.clone());
                }
                (f.clone(), sid.unwrap_or_default())
            })
            .collect();

        // 变体 A：现有 search API（unicode61 + build_match_query）
        let hits_a: Vec<(String, String, String)> = {
            let resp_a = db.search(&SearchQuery {
                text: q.question.clone(),
                limit: 5,
                offset: 0,
                ..Default::default()
            })?;
            resp_a.hits.iter().map(|h| (h.session_id.clone(), h.message_id.clone(), h.snippet.clone())).collect()
        };
        let mut ra = judge(&hits_a, &expected, &q.must_hit_anchor);
        fill_anchor_msg(&db, &hits_a, &mut ra, &q.must_hit_anchor);

        // 变体 B：trigram + n-gram OR
        let hits_b = search_trigram(&db, &q.question, 5)?;
        let mut rb = judge(&hits_b, &expected, &q.must_hit_anchor);
        fill_anchor_msg(&db, &hits_b, &mut rb, &q.must_hit_anchor);

        results.push((q.clone_q(), ra, rb));
    }

    // ---- 汇总表 ----
    print_summary("A（unicode61 FTS 基线）", &results, |r| &r.1);
    print_summary("B（trigram + n-gram OR）", &results, |r| &r.2);

    // ---- 逐题明细（题号 + 布尔 + 命中文件名；无正文）----
    println!("\n逐题明细:");
    for (q, ra, rb) in &results {
        let mark = |b: bool| if b { "✓" } else { "✗" };
        let hit = ra.hit_file.as_deref().or(rb.hit_file.as_deref()).unwrap_or("-");
        println!(
            "  {} {:6}  A[召{} 首{} 锚{}]  B[召{} 首{} 锚{} 锚2{} 锚3{}]  命中: {}",
            q.id,
            q.tier,
            mark(ra.recall5),
            mark(ra.top1),
            mark(ra.anchor),
            mark(rb.recall5),
            mark(rb.top1),
            mark(rb.anchor),
            mark(rb.anchor_msg),
            mark(rb.anchor_sess),
            hit
        );
    }

    if !map_misses.is_empty() {
        println!("\n警告: 以下 expected_files 在语料 zip 中没有对应会话（题集标注或语料问题）:");
        for f in &map_misses {
            println!("  - {f}");
        }
    }
    Ok(())
}

impl Question {
    fn clone_q(&self) -> Question {
        Question {
            id: self.id.clone(),
            tier: self.tier.clone(),
            question: self.question.clone(),
            expected_files: self.expected_files.clone(),
            must_hit_anchor: self.must_hit_anchor.clone(),
        }
    }
}

fn print_summary<'a>(
    name: &str,
    results: &'a [(Question, QResult, QResult)],
    pick: impl Fn(&'a (Question, QResult, QResult)) -> &'a QResult,
) {
    println!("\n变体 {name}");
    for tier in ["all", "easy", "medium", "hard"] {
        let selected: Vec<&QResult> = results
            .iter()
            .filter(|(q, _, _)| tier == "all" || q.tier == tier)
            .map(|r| pick(r))
            .collect();
        let n = selected.len();
        let recall: usize = selected.iter().filter(|r| r.recall5).count();
        let top1: usize = selected.iter().filter(|r| r.top1).count();
        let anchor: usize = selected.iter().filter(|r| r.anchor).count();
        let anchor_msg: usize = selected.iter().filter(|r| r.anchor_msg).count();
        let anchor_sess: usize = selected.iter().filter(|r| r.anchor_sess).count();
        println!(
            "  {:6}: recall@5 {}/{} ({:.0}%)  top-1 {}/{} ({:.0}%)  anchor(片段) {}/{} ({:.0}%)  anchor(全文) {}/{} ({:.0}%)  anchor(会话) {}/{} ({:.0}%)",
            tier, recall, n, pct(recall, n), top1, n, pct(top1, n), anchor, n, pct(anchor, n), anchor_msg, n, pct(anchor_msg, n), anchor_sess, n, pct(anchor_sess, n)
        );
    }
}

fn pct(part: usize, total: usize) -> f64 {
    if total == 0 { 0.0 } else { part as f64 * 100.0 / total as f64 }
}

/// 重放 zip 解析，重建「原始 .md 文件名 → 会话 id」映射。
fn build_file_map(zip_path: &str) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
    let file = std::fs::File::open(zip_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut map = HashMap::new();
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        if entry.is_dir() || !entry.name().ends_with(".md") {
            continue;
        }
        let name = entry.name().to_string();
        let mut text = String::new();
        entry.read_to_string(&mut text)?;
        // 与导入 example 完全一致的 mtime 兜底（影响内容哈希派生的 external_id）
        let fallback = entry.last_modified().and_then(|dt| {
            chrono::NaiveDate::from_ymd_opt(dt.year() as i32, dt.month() as u32, dt.day() as u32)
                .and_then(|d| d.and_hms_opt(dt.hour() as u32, dt.minute() as u32, dt.second() as u32))
                .map(|n| n.and_utc().to_rfc3339())
        });
        if let Ok((package, _, _)) = parse_input("chatgpt", &text, fallback.as_deref()) {
            for s in package.sessions {
                if let Some(ext) = s.external_id {
                    map.insert(name.clone(), format!("chatgpt:{ext}"));
                }
            }
        }
    }
    Ok(map)
}

/// 把问题切成 3–6 字滑窗 n-gram，组成 FTS5 OR 短语查询。
fn trigram_query(question: &str) -> String {
    let chars: Vec<char> = question
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

/// trigram 检索：返回 (session_id, message_id, snippet) 列表（bm25 排序，snippet 仅内部用于 anchor 布尔判断）。
fn search_trigram(db: &Database, question: &str, limit: i64) -> paraselene_memory_core::Result<Vec<(String, String, String)>> {
    let q = trigram_query(question);
    if q.is_empty() {
        return Ok(Vec::new());
    }
    db.with_conn(|conn| {
        let mut stmt = conn.prepare_cached(
            "SELECT m.session_id, m.id, snippet(message_fts_trigram, 0, '<mark>', '</mark>', '…', 18)
             FROM message_fts_trigram
             JOIN messages m ON m.rowid = message_fts_trigram.rowid
             WHERE message_fts_trigram MATCH ?1
             ORDER BY rank
             LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(rusqlite::params![q, limit], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, Option<String>>(2)?.unwrap_or_default(),
                ))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(rows)
    })
}
