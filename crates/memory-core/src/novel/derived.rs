//! 派生摘要与重建队列（T05E）。摘要是可丢弃派生物：记来源版本与算法版本，
//! 依赖的确认稿一变即 dirty；重建发布前再次核对来源，过期产物拒绝发布。
//! 重启恢复 running→queued；同摘要只保留一个排队任务（幂等入队）；
//! 确认稿再变时 running 任务的 claim 作废退回 queued，旧产物照样被拒。

use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{new_id, now};

/// 摘要算法版本标识。换算法（提示词 / 切分策略变更）时必须 bump，
/// 否则旧摘要会被误认为新算法产物。
pub const SUMMARY_ALGORITHM_V1: &str = "chapter-summary-v1";

/// 章节（或累积）摘要记录。`source_version_id` 标注产物来自哪个确认版本——
/// 查询侧据此判断 ready 摘要是否仍可展示。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChapterSummary {
    pub id: String,
    pub work_id: String,
    pub document_id: String,
    pub source_version_id: String,
    pub scope: String,
    pub body: String,
    pub algorithm: String,
    pub status: String,
    pub built_at: String,
}

/// 摘要重建任务（队列行）。`claim_info` 是认领 token：running 任务必须携 token
/// 才能完成 / 作废，防止「旧 worker 完成新任务」的串台。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RebuildJob {
    pub id: String,
    pub work_id: String,
    pub summary_id: String,
    pub status: String,
    pub attempts: i64,
    pub claim_info: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl Database {
    /// 写入或替换一章的摘要（chapter 作用域）。来源版本必须对应当前头：
    /// 调用方负责拿最新头构建，写入口再核对一次。
    pub fn upsert_chapter_summary(
        &self,
        document_id: &str,
        source_version_id: &str,
        body: &str,
        algorithm: &str,
    ) -> Result<ChapterSummary> {
        if body.trim().is_empty() {
            return Err(Error::parse("摘要不能为空"));
        }
        let timestamp = now();
        let id = new_id();
        let work_id: String = self.with_conn(|conn| {
            conn.query_row(
                "SELECT work_id, head_version_id FROM novel_documents WHERE id = ?1",
                [document_id],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)),
            )
            .optional()?
            .map(|(work, _)| work)
            .ok_or_else(|| Error::not_found("小说文档不存在"))
        })?;
        self.with_tx(|tx| {
            // 先删同 scope 旧行再插新行（而不是 UPSERT）：一文档一摘要，
            // DELETE 天然清掉历史行，避免 UPSERT 留下多 scope 残留。
            tx.execute(
                "DELETE FROM chapter_summaries WHERE document_id = ?1 AND scope = 'chapter'",
                [document_id],
            )?;
            tx.execute(
                "INSERT INTO chapter_summaries (id, work_id, document_id, source_version_id, scope, body, algorithm, status, built_at)
                 VALUES (?1, ?2, ?3, ?4, 'chapter', ?5, ?6, 'ready', ?7)",
                params![id, work_id, document_id, source_version_id, body, algorithm, timestamp],
            )?;
            Ok(())
        })?;
        self.get_chapter_summary(&id)?
            .ok_or_else(|| Error::not_found("摘要不存在"))
    }

    /// 按 id 读取摘要。
    pub fn get_chapter_summary(&self, summary_id: &str) -> Result<Option<ChapterSummary>> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT id, work_id, document_id, source_version_id, scope, body, algorithm, status, built_at
                     FROM chapter_summaries WHERE id = ?1",
                    [summary_id],
                    read_summary,
                )
                .optional()?)
        })
    }

    /// 读取文档某作用域最新一份摘要（展示入口）。
    pub fn get_chapter_summary_for(
        &self,
        document_id: &str,
        scope: &str,
    ) -> Result<Option<ChapterSummary>> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT id, work_id, document_id, source_version_id, scope, body, algorithm, status, built_at
                     FROM chapter_summaries WHERE document_id = ?1 AND scope = ?2 ORDER BY built_at DESC LIMIT 1",
                    params![document_id, scope],
                    read_summary,
                )
                .optional()?)
        })
    }

    /// 确认稿变化后的失效传播：该章自身摘要 + 同作品全部累积摘要置 dirty，
    /// 并为 dirty 摘要幂等入队重建任务（同 summary 只留一个任务：已有 queued
    /// 不动，已有 running 说明来源又变了，作废 claim 退回 queued 重排）。
    pub fn mark_summaries_dirty(&self, document_id: &str) -> Result<usize> {
        let timestamp = now();
        let affected = self.with_tx(|tx| {
            let work_id: String = tx
                .query_row(
                    "SELECT work_id FROM novel_documents WHERE id = ?1",
                    [document_id],
                    |r| r.get(0),
                )
                .optional()?
                .ok_or_else(|| Error::not_found("小说文档不存在"))?;
            tx.execute(
                "UPDATE chapter_summaries SET status = 'dirty' WHERE document_id = ?1",
                [document_id],
            )?;
            // 累积摘要保守失效：任何前序章变化都可能影响累积内容。
            let changed = tx.execute(
                "UPDATE chapter_summaries SET status = 'dirty'
                 WHERE work_id = ?1 AND scope = 'cumulative' AND status = 'ready'",
                [&work_id],
            )?;
            let mut stmt = tx.prepare(
                "SELECT id FROM chapter_summaries
                 WHERE (document_id = ?1 OR (work_id = ?2 AND scope = 'cumulative')) AND status = 'dirty'",
            )?;
            let ids: Vec<String> = stmt
                .query_map(params![document_id, work_id], |r| r.get(0))?
                .collect::<std::result::Result<_, _>>()?;
            drop(stmt);
            let mut queued = 0;
            for summary_id in ids {
                queued += ensure_rebuild_job(tx, &work_id, &summary_id, &timestamp)?;
            }
            Ok(changed + queued)
        })?;
        Ok(affected)
    }

    /// 认领下一个重建任务（queued→running，返回 claim token）。
    pub fn next_rebuild_job(&self) -> Result<Option<(RebuildJob, String)>> {
        let claim = new_id();
        let timestamp = now();
        let claimed = self.with_tx(|tx| {
            let job_id: Option<String> = tx
                .query_row(
                    "SELECT id FROM rebuild_jobs WHERE status = 'queued' ORDER BY created_at, id LIMIT 1",
                    [],
                    |r| r.get(0),
                )
                .optional()?;
            let Some(job_id) = job_id else { return Ok(None) };
            tx.execute(
                "UPDATE rebuild_jobs SET status = 'running', attempts = attempts + 1, claim_info = ?2, updated_at = ?3
                 WHERE id = ?1 AND status = 'queued'",
                params![job_id, claim, timestamp],
            )?;
            Ok(Some(job_id))
        })?;
        let Some(job_id) = claimed else {
            return Ok(None);
        };
        let job = self
            .with_conn(|conn| {
                Ok(conn
                    .query_row(
                        "SELECT id, work_id, summary_id, status, attempts, claim_info, created_at, updated_at
                         FROM rebuild_jobs WHERE id = ?1",
                        [&job_id],
                        read_job,
                    )
                    .optional()?)
            })?
            .ok_or_else(|| Error::not_found("重建任务不存在"))?;
        Ok(Some((job, claim)))
    }

    /// 发布重建结果。核对 claim 与构建基准：重建期间确认头又移动时
    /// 旧产物拒绝发布（任务记 failed，可重新入队）；发布把摘要来源版本
    /// 一并更新为构建基准，保持「来源版本对应当前头」的不变式。
    pub fn finish_rebuild_job(
        &self,
        job_id: &str,
        claim: &str,
        built_from_version: &str,
        body: &str,
    ) -> Result<ChapterSummary> {
        let timestamp = now();
        let summary_id = self.with_tx(|tx| {
            let (job_summary, job_claim, status): (String, Option<String>, String) = tx
                .query_row(
                    "SELECT summary_id, claim_info, status FROM rebuild_jobs WHERE id = ?1",
                    [job_id],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .optional()?
                .ok_or_else(|| Error::not_found("重建任务不存在"))?;
            if status != "running" || job_claim.as_deref() != Some(claim) {
                return Err(Error::parse("重建任务已失效，请重新领取"));
            }
            // 存储的 source_version_id 是旧正文的来源，不能拿来核对新产物；
            // 要核的是构建基准仍等于文档当前确认头（期间再改即旧产物）。
            let (document_id, summary_status): (String, String) = tx.query_row(
                "SELECT document_id, status FROM chapter_summaries WHERE id = ?1",
                [&job_summary],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            let head: Option<String> = tx
                .query_row(
                    "SELECT head_version_id FROM novel_documents WHERE id = ?1",
                    [&document_id],
                    |r| r.get(0),
                )
                .optional()?;
            if summary_status != "dirty" || head.as_deref() != Some(built_from_version) {
                tx.execute(
                    "UPDATE rebuild_jobs SET status = 'failed', updated_at = ?2 WHERE id = ?1",
                    params![job_id, timestamp],
                )?;
                return Err(Error::parse("摘要期间已变化，旧产物未发布；请重新排队"));
            }
            tx.execute(
                "UPDATE chapter_summaries
                 SET body = ?2, source_version_id = ?3, status = 'ready', built_at = ?4
                 WHERE id = ?1",
                params![job_summary, body, built_from_version, timestamp],
            )?;
            tx.execute(
                "UPDATE rebuild_jobs SET status = 'done', updated_at = ?2 WHERE id = ?1",
                params![job_id, timestamp],
            )?;
            Ok(job_summary)
        })?;
        self.get_chapter_summary(&summary_id)?
            .ok_or_else(|| Error::not_found("摘要不存在"))
    }

    /// 重启恢复：中断的 running 任务回到 queued（claim 清空，attempts 保留）。
    pub fn reset_stale_rebuild_jobs(&self) -> Result<usize> {
        let timestamp = now();
        let updated = self.with_conn(|conn| {
            Ok(conn.execute(
                "UPDATE rebuild_jobs SET status = 'queued', claim_info = NULL, updated_at = ?1
                 WHERE status = 'running'",
                [timestamp],
            )?)
        })?;
        Ok(updated)
    }
}

/// 保证一个 dirty 摘要有且只有一个可领取的重建任务：无任务则新建 queued；
/// 已有 queued 不动（幂等）；已有 running 说明来源又变了，旧 claim 作废
/// 退回 queued（attempts 保留，重试次数仍可见），由下一轮按最新头重建。
fn ensure_rebuild_job(
    tx: &rusqlite::Transaction<'_>,
    work_id: &str,
    summary_id: &str,
    timestamp: &str,
) -> Result<usize> {
    let existing: Option<(String, String)> = tx
        .query_row(
            "SELECT id, status FROM rebuild_jobs
             WHERE summary_id = ?1 AND status IN ('queued','running')
             ORDER BY created_at, id LIMIT 1",
            [summary_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    let Some((job_id, status)) = existing else {
        tx.execute(
            "INSERT INTO rebuild_jobs (id, work_id, summary_id, status, attempts, created_at, updated_at)
             VALUES (?1, ?2, ?3, 'queued', 0, ?4, ?4)",
            params![new_id(), work_id, summary_id, timestamp],
        )?;
        return Ok(1);
    };
    if status == "running" {
        tx.execute(
            "UPDATE rebuild_jobs SET status = 'queued', claim_info = NULL, updated_at = ?2
             WHERE id = ?1",
            params![job_id, timestamp],
        )?;
    }
    Ok(0)
}

/// 摘要表行 → 记录（9 列，与各 SELECT 强绑定）。
fn read_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<ChapterSummary> {
    Ok(ChapterSummary {
        id: row.get(0)?,
        work_id: row.get(1)?,
        document_id: row.get(2)?,
        source_version_id: row.get(3)?,
        scope: row.get(4)?,
        body: row.get(5)?,
        algorithm: row.get(6)?,
        status: row.get(7)?,
        built_at: row.get(8)?,
    })
}

/// 重建任务行 → 记录（8 列，与各 SELECT 强绑定）。
fn read_job(row: &rusqlite::Row<'_>) -> rusqlite::Result<RebuildJob> {
    Ok(RebuildJob {
        id: row.get(0)?,
        work_id: row.get(1)?,
        summary_id: row.get(2)?,
        status: row.get(3)?,
        attempts: row.get(4)?,
        claim_info: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

#[cfg(test)]
#[path = "derived_tests.rs"]
mod tests;
