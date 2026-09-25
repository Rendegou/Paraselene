//! 用 dbstat 虚拟表查看库内各对象页占用（bundled SQLite 编译了 SQLITE_ENABLE_DBSTAT_VTAB）。
//! 用法: cargo run --example dbstat -- <库文件路径>

use paraselene_memory_core::Database;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("用法: dbstat <库文件路径>")?;
    let db = Database::open(std::path::Path::new(&path))?;
    db.with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT name, SUM(pgsize) AS bytes FROM dbstat GROUP BY name ORDER BY bytes DESC LIMIT 12",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })?;
        for r in rows {
            let (name, bytes) = r?;
            println!("{name:<32} {bytes:>14}");
        }
        Ok(())
    })?;
    Ok(())
}
