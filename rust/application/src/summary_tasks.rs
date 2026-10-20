//! A manually approved chapter rebuild worker using the core's claim/head CAS.
//!
//! 摘要任务通过核心 claim token 与 head CAS 取得唯一执行权；开始事务同时把摘要标记 dirty、
//! 使旧队列任务失败并插入 running 记录，失败或取消按 token 回收。
use crate::{core_error, err, AppError};
use paraselene_llm_core as llm;
use paraselene_memory_core::{Database, Error};
use paraselene_novel_core::GenerationPlan;
use rusqlite::{params, OptionalExtension};

/// 一次重建任务的 claim：job id、一次性 token 与绑定的 head 版本。
pub(crate) struct Claim {
    pub job: String,
    pub token: String,
    pub head: String,
}
/// 只针对已确认章节组装摘要计划；缺 head 或正文返回 confirmed_chapter_required。
pub(crate) fn prepare(
    db: &Database,
    work: &str,
    chapter: &str,
) -> Result<GenerationPlan, AppError> {
    let doc = crate::verify(db, work, chapter)?;
    let head = doc
        .head_version_id
        .ok_or_else(|| err("confirmed_chapter_required"))?;
    let body = doc
        .head_body
        .ok_or_else(|| err("confirmed_chapter_required"))?;
    let prepared = llm::assemble_chat(&llm::AllowAll, llm::ChatRequest {
        space: llm::Space::Novel,
        messages: vec![llm::Message::system("Summarize only the following confirmed chapter in at most 2000 characters. Preserve unresolved questions as unresolved. Invent no facts, dialogue or future events. Output summary text only; this is discardable derived material, never canonical manuscript."),
            llm::Message::user(&body)],
        model: Some("deepseek-flash".into()), max_tokens: Some(3000), temperature: Some(0.2), tools: None,
    }, "deepseek-flash").map_err(|_| err("preview_failed"))?;
    Ok(GenerationPlan {
        document_id: chapter.into(),
        work_id: work.into(),
        base_version_id: Some(head),
        context_versions: Vec::new(),
        prepared,
        manifest: None,
    })
}

/// Claim only this chapter. Queue metadata and dirty marker commit together.
///
/// 在事务内校验 head、标记 dirty、使旧 queued/running 任务失败并插入带 token 的 running 记录。
pub(crate) fn start(db: &Database, plan: &GenerationPlan) -> Result<Claim, AppError> {
    let head = plan
        .base_version_id
        .as_ref()
        .ok_or_else(|| err("confirmed_chapter_required"))?;
    let token = uuid::Uuid::new_v4().to_string();
    let job = uuid::Uuid::new_v4().to_string();
    let timestamp = chrono::Utc::now().to_rfc3339();
    db.with_tx(|tx| {
        let current: Option<String> = tx.query_row("SELECT head_version_id FROM novel_documents WHERE id=?1 AND work_id=?2 AND archived_at IS NULL",
            params![plan.document_id, plan.work_id], |r| r.get(0))?;
        if current.as_ref() != Some(head) { return Err(Error::parse("summary_source_changed")); }
        let existing: Option<String> = tx.query_row("SELECT id FROM chapter_summaries WHERE document_id=?1 AND scope='chapter' ORDER BY built_at DESC LIMIT 1",
            [&plan.document_id], |r| r.get(0)).optional()?;
        // 复用既有摘要行，避免同一章出现多条摘要；job 仍新建以保留尝试历史。
        let summary = existing.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        tx.execute("INSERT INTO chapter_summaries(id,work_id,document_id,source_version_id,scope,body,algorithm,status,built_at) VALUES(?1,?2,?3,?4,'chapter','','flutter-reviewed-chapter-summary-v1','dirty',?5)
            ON CONFLICT(id) DO UPDATE SET status='dirty',algorithm='flutter-reviewed-chapter-summary-v1'",
            params![summary, plan.work_id, plan.document_id, head, timestamp])?;
        tx.execute("UPDATE rebuild_jobs SET status='failed',claim_info=NULL,updated_at=?2 WHERE summary_id=?1 AND status IN ('queued','running')", params![summary,timestamp])?;
        tx.execute("INSERT INTO rebuild_jobs(id,work_id,summary_id,status,attempts,claim_info,created_at,updated_at) VALUES(?1,?2,?3,'running',1,?4,?5,?5)",
            params![job,plan.work_id,summary,token,timestamp])?;
        Ok(())
    }).map_err(core_error)?;
    Ok(Claim {
        job,
        token,
        head: head.clone(),
    })
}
/// 只更新 job、token 与 running 状态全部匹配的行；不匹配时不改动。
pub(crate) fn fail(db: &Database, claim: &Claim) -> Result<(), AppError> {
    db.with_conn(|conn| {
        conn.execute("UPDATE rebuild_jobs SET status='failed',claim_info=NULL,updated_at=?3 WHERE id=?1 AND claim_info=?2 AND status='running'",
            params![claim.job,claim.token,chrono::Utc::now().to_rfc3339()])?;
        Ok(())
    }).map_err(core_error)
}

/// A bounded chapter-scoped queue view; worker claim tokens never leave Rust.
///
/// 返回该章最近 20 条重建任务视图；claim token 不外发。
pub(crate) fn history(db: &Database, chapter: &str) -> Result<Vec<serde_json::Value>, AppError> {
    db.with_conn(|conn| {
        let mut statement = conn.prepare("SELECT j.id,j.status,j.attempts,j.updated_at FROM rebuild_jobs j JOIN chapter_summaries s ON s.id=j.summary_id WHERE s.document_id=?1 ORDER BY j.created_at DESC,j.id DESC LIMIT 20")?;
        let rows = statement.query_map([chapter], |row| Ok(serde_json::json!({"id":row.get::<_,String>(0)?,"status":row.get::<_,String>(1)?,"attempts":row.get::<_,i64>(2)?,"updatedAt":row.get::<_,String>(3)?})))?;
        rows.collect::<Result<Vec<_>,_>>().map_err(Into::into)
    }).map_err(core_error)
}
