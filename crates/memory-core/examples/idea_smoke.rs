//! 在已授权导入库的副本上验证旧想法候选；只输出布尔值与计数，不输出私人正文。
//!
//! 用法：cargo run -p paraselene-memory-core --example idea_smoke -- <库目录>

use std::path::PathBuf;

use paraselene_memory_core::{spaces::Space, Database};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let directory = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .ok_or("用法: idea_smoke <库目录>")?;
    let db = Database::open(&directory.join("index.db"))?;
    let before = db.list_memories(Space::Idea, None)?.len();
    let candidate = db.suggest_old_idea(0)?;
    let after = db.list_memories(Space::Idea, None)?.len();
    println!("candidate_found={}", candidate.is_some());
    println!("ideas_before={before} ideas_after={after}");
    assert_eq!(before, after, "候选查询不能写入 idea 空间");
    if let Some(candidate) = candidate {
        assert!(!candidate.excerpt.is_empty());
        assert!(candidate.source_text.contains(&candidate.excerpt));
        println!("source_traceable=true");
        let next = db.suggest_old_idea(1)?;
        println!("second_candidate_found={}", next.is_some());
        if let Some(next) = next {
            assert_ne!(
                (candidate.session_id, candidate.message_seq),
                (next.session_id, next.message_seq)
            );
        }
    }
    Ok(())
}
