//! 本机原文检索（首版线性扫描 + 别名扩展 + 章序范围过滤）。
//! 未来信息隔离：默认只检索 order 不高于目标章的确认章节（含目标章），
//! 历史改写模式由调用方收紧。FTS/trigram 索引为后续增强（见 T05E 证据）。

use paraselene_memory_core::NovelCanonicalEntry;

use super::budget::estimate_tokens;
use super::budget::EstimatorInfo;

/// 参与检索的章节引用：确认条目 + 显式章序。
/// 章序由调用方负责过滤（不高于目标章），本模块不做未来信息隔离判断。
pub struct ChapterRef<'a> {
    pub entry: &'a NovelCanonicalEntry,
    pub order_index: i64,
}

/// 一次章节检索命中：片段坐标（字符序号，含起点不含终点）+ 命中计数。
/// 坐标基于当前确认版本，供 manifest 审计与 UI 跳转定位。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RetrievalHit {
    pub document_id: String,
    /// 命中时点的确认版本；版本变化后此片段坐标可能失效。
    pub version_id: String,
    pub title: String,
    /// 片段在章节内的起点（字符序号，含）。
    pub start_char: usize,
    /// 片段在章节内的终点（字符序号，不含）。
    pub end_char: usize,
    /// 截出的原文片段（±40 字窗口）。
    pub snippet: String,
    /// 全部检索词在该章节的总命中次数（排序主键）。
    pub occurrences: usize,
}

/// 别名扩展：命中的条目名/别名作为额外检索词（同义词召回）。
pub fn expand_query(query: &str, lore_entries: &[(String, Vec<String>)]) -> Vec<String> {
    let mut terms: Vec<String> = query
        .split_whitespace()
        .flat_map(|part| part.split(|ch: char| !ch.is_alphanumeric() && ch != '“' && ch != '”'))
        .filter(|part| !part.is_empty())
        .map(str::to_string)
        .collect();
    for (name, aliases) in lore_entries {
        if terms.iter().any(|term| aliases.contains(term) || term == name) {
            terms.push(name.clone());
        }
    }
    terms.sort();
    terms.dedup();
    terms
}

/// 检索：只扫章节（kind == "chapter"），命中计数 + 截 ±40 字片段。
/// 排序：命中数降序，再按章序降序（近期优先）。
pub fn search_chapters<'a, I>(
    chapters: I,
    terms: &[String],
    limit: usize,
) -> Vec<RetrievalHit>
where
    I: Iterator<Item = ChapterRef<'a>>,
{
    let mut scored: Vec<(RetrievalHit, i64)> = Vec::new();
    for chapter in chapters {
        let body = &chapter.entry.body;
        let mut occurrences = 0usize;
        let mut first_byte = None;
        for term in terms {
            let mut offset = 0usize;
            while let Some(pos) = body[offset..].find(term) {
                occurrences += 1;
                let abs = offset + pos;
                if first_byte.is_none() {
                    first_byte = Some(abs);
                }
                offset = abs + term.len();
                if offset >= body.len() {
                    break;
                }
            }
        }
        if occurrences == 0 {
            continue;
        }
        // 片段窗口：命中点前 40 字符起，前后各 40 字符（字符序号口径）。
        // 以"最早命中的词"为锚，窗口只保证覆盖首个命中点附近语境。
        let char_pos = body[..first_byte.unwrap()].chars().count();
        let chars: Vec<char> = body.chars().collect();
        let start = char_pos.saturating_sub(40);
        let end = (char_pos + terms.iter().map(|t| t.chars().count()).max().unwrap_or(1) + 40)
            .min(chars.len());
        scored.push((
            RetrievalHit {
                document_id: chapter.entry.document_id.clone(),
                version_id: chapter.entry.version_id.clone(),
                title: chapter.entry.title.clone(),
                start_char: start,
                end_char: end,
                snippet: chars[start..end].iter().collect(),
                occurrences,
            },
            chapter.order_index,
        ));
    }
    scored.sort_by(|(a_hit, a_order), (b_hit, b_order)| {
        b_hit
            .occurrences
            .cmp(&a_hit.occurrences)
            .then(b_order.cmp(a_order))
    });
    scored.truncate(limit);
    scored.into_iter().map(|(hit, _)| hit).collect()
}

/// 预算内贪心装入检索结果；装不下的由调用方记入 omitted。
pub fn fit_hits(
    hits: Vec<RetrievalHit>,
    budget_tokens: u64,
    estimator: &EstimatorInfo,
) -> (Vec<RetrievalHit>, Vec<RetrievalHit>) {
    let mut used = 0u64;
    let mut kept = Vec::new();
    let mut omitted = Vec::new();
    for hit in hits {
        let cost = estimate_tokens(estimator, &hit.snippet);
        if used + cost <= budget_tokens {
            used += cost;
            kept.push(hit);
        } else {
            omitted.push(hit);
        }
    }
    (kept, omitted)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(body: &str) -> NovelCanonicalEntry {
        NovelCanonicalEntry {
            document_id: "d".into(),
            version_id: "v".into(),
            kind: "chapter".into(),
            title: "章".into(),
            body: body.into(),
        }
    }

    #[test]
    fn 别名扩展加入规范名() {
        let lore = vec![("林晚".to_string(), vec!["阿晚".to_string()])];
        let terms = expand_query("阿晚 去了 城门", &lore);
        assert!(terms.contains(&"林晚".to_string()));
    }

    #[test]
    fn 检索命中计数并给出片段坐标() {
        let entries = vec![entry("她去了城门。城门下有猫。")];
        let refs: Vec<ChapterRef> = entries.iter().map(|e| ChapterRef { entry: e, order_index: 0 }).collect();
        let hits = search_chapters(refs.into_iter(), &["城门".to_string()], 5);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].occurrences, 2);
        assert!(hits[0].snippet.contains("城门"));
        assert!(hits[0].start_char < hits[0].end_char);
    }

    #[test]
    fn 预算裁剪分出保留与省略() {
        let est = super::super::budget::chinese_char_estimator();
        let hits = vec![
            RetrievalHit { document_id: "a".into(), version_id: "v".into(), title: "A".into(), start_char: 0, end_char: 5, snippet: "一二三四五".into(), occurrences: 3 },
            RetrievalHit { document_id: "b".into(), version_id: "v".into(), title: "B".into(), start_char: 0, end_char: 5, snippet: "一二三四五".into(), occurrences: 2 },
        ];
        // 每条 12 token（5 字 + 20% 裕量），预算 12 只装得下第一条。
        let (kept, omitted) = fit_hits(hits, 12, &est);
        assert_eq!(kept.len(), 1);
        assert_eq!(omitted.len(), 1);
        assert_eq!(kept[0].document_id, "a", "高命中优先保留");
    }
}
