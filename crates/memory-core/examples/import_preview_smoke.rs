//! 只读验证用户已授权的导出文件；仅输出计数与布尔值，不输出私人正文和文件名。
//!
//! 用法：cargo run -p paraselene-memory-core --example import_preview_smoke -- <来源> <文件路径>

use std::path::PathBuf;

use paraselene_memory_core::import_file::read_import_file;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let source = args
        .next()
        .ok_or("用法: import_preview_smoke <来源> <文件路径>")?;
    let path = PathBuf::from(
        args.next()
            .ok_or("用法: import_preview_smoke <来源> <文件路径>")?,
    );
    let original = blake3::hash(&std::fs::read(&path)?);
    let preview = read_import_file(&path, &source)?;
    let unchanged = blake3::hash(&std::fs::read(&path)?) == original;
    let messages: usize = preview
        .package
        .sessions
        .iter()
        .map(|session| session.messages.len())
        .sum();
    println!("detected_format={}", preview.format.label());
    println!(
        "sessions={} messages={messages}",
        preview.package.sessions.len()
    );
    println!(
        "failed_files={} warning_count={}",
        preview.failed_files,
        preview.warnings.len()
    );
    println!("source_unchanged={unchanged}");
    assert!(unchanged, "预览不能修改用户原始文件");
    Ok(())
}
