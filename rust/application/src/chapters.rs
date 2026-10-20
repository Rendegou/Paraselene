//! Chapter directory, archive, version and draft lifecycle operations.
//! Reorder accepts only the visible non-archived chapter ids; the complete
//! work document set is reassembled here so lore documents and archived
//! chapters keep their positions, mirroring the original client merge.
//!
//! 重排只接受可见章节 id 且必须与当前目录集合完全一致；版本、草稿与回滚操作依赖核心事务的
//! revision/head/base CAS 拒绝过期写入。稳定错误码在本模块集中映射，核心的中文解析消息不直接外发。
use crate::{core_error, err, verify, AppError, ChapterInfo, Session, VersionInfo};
use paraselene_memory_core::{Database, NovelDocumentSummary};
use std::collections::BTreeSet;

/// Map a directory summary onto the bridge-facing chapter DTO.
pub(crate) fn chapter_info(d: NovelDocumentSummary) -> ChapterInfo {
    ChapterInfo {
        id: d.id,
        work_id: d.work_id,
        title: d.title,
        head_version_id: d.head_version_id,
        order_index: d.order_index,
        archived: d.archived_at.is_some(),
    }
}

/// Locate a chapter in the active or archived directory after a mutation.
pub(crate) fn find_chapter(
    db: &Database,
    work_id: &str,
    id: &str,
) -> Result<ChapterInfo, AppError> {
    let active = db.novel_document_summaries(work_id).map_err(core_error)?;
    let archived = db
        .novel_archived_document_summaries(work_id)
        .map_err(core_error)?;
    active
        .into_iter()
        .chain(archived)
        .find(|d| d.id == id && d.kind == "chapter")
        .map(chapter_info)
        .ok_or_else(|| err("not_found"))
}

/// The work's complete document order: active plus archived, sorted by the
/// stored index with creation order as the stable tiebreak.
pub(crate) fn full_directory_ids(
    db: &Database,
    work_id: &str,
) -> Result<Vec<NovelDocumentSummary>, AppError> {
    let mut full = db.novel_document_summaries(work_id).map_err(core_error)?;
    full.extend(
        db.novel_archived_document_summaries(work_id)
            .map_err(core_error)?,
    );
    full.sort_by_key(|d| (d.order_index, d.created_at.clone(), d.id.clone()));
    Ok(full)
}

/// Stable codes for the core's fixed Chinese parse messages; the strings are
/// a contract with the in-workspace core crate, not user-facing copy.
pub(crate) fn chapter_error(e: paraselene_memory_core::Error) -> AppError {
    match e {
        paraselene_memory_core::Error::Parse(message) => {
            // 核心以固定中文消息表达冲突，本映射把消息转成稳定 ASCII 码；消息文本是跨 crate 契约，不能本地化。
            let code = if message.contains("revision 过期") || message.contains("revision 已变化")
            {
                "revision_conflict"
            } else if message.contains("正稿已变化") {
                "head_conflict"
            } else if message.contains("基于旧正稿") {
                "base_conflict"
            } else if message.contains("人物设定或作品内容已变化") {
                "context_conflict"
            } else {
                "invalid_input"
            };
            err(code)
        }
        other => core_error(other),
    }
}

impl Session {
    /// Rename a chapter; titles live outside the version tree.
    ///
    /// 标题离开版本树；空标题或超长由核心返回 invalid_input。
    pub fn rename_chapter(
        &self,
        work_id: String,
        document_id: String,
        title: String,
    ) -> Result<ChapterInfo, AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            db.rename_novel_document(&document_id, &title)
                .map_err(chapter_error)?;
            find_chapter(db, &work_id, &document_id)
        })
    }

    /// Reorder the non-archived chapters; archived chapters and non-chapter
    /// documents keep their absolute positions in the submitted full set.
    ///
    /// ordered_ids 必须恰好是未归档章节集合，否则返回 invalid_input；归档章节与非章文档位置不变。
    pub fn reorder_chapters(
        &self,
        work_id: String,
        ordered_ids: Vec<String>,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            let full = full_directory_ids(db, &work_id)?;
            let expected: BTreeSet<&str> = full
                .iter()
                .filter(|d| d.kind == "chapter" && d.archived_at.is_none())
                .map(|d| d.id.as_str())
                .collect();
            let given: BTreeSet<&str> = ordered_ids.iter().map(String::as_str).collect();
            if given.len() != ordered_ids.len() || given != expected {
                return Err(err("invalid_input"));
            }
            let mut next = ordered_ids.into_iter();
            let merged: Vec<String> = full
                .iter()
                .map(|d| {
                    if d.kind == "chapter" && d.archived_at.is_none() {
                        next.next().unwrap_or_else(|| d.id.clone())
                    } else {
                        d.id.clone()
                    }
                })
                .collect();
            db.reorder_novel_documents(&work_id, &merged)
                .map_err(chapter_error)
        })
    }

    /// Archive or restore a chapter idempotently; versions and drafts survive.
    ///
    /// 幂等；版本、草稿与讨论线程均保留。
    pub fn set_chapter_archived(
        &self,
        work_id: String,
        document_id: String,
        archived: bool,
    ) -> Result<ChapterInfo, AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            db.set_novel_document_archived(&work_id, &document_id, archived)
                .map_err(chapter_error)?;
            find_chapter(db, &work_id, &document_id)
        })
    }

    /// List archived chapters for the work.
    ///
    /// 仅返回 kind=chapter 的归档文档。
    pub fn list_archived_chapters(&self, work_id: String) -> Result<Vec<ChapterInfo>, AppError> {
        self.with_db(|db| {
            Ok(db
                .novel_archived_document_summaries(&work_id)
                .map_err(core_error)?
                .into_iter()
                .filter(|d| d.kind == "chapter")
                .map(chapter_info)
                .collect())
        })
    }

    /// Roll back the head to an existing version of the same document. The
    /// working copy is discarded exactly as checked by the core transaction.
    ///
    /// 只回滚到同一文档已有版本；head/revision 过期分别返回 head_conflict/revision_conflict，
    /// 工作副本按核心事务语义处理。
    pub fn rollback_chapter(
        &self,
        work_id: String,
        document_id: String,
        version_id: String,
        expected_head: Option<String>,
        expected_revision: Option<i64>,
    ) -> Result<ChapterInfo, AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            db.rollback_novel_working_copy(
                &document_id,
                &version_id,
                expected_head.as_deref(),
                expected_revision,
            )
            .map_err(chapter_error)?;
            find_chapter(db, &work_id, &document_id)
        })
    }

    /// List confirmed versions newest first, including exact bodies.
    ///
    /// 新到旧排列并包含精确正文；作品/文档身份不匹配返回 identity_mismatch。
    pub fn list_versions(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<Vec<VersionInfo>, AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            Ok(db
                .list_novel_versions(&document_id)
                .map_err(core_error)?
                .into_iter()
                .map(|v| VersionInfo {
                    id: v.id,
                    document_id: v.document_id,
                    parent_version_id: v.parent_version_id,
                    body: v.body,
                    origin: v.origin,
                    created_at: v.created_at,
                    is_head: v.is_head,
                })
                .collect())
        })
    }

    /// Explicitly discard the working copy; the CAS revision must match.
    ///
    /// 只丢弃工作副本，不触碰已确认版本；revision 不匹配返回 revision_conflict。
    pub fn discard_draft(
        &self,
        work_id: String,
        document_id: String,
        expected_revision: Option<i64>,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            db.delete_working_copy(&document_id, expected_revision)
                .map_err(chapter_error)
        })
    }
}
