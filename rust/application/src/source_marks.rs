//! Read-only current-version manuscript decorations. Rust owns coordinates/hash.
//!
//! 只有编辑器正文与当前 head 逐字节相等时才解析标注；坐标以 UTF-16 码元存储、按 Unicode 标量
//! 区间还原，哈希不匹配立即失败而非迁移旧坐标。
use crate::{core_error, err, AppError, Session};
use rusqlite::params;
use serde_json::json;

impl Session {
    /// Returns only exact current-head sources; offsets are UTF-16 code units.
    /// A dirty editor body returns an empty list, never relocated old coordinates.
    ///
    /// body 上限 16 MB；只有编辑器正文与当前 head 完全一致才解析标注，否则返回空列表；
    /// 哈希不符返回 source_hash_mismatch，坐标非法返回 invalid_source。
    pub fn chapter_source_marks(
        &self,
        work: String,
        chapter: String,
        body: String,
    ) -> Result<String, AppError> {
        if body.len() > 16_000_000 {
            return Err(err("invalid_input"));
        }
        self.with_db(|db| {
            let document=crate::verify(db,&work,&chapter)?;
            let head=document.head_version_id;
            if document.head_body.as_deref()!=Some(body.as_str()) || head.is_none() {
                return Ok(json!({"headVersion":head,"marks":[]}).to_string());
            }
            let offsets=Offsets::new(&body);
            let marks=db.with_conn(|conn| {
                let mut query=conn.prepare("SELECT a.start_char,a.end_char,a.quote_hash,e.id,e.name,a.id
                    FROM source_anchors a JOIN lore_source_anchors l ON l.anchor_id=a.id JOIN lore_entries e ON e.id=l.entry_id
                    WHERE a.work_id=?1 AND a.document_id=?2 AND a.source_version_id=?3 AND e.work_id=?1 AND e.status!='rejected'
                    ORDER BY a.start_char,a.end_char,e.id,a.id")?;
                let rows=query.query_map(params![work,chapter,head], |row| Ok((row.get::<_,i64>(0)?,row.get::<_,i64>(1)?,row.get::<_,String>(2)?,row.get::<_,String>(3)?,row.get::<_,String>(4)?,row.get::<_,String>(5)?)))?;
                let mut marks=Vec::new();
                for row in rows {
                    let (start,end,hash,id,name,anchor)=row?;
                    let (from,to,quote)=offsets.resolve(&body,start,end)?;
                    if blake3::hash(quote.as_bytes()).to_hex().as_str()!=hash { return Err(paraselene_memory_core::Error::parse("source_hash_mismatch")); }
                    marks.push(json!({"entryId":id,"name":name,"anchorId":anchor,"from":from,"to":to}));
                }
                Ok(marks)
            }).map_err(core_error)?;
            Ok(json!({"headVersion":head,"marks":marks}).to_string())
        })
    }
}
/// 把 UTF-16 码元索引映射到 UTF-8 字节边界，用于在精确正文上还原区间且不拆分代理对。
struct Offsets {
    bytes: Vec<usize>,
    units: Vec<usize>,
}
impl Offsets {
    // 逐字符记录字节偏移与 UTF-16 计数，末尾补哨兵便于区间取值。
    fn new(body: &str) -> Self {
        let mut bytes = Vec::new();
        let mut units = Vec::new();
        let mut count = 0;
        for (byte, ch) in body.char_indices() {
            bytes.push(byte);
            units.push(count);
            count += ch.len_utf16();
        }
        bytes.push(body.len());
        units.push(count);
        Self { bytes, units }
    }
    // 边界必须落在字符边界内；越界或空区间要求重新绑定，绝不猜测移动。
    fn resolve<'a>(
        &self,
        body: &'a str,
        start: i64,
        end: i64,
    ) -> Result<(usize, usize, &'a str), paraselene_memory_core::Error> {
        let invalid = || paraselene_memory_core::Error::parse("invalid_source");
        let start = usize::try_from(start).map_err(|_| invalid())?;
        let end = usize::try_from(end).map_err(|_| invalid())?;
        if start >= end || end >= self.bytes.len() {
            return Err(invalid());
        }
        Ok((
            self.units[start],
            self.units[end],
            &body[self.bytes[start]..self.bytes[end]],
        ))
    }
}
