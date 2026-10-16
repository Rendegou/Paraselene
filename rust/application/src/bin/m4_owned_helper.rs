//! Cross-process helper for owned-store verification. Each invocation is a
//! fresh native process; the parent integration test supplies an isolated
//! store root and compares canonical dumps byte-for-byte.
use paraselene_application::Session;
use std::{io::Write, path::Path};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let code = match args.get(1).map(String::as_str) {
        Some("seed") => seed(&args[2]),
        Some("dump") => dump(&args[2]),
        Some("hold") => hold(&args[2], &args[3]),
        Some("crashy") => crashy(&args[2]),
        other => {
            eprintln!("unknown command {other:?}");
            2
        }
    };
    std::process::exit(code);
}

fn open(root: &str) -> Result<Session, paraselene_application::AppError> {
    Session::open_owned_at_for_test(Path::new(root))
}

fn seed(root: &str) -> i32 {
    match seed_inner(root) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

fn seed_inner(root: &str) -> Result<(), paraselene_application::AppError> {
    let s = open(root)?;
    let wa = s.create_work("作品甲".into())?;
    let wb = s.create_work("作品乙".into())?;
    let a1 = s.create_chapter(wa.id.clone(), "第一章".into())?;
    let a2 = s.create_chapter(wa.id.clone(), "第二章".into())?;
    let b1 = s.create_chapter(wb.id.clone(), "序章".into())?;
    s.save(
        wa.id.clone(),
        a1.id.clone(),
        None,
        "第一行\r\n第二行 👩\u{200d}💻 é".into(),
    )?;
    s.save(wa.id.clone(), a2.id.clone(), None, String::new())?;
    s.save(wb.id.clone(), b1.id.clone(), None, "序章正文".into())?;
    let snapshot = s.load(wa.id.clone(), a1.id.clone())?;
    let prepared = s.prepare_confirmation(
        wa.id.clone(),
        a1.id.clone(),
        snapshot.base_head_version.clone(),
        snapshot.revision.unwrap(),
    )?;
    s.confirm_chapter(wa.id.clone(), a1.id.clone(), prepared.token)?;
    s.set_ui_session(
        wa.id.clone(),
        format!(
            "{{\"schemaVersion\":1,\"chapterId\":\"{}\",\"wide\":true,\"scrollTop\":42}}",
            a2.id
        ),
    )?;
    s.select_work(wb.id.clone())?;
    dump_state(&s)?;
    s.close()
}

fn dump(root: &str) -> i32 {
    match open(root).and_then(|s| {
        dump_state(&s)?;
        s.close()
    }) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

fn hold(root: &str, millis: &str) -> i32 {
    match open(root) {
        Ok(s) => {
            println!("HOLDING");
            std::io::stdout().flush().unwrap();
            std::thread::sleep(std::time::Duration::from_millis(
                millis.parse().unwrap_or(1000),
            ));
            let _ = s.close();
            0
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

/// Open, write one published change, announce it, then hang until the parent
/// kills the process; destructors and close never run.
fn crashy(root: &str) -> i32 {
    match open(root) {
        Ok(s) => {
            let w = s.create_work("崩溃作品".into()).unwrap();
            let c = s.create_chapter(w.id.clone(), "第一章".into()).unwrap();
            s.save(w.id, c.id, None, "强杀前已发布".into()).unwrap();
            println!("SAVED");
            std::io::stdout().flush().unwrap();
            loop {
                std::thread::sleep(std::time::Duration::from_secs(60));
            }
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

/// Canonical textual image: ids, revisions, hashes, directory and settings.
/// Bodies are proven by BLAKE3 content hash, not printed.
fn dump_state(s: &Session) -> Result<(), paraselene_application::AppError> {
    let state = s.workspace_state()?;
    println!(
        "selected={}",
        state.selected_work_id.as_deref().unwrap_or("-")
    );
    println!(
        "recent={}",
        state
            .recent_works
            .iter()
            .map(|w| w.id.as_str())
            .collect::<Vec<_>>()
            .join(",")
    );
    println!("warning={}", state.warning.as_deref().unwrap_or("-"));
    for work in s.list_works()? {
        println!("work={}|{}", work.id, work.title);
        println!(
            "ui={}|{}",
            work.id,
            s.get_ui_session(work.id.clone())?.as_deref().unwrap_or("-")
        );
        let mut chapters = s.list_chapters(work.id.clone())?;
        chapters.extend(s.list_archived_chapters(work.id.clone())?);
        for chapter in chapters {
            println!(
                "chapter={}|{}|order={}|arch={}|head={}",
                chapter.id,
                chapter.title,
                chapter.order_index,
                chapter.archived,
                chapter.head_version_id.as_deref().unwrap_or("-"),
            );
            let doc = s.load(work.id.clone(), chapter.id.clone())?;
            println!(
                "doc={}|rev={}|base={}|hash={}|len={}",
                doc.document_id,
                doc.revision
                    .map(|r| r.to_string())
                    .unwrap_or_else(|| "-".into()),
                doc.base_head_version.as_deref().unwrap_or("-"),
                doc.content_hash.as_deref().unwrap_or("-"),
                doc.body.chars().count(),
            );
            for v in s.list_versions(work.id.clone(), chapter.id.clone())? {
                println!(
                    "version={}|parent={}|head={}|len={}",
                    v.id,
                    v.parent_version_id.as_deref().unwrap_or("-"),
                    v.is_head,
                    v.body.chars().count(),
                );
            }
        }
    }
    Ok(())
}
