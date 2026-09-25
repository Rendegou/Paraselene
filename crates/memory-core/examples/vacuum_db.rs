//! 打开库（自动跑迁移到最新 schema）+ VACUUM 回收文件体积，打印前后大小。
//! 用法: cargo run --example vacuum_db -- <库文件路径>
//! 注意：VACUUM 需要约一倍库体积的临时磁盘空间。

use paraselene_memory_core::Database;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("用法: vacuum_db <库文件路径>")?;
    let before = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    let t0 = std::time::Instant::now();
    let db = Database::open(std::path::Path::new(&path))?;
    let version: u32 = db.with_conn(|conn| {
        Ok(conn.query_row("PRAGMA user_version", [], |r| r.get(0))?)
    })?;
    println!("opened: user_version={version}, {} ms", t0.elapsed().as_millis());

    let t1 = std::time::Instant::now();
    db.vacuum()?;
    let after = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    println!(
        "vacuum: {} ms, size {} -> {} bytes ({}%)",
        t1.elapsed().as_millis(),
        before,
        after,
        if before > 0 { after * 100 / before } else { 0 }
    );
    Ok(())
}
