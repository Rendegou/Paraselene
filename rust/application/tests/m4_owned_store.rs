//! M4 owned-store verification across independent native processes:
//! save/restore, forced-kill recovery, second-writer rejection and tamper
//! rejection. The helper binary is a real separate process; the store root is
//! an isolated temp directory per test, never the production ROOT.
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};

const HELPER: &str = env!("CARGO_BIN_EXE_m4_owned_helper");

fn run(args: &[&str]) -> (i32, String, String) {
    let output = Command::new(HELPER)
        .args(args)
        .output()
        .expect("helper process runs");
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

/// Two independent processes: A seeds two works with precise Unicode/CRLF/empty
/// bodies, confirm, recent selection and UI session; B must restore the exact
/// canonical image byte-for-byte.
#[test]
fn two_processes_save_and_restore_exact_state() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_string_lossy().into_owned();
    let (seed_code, seeded, seed_err) = run(&["seed", &root]);
    assert_eq!((seed_code, &*seed_err), (0, ""), "seed failed: {seed_err}");
    let (dump_code, restored, dump_err) = run(&["dump", &root]);
    assert_eq!((dump_code, &*dump_err), (0, ""), "dump failed: {dump_err}");
    assert_eq!(seeded, restored);
    assert!(seeded.contains("len=0"), "empty chapter body must persist");
    assert!(
        seeded.contains("version="),
        "confirmed version must persist"
    );
    assert!(seeded.contains("scrollTop"), "UI session must persist");
    for body in [
        "第一行\r\n第二行 👩\u{200d}💻 é",
        "确认后草稿 e\u{301}",
        "序章正文 e\u{301} é\r\n",
        "",
    ] {
        assert!(restored.contains(&format!("body={}", serde_json::to_string(body).unwrap())));
        assert!(restored.contains(&format!("Hash={}", blake3::hash(body.as_bytes()))));
    }
}

fn kill_at_marker(args: &[&str], marker: &str) -> String {
    let mut child = Command::new(HELPER)
        .args(args)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut output = String::new();
    let mut reached = false;
    for line in BufReader::new(child.stdout.take().unwrap()).lines() {
        let line = line.unwrap();
        if line == marker {
            reached = true;
            break;
        }
        output.push_str(&line);
        output.push('\n');
    }
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(reached, "child exited before marker {marker}");
    output
}

#[test]
fn complete_fixture_survives_forced_termination() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_str().unwrap();
    let before = kill_at_marker(&["seed-hold", root], "SAVED");
    let (code, restored, err) = run(&["dump", root]);
    assert_eq!((code, err.as_str()), (0, ""));
    assert_eq!(restored, before);
}

#[test]
fn publication_kill_boundaries_restore_complete_old_or_new_image() {
    for stage in [
        "during-staging",
        "after-flush",
        "before-replace",
        "after-replace",
    ] {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().to_str().unwrap();
        assert_eq!(run(&["seed", root]).0, 0);
        let before = kill_at_marker(&["boundary", root, stage], &format!("GATE:{stage}"));
        let before = before.strip_suffix("BEFORE\n").unwrap();
        let (code, restored, err) = run(&["dump", root]);
        assert_eq!((code, err.as_str()), (0, ""), "{stage}");
        let expected = if stage == "after-replace" {
            let work_line = before
                .lines()
                .find(|line| line.ends_with("|作品乙"))
                .unwrap();
            let id = work_line
                .strip_prefix("work=")
                .unwrap()
                .split('|')
                .next()
                .unwrap();
            before.replace(
                &format!("ui={id}|-"),
                &format!("ui={id}|{{\"schemaVersion\":1,\"wide\":true}}"),
            )
        } else {
            before.to_owned()
        };
        assert_eq!(restored, expected, "{stage}");
    }
}

/// A fresh store with no snapshot opens cleanly with the initial migration
/// publish and no works.
#[test]
fn empty_store_opens_with_initial_state() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_string_lossy().into_owned();
    let (code, out, err) = run(&["dump", &root]);
    assert_eq!((code, err.as_str()), (0, ""));
    assert!(!out.contains("work="));
    assert!(out.contains("selected=-"));
}

/// Forced termination after a published save: the next process restores the
/// last fully published snapshot. No claim is made for unpublished memory.
#[test]
fn killed_process_recovers_last_published_snapshot() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_string_lossy().into_owned();
    let mut child = Command::new(HELPER)
        .args(["crashy", &root])
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
        let marker = lines.next().unwrap().unwrap();
        assert_eq!(marker, "SAVED");
    }
    child.kill().unwrap();
    child.wait().unwrap();

    let (code, out, err) = run(&["dump", &root]);
    assert_eq!((code, err.as_str()), (0, ""), "reopen after kill failed");
    assert!(
        out.contains("崩溃作品"),
        "published work must survive the kill"
    );
    let expected = blake3::hash("强杀前已发布".as_bytes()).to_hex();
    assert!(
        out.contains(&format!("hash={expected}")),
        "published body hash must survive the kill"
    );
}

/// A second writer opening the same store is rejected with owned_store_busy;
/// after the first holder exits, the store opens again.
#[test]
fn second_writer_is_rejected_then_recovers() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_string_lossy().into_owned();
    let (seed_code, _, _) = run(&["seed", &root]);
    assert_eq!(seed_code, 0);

    let mut holder = Command::new(HELPER)
        .args(["hold", &root, "4000"])
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let mut lines = BufReader::new(holder.stdout.take().unwrap()).lines();
        assert_eq!(lines.next().unwrap().unwrap(), "HOLDING");
    }
    let (code, _, err) = run(&["dump", &root]);
    assert_ne!(code, 0, "second writer must fail");
    assert!(err.contains("owned_store_busy"), "unexpected error: {err}");
    holder.wait().unwrap();

    let (code, _, err) = run(&["dump", &root]);
    assert_eq!(
        (code, err.as_str()),
        (0, ""),
        "store must reopen after the holder exits"
    );
}

/// Tampering with the sealed payload, or leaving unknown content in the store
/// directory, fails closed instead of silently replacing the store.
#[test]
fn tampered_payload_and_unknown_content_are_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let root_path = dir.path();
    let root = root_path.to_string_lossy().into_owned();
    let (seed_code, _, _) = run(&["seed", &root]);
    assert_eq!(seed_code, 0);

    let payload = root_path.join("snapshot.dpapi");
    let mut bytes = std::fs::read(&payload).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 0x5A;
    std::fs::write(&payload, bytes).unwrap();
    let (code, _, err) = run(&["dump", &root]);
    assert_ne!(code, 0, "tampered payload must fail");
    assert!(
        err.contains("owned_store_invalid"),
        "unexpected error: {err}"
    );
}

#[test]
fn unknown_store_content_is_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let root_path = dir.path();
    let root = root_path.to_string_lossy().into_owned();
    let (seed_code, _, _) = run(&["seed", &root]);
    assert_eq!(seed_code, 0);
    std::fs::write(root_path.join("stray.txt"), b"unknown").unwrap();
    let (code, _, err) = run(&["dump", &root]);
    assert_ne!(code, 0, "unknown content must fail");
    assert!(
        err.contains("owned_store_invalid"),
        "unexpected error: {err}"
    );
}
