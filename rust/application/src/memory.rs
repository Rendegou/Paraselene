//! Explicit single-space memory access; importing or cloud access is never implicit.
//!
//! 记忆按 Space 隔离：小说空间必须带作品，其余空间不得带作品。写操作要求 updated_at CAS
//! 与身份匹配；软删除保留历史与来源链，导入搜索只查已导入索引，不做磁盘扫描。
use crate::{core_error, err, AppError, Session};
use paraselene_memory_core::{NewMemory, Space};
use serde_json::json;
// 空间名解析失败统一为 invalid_space，调用方无法用未知空间绕过隔离。
fn space(value: &str) -> Result<Space, AppError> {
    Space::parse(value).ok_or_else(|| err("invalid_space"))
}
impl Session {
    /// Soft deletes one explicitly confirmed record under its original scope/CAS.
    ///
    /// 记录不存在返回 not_found，空间/作品身份不符返回 identity_mismatch，已转换的想法来源返回
    /// converted_source_in_use；软删除保留历史与来源链。
    pub fn memory_delete(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
        updated_at: String,
    ) -> Result<(), AppError> {
        let selected = space(&selected_space)?;
        self.with_db(|db| {
            let record = db
                .get_memory(&id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if record.space != selected.as_str() || record.work_id != work {
                return Err(err("identity_mismatch"));
            }
            if selected == Space::Idea && db.converted_target(&id).map_err(core_error)?.is_some() {
                return Err(err("converted_source_in_use"));
            }
            db.soft_delete_memory_if_current(&id, selected, &updated_at)
                .map_err(core_error)
        })
    }
    /// Lists one space. Novel records additionally require the selected work.
    ///
    /// 小说空间必须带作品、其他空间不得带作品，否则 identity_mismatch；只返回所属空间与作品的记录。
    pub fn memory_list(
        &self,
        selected_space: String,
        work: Option<String>,
    ) -> Result<String, AppError> {
        let selected = space(&selected_space)?;
        if (selected == Space::Novel) != work.is_some() {
            return Err(err("identity_mismatch"));
        }
        self.with_db(|db| {
            let rows = db.list_memories(selected, None).map_err(core_error)?;
            let rows: Vec<_> = rows.into_iter().filter(|row| row.work_id == work).collect();
            serde_json::to_string(&rows).map_err(|_| err("memory_read_failed"))
        })
    }
    /// Author-created note. Source/payload/status links cannot be forged by this UI.
    ///
    /// 标题上限 2000 字节、摘要上限 100000 字节，超限返回 invalid_input；只创建作者 note，
    /// 来源、状态与载荷链接不能由 UI 伪造。
    pub fn memory_create(
        &self,
        selected_space: String,
        work: Option<String>,
        title: String,
        summary: String,
    ) -> Result<String, AppError> {
        let selected = space(&selected_space)?;
        if title.len() > 2000 || summary.len() > 100_000 {
            return Err(err("invalid_input"));
        }
        self.with_db(|db| {
            let record = db
                .create_memory(NewMemory {
                    space: selected,
                    work_id: work,
                    kind: "note".into(),
                    title,
                    summary: Some(summary),
                    status: None,
                    reminder_pref: None,
                    payload: None,
                })
                .map_err(core_error)?;
            serde_json::to_string(&record).map_err(|_| err("memory_write_failed"))
        })
    }
    /// CAS correction retains source chain and immutable space/work identity.
    ///
    /// updated_at CAS 与空间/作品身份必须匹配；失败不部分更新，来源链保留。
    pub fn memory_correct(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
        updated_at: String,
        title: String,
        summary: String,
    ) -> Result<(), AppError> {
        let selected = space(&selected_space)?;
        if title.len() > 2000 || summary.len() > 100_000 {
            return Err(err("invalid_input"));
        }
        self.with_db(|db| {
            let record = db
                .get_memory(&id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if record.space != selected.as_str() || record.work_id != work {
                return Err(err("identity_mismatch"));
            }
            db.correct_memory_if_current(&id, selected, &updated_at, &title, &summary)
                .map(|_| ())
                .map_err(core_error)
        })
    }
    /// Exact recorded source plus explicit outgoing links, single-space scoped.
    ///
    /// 返回记录、来源明细与显式外链；跨空间/作品访问返回 identity_mismatch。
    pub fn memory_detail(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
    ) -> Result<String, AppError> {
        let selected = space(&selected_space)?;
        self.with_db(|db| {
            let record = db.get_memory(&id).map_err(core_error)?.ok_or_else(|| err("not_found"))?;
            if record.space != selected.as_str() || record.work_id != work { return Err(err("identity_mismatch")); }
            let sources = db.get_sources(&id).map_err(core_error)?;
            let mut details = Vec::new();
            for source in sources {
                details.push(db.get_memory_source_detail(&id, &source.session_id, source.message_seq).map_err(core_error)?);
            }
            serde_json::to_string(&json!({"record":record,"sources":details,"links":db.get_links(&id).map_err(core_error)?}))
                .map_err(|_| err("memory_read_failed"))
        })
    }
    /// Search is confined to already imported synthetic index messages, never disk scans.
    ///
    /// 空查询或超过 1000 字节返回 invalid_input；只查已导入消息索引，最多 50 条。
    pub fn search_imported(&self, text: String) -> Result<String, AppError> {
        if text.is_empty() || text.len() > 1000 {
            return Err(err("invalid_input"));
        }
        self.with_db(|db| {
            let query = paraselene_memory_core::SearchQuery {
                text,
                messages_only: true,
                limit: 50,
                ..Default::default()
            };
            serde_json::to_string(&db.search(&query).map_err(core_error)?)
                .map_err(|_| err("search_failed"))
        })
    }
}
