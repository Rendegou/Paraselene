//! 设定集与出处锚点的集成测试（T05D）。提取为独立文件控制模块行数。

#[cfg(test)]
mod tests {
    use paraselene_memory_core::{Database, DraftOrigin, NovelKind};
    use paraselene_memory_core::{LoreKind, NewSourceAnchor};

    fn setup() -> (Database, String, String) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        (db, work.id, chapter.id)
    }

    fn confirm_chapter(db: &Database, chapter_id: &str, body: &str) -> String {
        let draft = db.create_novel_draft(chapter_id, body, DraftOrigin::User).unwrap();
        db.accept_novel_draft(&draft.id).unwrap().head_version_id.unwrap()
    }

    #[test]
    fn 作者设定直接确认_AI只能是候选且确认分离() {
        let (db, work_id, _) = setup();
        let author = db
            .create_lore_entry(&work_id, LoreKind::Character, "主角", "不轻易杀人", &[], true)
            .unwrap();
        assert_eq!(author.status, "confirmed");
        let ai = db
            .create_lore_entry(&work_id, LoreKind::World, "月港", "港口城市", &[], false)
            .unwrap();
        assert_eq!(ai.status, "candidate");
        assert!(db.resolve_lore_entry(&ai.id, true).is_ok());
        assert_eq!(db.get_lore_entry(&ai.id).unwrap().unwrap().status, "confirmed");
        // 已确认的不能再走候选决议。
        assert!(db.resolve_lore_entry(&author.id, false).is_err());
    }

    #[test]
    fn 同名异人不自动合并_别名可检索() {
        let (db, work_id, _) = setup();
        let a = db
            .create_lore_entry(&work_id, LoreKind::Character, "林", "甲线的林", &["阿林".into()], true)
            .unwrap();
        let b = db
            .create_lore_entry(&work_id, LoreKind::Character, "林", "乙线的林", &[], true)
            .unwrap();
        assert_ne!(a.id, b.id);
        let by_name = db.find_lore_by_name(&work_id, "林").unwrap();
        assert_eq!(by_name.len(), 2, "同名两人都要返回，由用户分辨");
        let by_alias = db.find_lore_by_name(&work_id, "阿林").unwrap();
        assert_eq!(by_alias.len(), 1);
        assert_eq!(by_alias[0].id, a.id);
    }

    #[test]
    fn 版本链乐观锁与作用范围() {
        let (db, work_id, _) = setup();
        let entry = db
            .create_lore_entry(&work_id, LoreKind::Taboo, "禁忌", "不许提海", &[], true)
            .unwrap();
        let updated = db
            .update_lore_entry(&entry.id, 1, "不许提海与火", &[], "from:chapter-9", true)
            .unwrap();
        assert_eq!(updated.head_version, 2);
        assert_eq!(updated.scope, "from:chapter-9");
        // 过期 expected_version 拒绝。
        assert!(db.update_lore_entry(&entry.id, 1, "又改", &[], "whole", true).is_err());
        let versions = db.list_lore_versions(&entry.id).unwrap();
        assert_eq!(versions.len(), 2);
        assert_eq!(versions[0].version, 2);
        assert!(versions.iter().all(|v| v.confirmed));
        // 非法 scope 拒绝。
        assert!(db.update_lore_entry(&entry.id, 2, "x", &[], "anywhere", true).is_err());
    }

    #[test]
    fn 回溯改设定保留全部历史且可回溯查看() {
        let (db, work_id, _) = setup();
        let entry = db
            .create_lore_entry(&work_id, LoreKind::Style, "文风", "短句白描", &[], true)
            .unwrap();
        db.update_lore_entry(&entry.id, 1, "短句白描，对白不解释情绪", &[], "retrospective", true)
            .unwrap();
        let versions = db.list_lore_versions(&entry.id).unwrap();
        assert_eq!(versions.len(), 2);
        assert_eq!(versions.last().unwrap().body, "短句白描");
    }

    #[test]
    fn 出处锚点校验版本归属边界与hash() {
        let (db, work_id, chapter_id) = setup();
        let head = confirm_chapter(&db, &chapter_id, "她说：“走吧。”\n后来离开。");
        let chars: Vec<char> = "她说：“走吧。”\n后来离开。".chars().collect();
        let start = 0;
        let end = "她说：“走吧。”".chars().count();
        let hash = blake3::hash(chars[start..end].iter().collect::<String>().as_bytes()).to_hex().to_string();
        let anchor = db
            .add_source_anchor(&NewSourceAnchor {
                work_id: &work_id,
                document_id: &chapter_id,
                source_version_id: &head,
                start_char: start as i64,
                end_char: end as i64,
                quote_hash: &hash,
                note: Some("对白出处"),
            })
            .unwrap();
        assert!(anchor.is_current);
        // hash 不符 / 越界 / 版本不属于该文档 都拒绝。
        let bad = |hash: &str, start: i64, end: i64, version: &str| {
            db.add_source_anchor(&NewSourceAnchor {
                work_id: &work_id,
                document_id: &chapter_id,
                source_version_id: version,
                start_char: start,
                end_char: end,
                quote_hash: hash,
                note: None,
            })
            .is_err()
        };
        assert!(bad("bad-hash", 0, 3, &head), "hash 不符");
        assert!(bad(&hash, 0, 999, &head), "越界");
        assert!(bad(&hash, 0, 3, "other-version"), "版本不属于该文档");
    }

    #[test]
    fn 头版本移动后锚点变旧版且文档删除级联清理() {
        let (db, work_id, chapter_id) = setup();
        let head = confirm_chapter(&db, &chapter_id, "第一版正文。");
        let hash = blake3::hash("第一版正文。".as_bytes()).to_hex().to_string();
        let end = "第一版正文。".chars().count() as i64;
        let anchor = db
            .add_source_anchor(&NewSourceAnchor {
                work_id: &work_id,
                document_id: &chapter_id,
                source_version_id: &head,
                start_char: 0,
                end_char: end,
                quote_hash: &hash,
                note: None,
            })
            .unwrap();
        // 回滚/新确认使头移动：旧锚点保留但 is_current=false（旧版出处可见）。
        let second = confirm_chapter(&db, &chapter_id, "第二版正文。");
        let _ = second;
        let anchors = db.list_source_anchors(&chapter_id).unwrap();
        assert_eq!(anchors.len(), 1);
        assert!(!anchors[0].is_current, "头移动后锚点应显示为旧版出处");
        db.with_conn(|conn| {
            conn.execute("DELETE FROM novel_documents WHERE id = ?1", [&chapter_id])?;
            Ok::<_, paraselene_memory_core::Error>(())
        })
        .unwrap();
        assert!(db.list_source_anchors(&chapter_id).unwrap().is_empty());
    }
}
