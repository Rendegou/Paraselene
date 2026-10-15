//! 派生摘要 / 重建队列的行为测试（由 derived.rs 以 #[path] 引入）。
use super::super::{DraftOrigin, NovelKind};
use super::*;

/// 造：作品 + 已确认章节 + 一章摘要（ready）。返回 (db, work_id, chapter_id)。
fn chapter_with_summary() -> (Database, String, String) {
    let db = Database::open_in_memory().unwrap();
    let work = db.create_work("作品").unwrap();
    let chapter = db
        .create_novel_document(&work.id, NovelKind::Chapter, "第三章")
        .unwrap();
    let draft = db
        .create_novel_draft(&chapter.id, "第三版正文", DraftOrigin::User)
        .unwrap();
    let head = db
        .accept_novel_draft(&draft.id)
        .unwrap()
        .head_version_id
        .unwrap();
    db.upsert_chapter_summary(&chapter.id, &head, "第三章摘要", SUMMARY_ALGORITHM_V1)
        .unwrap();
    (db, work.id, chapter.id)
}

/// 便捷：给章节采纳一个内容为 body 的新确认版本，返回新 head 版本 id。
fn accept_new_version(db: &Database, chapter_id: &str, body: &str) -> String {
    let draft = db
        .create_novel_draft(chapter_id, body, DraftOrigin::User)
        .unwrap();
    db.accept_novel_draft(&draft.id)
        .unwrap()
        .head_version_id
        .unwrap()
}

#[test]
fn 修改章节后摘要dirty并入队重建() {
    let (db, _work, chapter_id) = chapter_with_summary();
    accept_new_version(&db, &chapter_id, "第三版改");
    let summary = db
        .get_chapter_summary_for(&chapter_id, "chapter")
        .unwrap()
        .unwrap();
    assert_eq!(summary.status, "dirty");
    let (job, _claim) = db.next_rebuild_job().unwrap().unwrap();
    assert_eq!(job.summary_id, summary.id);
    // 幂等：再标记不重复入队。
    db.mark_summaries_dirty(&chapter_id).unwrap();
    let (job2, _) = db.next_rebuild_job().unwrap().unwrap();
    assert_eq!(job2.id, job.id, "同摘要只保留一个任务");
}

#[test]
fn 重建发布前核对来源_期间再修改拒绝旧产物() {
    let (db, _work, chapter_id) = chapter_with_summary();
    accept_new_version(&db, &chapter_id, "第三版改");
    let (job, claim) = db.next_rebuild_job().unwrap().unwrap();
    // 构建期间正文又变了。
    accept_new_version(&db, &chapter_id, "第三版再改");
    let stale = db.finish_rebuild_job(&job.id, &claim, "旧版本", "旧摘要产物");
    assert!(stale.is_err(), "旧产物不得发布");
    let summary = db
        .get_chapter_summary_for(&chapter_id, "chapter")
        .unwrap()
        .unwrap();
    assert_eq!(summary.body, "第三章摘要", "正文保持旧可靠版本");
    assert_eq!(summary.status, "dirty");
}

#[test]
fn 重建成功发布ready且claim过期后拒绝重复完成() {
    let (db, _work, chapter_id) = chapter_with_summary();
    let new_head = accept_new_version(&db, &chapter_id, "第三版改");
    let (job, claim) = db.next_rebuild_job().unwrap().unwrap();
    let summary = db
        .finish_rebuild_job(&job.id, &claim, &new_head, "新摘要")
        .unwrap();
    assert_eq!(summary.status, "ready");
    assert_eq!(summary.body, "新摘要");
    assert!(db
        .finish_rebuild_job(&job.id, &claim, &new_head, "再写一次")
        .is_err());
}

#[test]
fn 重启恢复running回queued() {
    let (db, _work, chapter_id) = chapter_with_summary();
    accept_new_version(&db, &chapter_id, "第三版改");
    let (_job, _claim) = db.next_rebuild_job().unwrap().unwrap();
    let recovered = db.reset_stale_rebuild_jobs().unwrap();
    assert_eq!(recovered, 1);
    let (job, _claim) = db.next_rebuild_job().unwrap().unwrap();
    assert_eq!(job.attempts, 2, "attempts 保留可见重试次数");
}

#[test]
fn 累积摘要在任何前序章变化时保守失效() {
    let db = Database::open_in_memory().unwrap();
    let work = db.create_work("作品").unwrap();
    let earlier = db
        .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
        .unwrap();
    let later = db
        .create_novel_document(&work.id, NovelKind::Chapter, "第五章")
        .unwrap();
    let draft = db
        .create_novel_draft(&later.id, "内容", DraftOrigin::User)
        .unwrap();
    let head = db
        .accept_novel_draft(&draft.id)
        .unwrap()
        .head_version_id
        .unwrap();
    let _cumulative = db
        .upsert_chapter_summary(&later.id, &head, "卷一累积摘要", SUMMARY_ALGORITHM_V1)
        .unwrap();
    // 手工把该摘要改为 cumulative 作用域以模拟卷级派生物。
    db.with_conn(|conn| {
        conn.execute(
            "UPDATE chapter_summaries SET scope = 'cumulative' WHERE document_id = ?1",
            [&later.id],
        )?;
        Ok::<_, crate::error::Error>(())
    })
    .unwrap();
    // 修改前序章：累积摘要必须 dirty。
    let draft = db
        .create_novel_draft(&earlier.id, "一改", DraftOrigin::User)
        .unwrap();
    db.accept_novel_draft(&draft.id).unwrap();
    db.mark_summaries_dirty(&earlier.id).unwrap();
    let summary = db
        .get_chapter_summary_for(&later.id, "cumulative")
        .unwrap()
        .unwrap();
    assert_eq!(summary.status, "dirty");
}
