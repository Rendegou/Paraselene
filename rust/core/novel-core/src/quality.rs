//! Source-backed, deliberately narrow checks over confirmed novel documents.
//! These are candidate warnings, not a claim to understand character psychology.

use paraselene_memory_core::NovelCanonicalEntry;
use serde::Serialize;

/// An unresolved question surfaced from a confirmed document, keeping its
/// exact source so the UI can jump back to where the question was raised.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenQuestion {
    pub text: String,
    /// Document that owns the line containing the question marker.
    pub source_document_id: String,
    /// Exact confirmed version the question was scanned from (rolls back with it).
    pub source_version_id: String,
    pub source_title: String,
}

/// A candidate conflict between the draft and an explicit `禁止：` rule.
/// This is a literal-match warning only; the human still decides.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DraftConflict {
    /// Stable id: `<version_id>:<line_index>`, used for the override list.
    pub id: String,
    pub rule: String,
    pub matched_text: String,
    pub source_document_id: String,
    pub source_version_id: String,
    pub source_title: String,
}

/// Only current confirmed heads are passed in. A rejected draft cannot create a question.
pub fn open_questions(entries: &[NovelCanonicalEntry]) -> Vec<OpenQuestion> {
    entries
        .iter()
        .flat_map(|entry| {
            entry.body.lines().filter_map(move |line| {
                let text = line.trim();
                if text.is_empty() || !(text.contains("没想好") || text.contains("不知道怎么"))
                {
                    return None;
                }
                Some(OpenQuestion {
                    text: text.to_string(),
                    source_document_id: entry.document_id.clone(),
                    source_version_id: entry.version_id.clone(),
                    source_title: entry.title.clone(),
                })
            })
        })
        .collect()
}

/// Strip unresolved-question lines from a body. Hard constraints are injected
/// without these markers so a "没想好" line never becomes a binding rule.
pub fn resolved_body(body: &str) -> String {
    body.lines()
        .filter(|line| !(line.contains("没想好") || line.contains("不知道怎么")))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Matches only explicit `禁止：<literal>` lines in current character cards.
/// A literal occurrence is a candidate; quotation, negation and metaphor need human review.
pub fn draft_conflicts(entries: &[NovelCanonicalEntry], draft_body: &str) -> Vec<DraftConflict> {
    entries
        .iter()
        .filter(|entry| entry.kind == "character")
        .flat_map(|entry| {
            entry
                .body
                .lines()
                .enumerate()
                .filter_map(move |(line_index, line)| {
                    let rule = line.trim();
                    // Accept both full-width and half-width colon so cards typed
                    // on either IME still register as rules.
                    let literal = rule
                        .strip_prefix("禁止：")
                        .or_else(|| rule.strip_prefix("禁止:"))?
                        .trim();
                    // 2–80 chars: below that the match is noise, above it the
                    // "rule" is likely a prose paragraph, not a ban line.
                    if literal.chars().count() < 2
                        || literal.chars().count() > 80
                        || !draft_body.contains(literal)
                    {
                        return None;
                    }
                    Some(DraftConflict {
                        id: format!("{}:{}", entry.version_id, line_index),
                        rule: rule.to_string(),
                        matched_text: literal.to_string(),
                        source_document_id: entry.document_id.clone(),
                        source_version_id: entry.version_id.clone(),
                        source_title: entry.title.clone(),
                    })
                })
        })
        .collect()
}

/// Accept requires an explicit override for every warning in the current scan.
pub fn all_conflicts_overridden(conflicts: &[DraftConflict], ids: &[String]) -> bool {
    conflicts.iter().all(|conflict| ids.contains(&conflict.id))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(kind: &str, body: &str) -> NovelCanonicalEntry {
        NovelCanonicalEntry {
            document_id: "doc-1".into(),
            version_id: "v-1".into(),
            kind: kind.into(),
            title: "主角卡".into(),
            body: body.into(),
        }
    }

    #[test]
    fn unresolved_questions_keep_exact_confirmed_source() {
        let questions = open_questions(&[entry(
            "world",
            "城的名字没想好\n天气已确定\n不知道怎么安排入城",
        )]);
        assert_eq!(questions.len(), 2);
        assert_eq!(questions[0].source_version_id, "v-1");
        assert_eq!(questions[0].text, "城的名字没想好");
        assert_eq!(
            resolved_body("勇敢\n关系没想好\n不会放弃"),
            "勇敢\n不会放弃"
        );
    }

    #[test]
    fn conflict_requires_explicit_character_rule_and_literal_match() {
        let entries = [
            entry("character", "禁止：泄露秘密\n性格：谨慎"),
            entry("world", "禁止：使用魔法"),
        ];
        let found = draft_conflicts(&entries, "她泄露秘密后使用魔法。");
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].id, "v-1:0");
        assert_eq!(found[0].matched_text, "泄露秘密");
        assert!(draft_conflicts(&entries, "她守住秘密。").is_empty());
        assert!(!all_conflicts_overridden(&found, &[]));
        assert!(all_conflicts_overridden(&found, &[found[0].id.clone()]));
    }
}
