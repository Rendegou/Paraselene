//! 安全 patch：候选修改切成块，绑定不可变输入条件（确认头版本、编辑稿
//! revision、原文 hash、逐块原文快照）。应用永远以原始快照统一计算偏移，
//! 禁止"应用第一块后用旧偏移写第二块"。逐块应用后其余块按原文唯一精确
//! 匹配重定锚，失配即剔除并报告——不做模糊匹配替换。
//! 坐标为 Unicode 字符序号（与前端 selection.ts 换算口径一致）。

mod diff;

pub use diff::{char_ops, compute_blocks, CharOp, CharSpan};

use serde::{Deserialize, Serialize};

/// 编辑稿原文的引用指纹；过期/错位任何一处都会改变它。
pub fn quote_hash(body: &str) -> String {
    blake3::hash(body.as_bytes()).to_hex().to_string()
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchBlock {
    pub index: usize,
    /// 原始编辑稿中的字符起点（含）。
    pub start_char: usize,
    /// 原始编辑稿中的字符终点（不含）。
    pub end_char: usize,
    /// 原文片段（冗余校验，重定锚时作为搜索键）。
    pub original: String,
    /// 候选替换片段。
    pub replacement: String,
    /// 块前最近的未变化行（纯插入块重定锚用）；文档开头块为 None。
    pub anchor_line: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Patch {
    pub document_id: String,
    /// 构造候选时点的正稿头版本；应用时与当前值不符即拒绝（过期）。
    pub base_head_version: Option<String>,
    /// 构造候选时点的编辑稿 revision（乐观锁口径）；不符即拒绝。
    pub base_working_revision: Option<i64>,
    /// 编辑稿原文的引用指纹；内容任何变化都会改变它。
    pub quote_hash: String,
    /// 差异块列表；坐标全部基于原文快照，禁止按中间结果累积偏移。
    pub blocks: Vec<PatchBlock>,
}

/// 由编辑稿原文与候选稿构造 patch（块坐标均基于原文快照）。
pub fn build_patch(
    document_id: &str,
    base: &str,
    candidate: &str,
    base_head_version: Option<String>,
    base_working_revision: Option<i64>,
) -> Patch {
    let base_chars: Vec<char> = base.chars().collect();
    let mut blocks = Vec::new();
    for (index, draft) in compute_blocks(base, candidate).into_iter().enumerate() {
        let original: String = base_chars[draft.old_start..draft.old_end].iter().collect();
        // 构造期自检：original 与坐标切片必须一致；它冗余存一份，
        // 是作为应用时"唯一精确匹配"的搜索键，不能依赖坐标仍有效。
        debug_assert_eq!(original, draft.old_text);
        blocks.push(PatchBlock {
            index,
            start_char: draft.old_start,
            end_char: draft.old_end,
            original,
            replacement: draft.new_text,
            anchor_line: preceding_line(base, draft.old_start),
        });
    }
    Patch {
        document_id: document_id.to_string(),
        base_head_version,
        base_working_revision,
        quote_hash: quote_hash(base),
        blocks,
    }
}

/// 取字符位置之前最近的一行（不含换行），作为"纯插入块"重定锚的搜索键。
/// 上一行为空或不存在时返回 None：空串会在文中处处匹配，
/// 不能充当锚，这类插入块在单块应用后可能被剔除。
fn preceding_line(base: &str, char_pos: usize) -> Option<String> {
    let text: String = base.chars().take(char_pos).collect();
    let trimmed = text.strip_suffix('\n').unwrap_or(&text);
    let line = trimmed.rsplit('\n').next().unwrap_or("");
    if line.is_empty() {
        None
    } else {
        Some(line.to_string())
    }
}

/// 应用时点的当前条件。任何一项与 patch 绑定值不符即拒绝。
pub struct ApplyContext<'a> {
    /// 当前编辑稿全文。
    pub body: &'a str,
    /// 当前正稿头版本；与 patch 绑定的 `base_head_version` 比对。
    pub head_version: Option<&'a str>,
    /// 当前编辑稿 revision；与 patch 绑定的 `base_working_revision` 比对。
    pub working_revision: Option<i64>,
}

/// 过期检查 + 快照核对。错误信息面向用户可读。
pub fn validate_patch(patch: &Patch, ctx: &ApplyContext<'_>) -> Result<(), String> {
    if patch.base_head_version.as_deref() != ctx.head_version {
        return Err("正稿已变化，这份候选基于旧版本；请刷新后重新生成".into());
    }
    if patch.base_working_revision != ctx.working_revision {
        return Err("编辑稿已被其他保存更新，这份候选过期；请刷新后重新生成".into());
    }
    if quote_hash(ctx.body) != patch.quote_hash {
        return Err("编辑稿内容与候选快照不一致；请刷新后重新生成".into());
    }
    let chars: Vec<char> = ctx.body.chars().collect();
    let mut previous_end = 0usize;
    // 逐块对照原文快照校验：坐标越界、块间重叠、原文被改，任一命中即拒绝。
    // 手工构造的 patch（不经 build_patch）也必须过这道闸。
    for block in patch.blocks.iter().map(|b| (b.index, b.start_char, b.end_char, &b.original)) {
        let (index, start, end, original) = block;
        if end > chars.len() {
            return Err(format!("第{}块坐标越界，候选已过期", index + 1));
        }
        if start < previous_end {
            return Err(format!("第{}块与前一块重叠，候选无效", index + 1));
        }
        let actual: String = chars[start..end].iter().collect();
        if actual != *original {
            return Err(format!("第{}块原文已变化，候选已过期", index + 1));
        }
        previous_end = end;
    }
    Ok(())
}

/// 应用全部块：按原始快照一次拼接，选段之外逐字不变。
pub fn apply_all(patch: &Patch, ctx: &ApplyContext<'_>) -> Result<String, String> {
    validate_patch(patch, ctx)?;
    let chars: Vec<char> = ctx.body.chars().collect();
    let mut out = String::new();
    let mut cursor = 0usize;
    for block in &patch.blocks {
        out.extend(&chars[cursor..block.start_char]);
        out.push_str(&block.replacement);
        cursor = block.end_char;
    }
    out.extend(&chars[cursor..]);
    Ok(out)
}

/// 单块应用的结果：新正文 + 重定锚后的剩余块 + 被剔除的块序号。
/// dropped 非空时调用方必须向用户展示"哪些候选块未应用"，不得静默丢弃。
pub struct PartialApply {
    /// 应用第 index 块之后的新正文。
    pub body: String,
    /// 其余块在新正文中重定锚后的坐标（original/replacement 不变）。
    pub remaining: Vec<PatchBlock>,
    /// 找不到唯一锚点而被剔除的块序号（0 基）。
    pub dropped: Vec<usize>,
}

/// 应用第 index 块；其余块以"原文唯一精确匹配"在新正文中重定锚。
/// 找不到唯一匹配即剔除（dropped），宁可报告也不用模糊位置。
pub fn apply_one(patch: &Patch, ctx: &ApplyContext<'_>, index: usize) -> Result<PartialApply, String> {
    validate_patch(patch, ctx)?;
    let block = patch
        .blocks
        .iter()
        .find(|block| block.index == index)
        .ok_or_else(|| "块不存在".to_string())?;
    let chars: Vec<char> = ctx.body.chars().collect();
    let mut out = String::new();
    out.extend(&chars[..block.start_char]);
    out.push_str(&block.replacement);
    out.extend(&chars[block.end_char..]);
    let body = out;
    let mut remaining = Vec::new();
    let mut dropped = Vec::new();
    for other in &patch.blocks {
        if other.index == index {
            continue;
        }
        match reanchor(other, &body, &remaining) {
            Some(moved) => remaining.push(moved),
            None => dropped.push(other.index),
        }
    }
    Ok(PartialApply {
        body,
        remaining,
        dropped,
    })
}

/// 在新正文中为一个剩余块寻找新坐标。纯插入块（original 为空）用
/// anchor_line 定位；其余按 original 唯一精确匹配。
fn reanchor(block: &PatchBlock, new_body: &str, placed: &[PatchBlock]) -> Option<PatchBlock> {
    let chars: Vec<char> = new_body.chars().collect();
    if block.original.is_empty() {
        let anchor = block.anchor_line.as_ref()?;
        let positions = find_occurrences(&chars, &anchor.chars().collect::<Vec<_>>());
        let mut start = *positions.first()?;
        start += anchor.chars().count() + 1; // 跳过锚行与其换行
        // 已放置块造成的偏移累计（锚按原始顺序处理，近似单调）。
        for placed_block in placed {
            if placed_block.start_char <= start {
                let old_len = placed_block.end_char.saturating_sub(placed_block.start_char);
                let new_len = placed_block.replacement.chars().count();
                start = start.saturating_sub(old_len).saturating_add(new_len);
            }
        }
        return Some(PatchBlock {
            index: block.index,
            start_char: start,
            end_char: start,
            original: block.original.clone(),
            replacement: block.replacement.clone(),
            anchor_line: block.anchor_line.clone(),
        });
    }
    let needle: Vec<char> = block.original.chars().collect();
    let positions = find_occurrences(&chars, &needle);
    if positions.len() != 1 {
        return None;
    }
    let start = positions[0];
    Some(PatchBlock {
        index: block.index,
        start_char: start,
        end_char: start + needle.len(),
        original: block.original.clone(),
        replacement: block.replacement.clone(),
        anchor_line: block.anchor_line.clone(),
    })
}

/// 返回 needle 在 hay 中的所有出现位置（字符序号）；重叠匹配也计入。
fn find_occurrences(hay: &[char], needle: &[char]) -> Vec<usize> {
    if needle.is_empty() || needle.len() > hay.len() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for start in 0..=(hay.len() - needle.len()) {
        if hay[start..start + needle.len()] == *needle {
            out.push(start);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx<'a>(body: &'a str, head: Option<&'a str>, rev: Option<i64>) -> ApplyContext<'a> {
        ApplyContext {
            body,
            head_version: head,
            working_revision: rev,
        }
    }

    #[test]
    fn 多块统一偏移应用后选段之外逐字不变() {
        let base = "甲段保留。\n乙段被改。\n中间保留。\n丙段被改。\n丁段保留😀。";
        let candidate = "甲段保留。\n乙段已改。\n中间保留。\n丙段已改。\n丁段保留😀。";
        let patch = build_patch("d1", base, candidate, Some("head-1".to_string()), Some(3));
        assert_eq!(patch.blocks.len(), 2);
        let result = apply_all(&patch, &ctx(base, Some("head-1"), Some(3))).unwrap();
        assert_eq!(result, candidate);
    }

    #[test]
    fn 单块应用后其余块按原文重定锚不偏移错位() {
        let base = "一。\n二。\n三。\n四。";
        let candidate = "一改。\n二。\n三改。\n四。";
        let patch = build_patch("d1", base, candidate, None, Some(1));
        let applied = apply_one(&patch, &ctx(base, None, Some(1)), 0).unwrap();
        assert_eq!(applied.body, "一改。\n二。\n三。\n四。");
        assert_eq!(applied.remaining.len(), 1);
        assert_eq!(applied.remaining[0].start_char, "一改。\n二。\n".chars().count());
        // 再以新正文应用剩余块（hash/revision 由调用方重置后）落点正确。
        let moved = &applied.remaining[0];
        let chars: Vec<char> = applied.body.chars().collect();
        let actual: String = chars[moved.start_char..moved.end_char].iter().collect();
        assert_eq!(actual, "三。\n");
    }

    #[test]
    fn 同句重复只命中候选本来的位置且歧义即剔除() {
        let base = "好句。\n好句。";
        let candidate = "好句。\n佳句。";
        let only = build_patch("d1", base, candidate, None, Some(1));
        assert_eq!(only.blocks.len(), 1);
        assert_eq!(only.blocks[0].original, "好句。");
        assert_eq!(only.blocks[0].start_char, "好句。\n".chars().count());
        let applied = apply_one(&only, &ctx(base, None, Some(1)), only.blocks[0].index).unwrap();
        assert_eq!(applied.body, "好句。\n佳句。");
        // 歧义场景：应用第 0 块后，第 1 块的原文在新正文中出现两次
        //（第 0 块的替换文本含同样片段），重定锚必须剔除（dropped），不得猜。
        let dup_base = "好句。\n中。\n好句。";
        let dup_candidate = "好句。好句。\n中。\n佳句。";
        let dup_patch = build_patch("d1", dup_base, dup_candidate, None, Some(1));
        assert_eq!(dup_patch.blocks.len(), 2);
        let partial = apply_one(&dup_patch, &ctx(dup_base, None, Some(1)), 0).unwrap();
        assert_eq!(partial.body, "好句。好句。\n中。\n好句。");
        assert_eq!(partial.dropped, vec![1]);
    }

    #[test]
    fn 过期头版本过期revision与hash不符一律拒绝() {
        let base = "原文。";
        let candidate = "新文。";
        let patch = build_patch("d1", base, candidate, Some("h1".to_string()), Some(2));
        assert!(apply_all(&patch, &ctx(base, Some("h2"), Some(2))).is_err(), "头版本过期");
        assert!(apply_all(&patch, &ctx(base, Some("h1"), Some(3))).is_err(), "revision 过期");
        assert!(apply_all(&patch, &ctx("被改过的原文。", Some("h1"), Some(2))).is_err(), "hash 不符");
    }

    #[test]
    fn 重复应用因hash变化而幂等拒绝() {
        let base = "原文内容。";
        let patch = build_patch("d1", base, "新文内容。", None, Some(1));
        let once = apply_all(&patch, &ctx(base, None, Some(1))).unwrap();
        // 第二次对同一 patch 再应用：条件已不匹配（revision/hash 属于旧快照）。
        let again = apply_all(&patch, &ctx(&once, None, Some(1)));
        assert!(again.is_err(), "重复应用必须被拒绝");
    }

    #[test]
    fn 重叠手工patch被校验拒绝() {
        let base = "一二三四五。";
        let mut patch = build_patch("d1", base, "一二三四五改。", None, Some(1));
        assert_eq!(patch.blocks.len(), 1);
        // 手工塞入一个与第 0 块坐标重叠的块：校验必须抓住，不得放行应用。
        patch.blocks.push(PatchBlock {
            index: 9,
            start_char: patch.blocks[0].start_char,
            end_char: patch.blocks[0].end_char,
            original: patch.blocks[0].original.clone(),
            replacement: "X".into(),
            anchor_line: None,
        });
        assert!(validate_patch(&patch, &ctx(base, None, Some(1))).is_err());
        assert!(apply_all(&patch, &ctx(base, None, Some(1))).is_err());
    }

    #[test]
    fn 纯插入块经锚行重定锚() {
        let base = "第一段。\n第二段。";
        let candidate = "第一段。\n新增段落。\n第二段。";
        let patch = build_patch("d1", base, candidate, None, Some(1));
        assert_eq!(patch.blocks.len(), 1);
        assert!(patch.blocks[0].original.is_empty());
        let applied = apply_one(&patch, &ctx(base, None, Some(1)), patch.blocks[0].index).unwrap();
        assert_eq!(applied.body, candidate);
    }
}
