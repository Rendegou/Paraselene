//! 持久生成操作：独立于可编辑线程，唯一 operation id 防重复付费；取消和完成互斥。
use super::patch_apply::checked_base;
use super::{new_id, now, NovelPatchRecord};
use crate::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct OperationReference {
    pub id: String,
    pub version_id: String,
    pub name: String,
    pub body: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NovelOperationBinding {
    pub base_head_version: Option<String>,
    pub base_working_revision: Option<i64>,
    pub quote_hash: String,
    pub request: Value,
    pub references: Vec<OperationReference>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelOperation {
    pub operation_id: String,
    pub work_id: String,
    pub document_id: String,
    pub thread_id: String,
    pub binding: NovelOperationBinding,
    pub status: String,
    pub output: Option<String>,
    pub patch_id: Option<String>,
    pub error: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl NovelOperation {
    fn expected_patch(&self) -> NovelPatchRecord {
        NovelPatchRecord {
            id: String::new(),
            document_id: self.document_id.clone(),
            base_head_version: self.binding.base_head_version.clone(),
            base_working_revision: self.binding.base_working_revision,
            quote_hash: self.binding.quote_hash.clone(),
            blocks_json: String::new(),
            status: "pending".into(),
            created_at: self.created_at.clone(),
            resolved_at: None,
        }
    }
}

impl Database {
    /// 发送前落盘原始绑定；不可复用 operation id，归属与正文/引用版本同事务核对。
    pub fn start_novel_operation(&self, operation: &NovelOperation) -> Result<NovelOperation> {
        if operation.operation_id.is_empty()
            || operation.operation_id.len() > 200
            || operation.status != "running"
        {
            return Err(Error::parse("生成操作编号或初始状态无效"));
        }
        let binding = serde_json::to_string(&operation.binding)
            .map_err(|_| Error::parse("生成绑定无法保存"))?;
        if binding.len() > 4_000_000 {
            return Err(Error::parse("生成绑定过大"));
        }
        let timestamp = now();
        self.with_tx(|tx| {
            checked_operation_scope(tx,operation)?;
            checked_operation_base(tx,operation)?;
            tx.execute("INSERT INTO novel_operations(operation_id,work_id,document_id,thread_id,binding,status,created_at,updated_at) VALUES(?1,?2,?3,?4,?5,'running',?6,?6)",
                params![operation.operation_id,operation.work_id,operation.document_id,operation.thread_id,binding,timestamp])?;
            Ok(())
        })?;
        let mut saved = operation.clone();
        saved.created_at = timestamp.clone();
        saved.updated_at = timestamp;
        saved.output = None;
        saved.patch_id = None;
        saved.error = None;
        Ok(saved)
    }

    /// 完整响应与安全 patch 同事务保存；取消、过期和重复完成均不入候选。
    pub fn complete_novel_operation(
        &self,
        expected: &NovelOperation,
        output: &str,
        blocks_json: &str,
    ) -> Result<NovelOperation> {
        if output.trim().is_empty() || output.chars().count() > 8000 {
            return Err(Error::parse("生成片段为空或过长"));
        }
        let patch_id = new_id();
        let timestamp = now();
        self.with_tx(|tx| {
            let current=operation_query(tx,&expected.work_id,&expected.operation_id)?.ok_or_else(||Error::not_found("生成操作不存在"))?;
            if current.status!="running" || current.binding!=expected.binding || current.thread_id!=expected.thread_id || current.document_id!=expected.document_id {
                return Err(Error::parse("生成已取消或绑定已变化"));
            }
            checked_operation_scope(tx,expected)?;checked_operation_base(tx,expected)?;
            tx.execute("INSERT INTO novel_patches(id,document_id,base_head_version,base_working_revision,quote_hash,blocks_json,status,created_at) VALUES(?1,?2,?3,?4,?5,?6,'pending',?7)",
                params![patch_id,expected.document_id,expected.binding.base_head_version,expected.binding.base_working_revision,expected.binding.quote_hash,blocks_json,timestamp])?;
            tx.execute("UPDATE novel_operations SET status='completed',output=?2,patch_id=?3,updated_at=?4 WHERE operation_id=?1 AND status='running'",
                params![expected.operation_id,output,patch_id,timestamp])?;
            Ok(())
        })?;
        let mut saved = expected.clone();
        saved.status = "completed".into();
        saved.output = Some(output.into());
        saved.patch_id = Some(patch_id);
        saved.updated_at = timestamp;
        Ok(saved)
    }

    /// 取消/失败仅能从 running 出发。完成先获胜时返回 false，不覆盖成功响应。
    pub fn finish_novel_operation(
        &self,
        work_id: &str,
        operation_id: &str,
        status: &str,
        error: Option<&str>,
    ) -> Result<bool> {
        if !matches!(status, "cancelled" | "failed") || error.is_some_and(|e| e.len() > 1000) {
            return Err(Error::parse("生成终态无效"));
        }
        self.with_tx(|tx| {
            operation_query(tx,work_id,operation_id)?.ok_or_else(||Error::not_found("生成操作不存在"))?;
            Ok(tx.execute("UPDATE novel_operations SET status=?3,error=?4,updated_at=?5 WHERE operation_id=?1 AND work_id=?2 AND status='running'",
                params![operation_id,work_id,status,error,now()])?==1)
        })
    }

    pub fn get_novel_operation(
        &self,
        work_id: &str,
        operation_id: &str,
    ) -> Result<Option<NovelOperation>> {
        self.with_conn(|conn| operation_query(conn, work_id, operation_id))
    }

    /// 原始 running 在重启后的前端显示为 interrupted，不自动重发模型请求。
    pub fn list_novel_operations(
        &self,
        work_id: &str,
        document_id: &str,
    ) -> Result<Vec<NovelOperation>> {
        self.with_conn(|conn| {
            let mut stmt=conn.prepare("SELECT operation_id,work_id,document_id,thread_id,binding,status,output,patch_id,error,created_at,updated_at FROM novel_operations WHERE work_id=?1 AND document_id=?2 ORDER BY created_at,operation_id")?;
            let rows=stmt.query_map(params![work_id,document_id],read_operation)?.collect::<std::result::Result<Vec<_>,_>>()?;
            Ok(rows)
        })
    }
}

fn checked_operation_scope(conn: &rusqlite::Connection, operation: &NovelOperation) -> Result<()> {
    let owned:bool=conn.query_row("SELECT EXISTS(SELECT 1 FROM novel_threads t JOIN novel_documents d ON d.id=t.document_id JOIN works w ON w.id=t.work_id WHERE t.thread_id=?1 AND t.work_id=?2 AND t.document_id=?3 AND d.archived_at IS NULL AND w.space='novel')",
        params![operation.thread_id,operation.work_id,operation.document_id],|r|r.get(0))?;
    if !owned {
        return Err(Error::not_found("生成讨论归属无效或章节已归档"));
    }
    Ok(())
}

fn checked_operation_base(conn: &rusqlite::Connection, operation: &NovelOperation) -> Result<()> {
    checked_base(conn, &operation.expected_patch())?;
    for reference in &operation.binding.references {
        let current:bool=conn.query_row("SELECT EXISTS(SELECT 1 FROM lore_entries e JOIN lore_versions v ON v.entry_id=e.id AND v.version=e.head_version WHERE e.id=?1 AND e.work_id=?2 AND v.id=?3 AND v.confirmed=1 AND e.name=?4)",
            params![reference.id,operation.work_id,reference.version_id,reference.name],|r|r.get(0))?;
        if !current {
            return Err(Error::parse("引用资料版本已变化，请重新预览"));
        }
    }
    Ok(())
}

pub(super) fn operation_query(
    conn: &rusqlite::Connection,
    work_id: &str,
    operation_id: &str,
) -> Result<Option<NovelOperation>> {
    Ok(conn.query_row("SELECT operation_id,work_id,document_id,thread_id,binding,status,output,patch_id,error,created_at,updated_at FROM novel_operations WHERE operation_id=?1 AND work_id=?2",
        params![operation_id,work_id],read_operation).optional()?)
}

pub(super) fn checked_operation_patch(
    conn: &rusqlite::Connection,
    work_id: &str,
    operation_id: &str,
    patch_id: &str,
) -> Result<()> {
    let operation = operation_query(conn, work_id, operation_id)?
        .ok_or_else(|| Error::not_found("生成操作不存在"))?;
    if operation.status != "completed" || operation.patch_id.as_deref() != Some(patch_id) {
        return Err(Error::parse("候选不属于这次生成操作"));
    }
    checked_operation_scope(conn, &operation)?;
    checked_operation_base(conn, &operation)
}

fn read_operation(row: &rusqlite::Row<'_>) -> rusqlite::Result<NovelOperation> {
    let binding: String = row.get(4)?;
    let binding = serde_json::from_str(&binding).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(4, rusqlite::types::Type::Text, Box::new(e))
    })?;
    Ok(NovelOperation {
        operation_id: row.get(0)?,
        work_id: row.get(1)?,
        document_id: row.get(2)?,
        thread_id: row.get(3)?,
        binding,
        status: row.get(5)?,
        output: row.get(6)?,
        patch_id: row.get(7)?,
        error: row.get(8)?,
        created_at: row.get(9)?,
        updated_at: row.get(10)?,
    })
}
