//! 行/段粒度的差异分块与块内字级对比。坐标全部是 Unicode 字符序号
//! （与前端 selection.ts 换算后的口径一致；CRLF 两个字符各自计数，不折叠）。

/// 块内的一处字级变化。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CharSpan {
    /// 块内原文起点（字符序号，含）。
    pub old_start: usize,
    /// 块内原文终点（字符序号，不含）。
    pub old_end: usize,
    /// 块内新文起点。
    pub new_start: usize,
    /// 块内新文终点。
    pub new_end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CharOp {
    Equal,
    /// 删除原文 [old_start, old_end)。
    Delete { old_start: usize, old_end: usize },
    /// 在原文 old_start 处插入新文 [new_start, new_end)。
    Insert { old_start: usize, new_start: usize, new_end: usize },
    /// 替换原文 [old_start, old_end) 为新文 [new_start, new_end)。
    Replace { span: CharSpan },
}

/// 行 LCS 的规模上限：超过则退化为"整文单块"，避免二次方爆炸。
const MAX_LINES_FOR_LCS: usize = 1500;

/// 按 \n 切分行。CRLF 中 \r 保留在行尾（两个字符各计一次，不折叠），
/// 与全项目 Unicode 字符序号口径一致。
fn line_seq(text: &str) -> Vec<String> {
    text.split('\n').map(|line| line.to_string()).collect()
}

/// 把 base/candidate 按行 diff 成块：连续变化行合并为一块，块携带原文与候选全文。
/// 块不含末行尾换行（行分隔符保持"未变化"，选段之外逐字不变）。
/// 返回按原文坐标升序、互不重叠的块；纯插入块的 original 为空串。
pub fn compute_blocks(base: &str, candidate: &str) -> Vec<BlockDraft> {
    let old_lines = line_seq(base);
    let new_lines = line_seq(candidate);
    if old_lines.len() > MAX_LINES_FOR_LCS || new_lines.len() > MAX_LINES_FOR_LCS {
        return vec![BlockDraft {
            old_start: 0,
            old_end: base.chars().count(),
            old_text: base.to_string(),
            new_text: candidate.to_string(),
        }];
    }
    let matched = lcs_pairs(&old_lines, &new_lines);
    let (old_offsets, old_total) = line_offsets(&old_lines);
    let (new_offsets, new_total) = line_offsets(&new_lines);
    let old_count = old_lines.len();
    let new_count = new_lines.len();
    let span = |offsets: &[usize], total: usize, count: usize, from: usize, to: usize| {
        let start = offsets[from];
        let end = if from == to {
            offsets[from]
        } else if to < count {
            offsets[to] // 含末行尾换行；应用时选段之外仍逐字不变
        } else {
            total
        };
        (start, end)
    };
    let mut blocks = Vec::new();
    let mut old_pos = 0;
    let mut new_pos = 0;
    for (old_line, new_line) in matched {
        if old_line > old_pos || new_line > new_pos {
            let (old_start, old_end) = span(&old_offsets, old_total, old_count, old_pos, old_line);
            let (new_start, new_end) = span(&new_offsets, new_total, new_count, new_pos, new_line);
            blocks.push(BlockDraft {
                old_start,
                old_end,
                old_text: base.chars().skip(old_start).take(old_end - old_start).collect(),
                new_text: candidate.chars().skip(new_start).take(new_end - new_start).collect(),
            });
        }
        old_pos = old_line + 1;
        new_pos = new_line + 1;
    }
    if old_pos < old_count || new_pos < new_count {
        let (old_start, old_end) = span(&old_offsets, old_total, old_count, old_pos, old_count);
        let (new_start, new_end) = span(&new_offsets, new_total, new_count, new_pos, new_count);
        blocks.push(BlockDraft {
            old_start,
            old_end,
            old_text: base.chars().skip(old_start).take(old_end - old_start).collect(),
            new_text: candidate.chars().skip(new_start).take(new_end - new_start).collect(),
        });
    }
    blocks
}

/// 块草稿：diff 的直接产物，尚未绑定版本条件（由 patch 模块包装成 PatchBlock）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockDraft {
    pub old_start: usize,
    pub old_end: usize,
    pub old_text: String,
    pub new_text: String,
}

/// 行号 → 字符偏移（行尾 \n 占一个字符）。返回 (每行起点, 全文字符总数)。
fn line_offsets(lines: &[String]) -> (Vec<usize>, usize) {
    let mut offsets = Vec::with_capacity(lines.len());
    let mut total = 0usize;
    for line in lines {
        offsets.push(total);
        total += line.chars().count() + 1; // +1 为行尾 \n
    }
    // 最后一次 +1 属于文档末尾不存在的换行，退回。
    let total = total.saturating_sub(1);
    (offsets, total)
}

/// 行 LCS（DP），返回匹配上的 (old_line, new_line) 序列。
fn lcs_pairs(old_lines: &[String], new_lines: &[String]) -> Vec<(usize, usize)> {
    let n = old_lines.len();
    let m = new_lines.len();
    let mut dp = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            dp[i][j] = if old_lines[i] == new_lines[j] {
                dp[i + 1][j + 1] + 1
            } else {
                dp[i + 1][j].max(dp[i][j + 1])
            };
        }
    }
    let mut pairs = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < n && j < m {
        if old_lines[i] == new_lines[j] {
            pairs.push((i, j));
            i += 1;
            j += 1;
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            i += 1;
        } else {
            j += 1;
        }
    }
    pairs
}

/// 块内字级 diff（字符 LCS，上限内精确；超出退化为整块 Replace）。
/// 结果按原文坐标升序，供 UI 渲染字级红绿。
pub fn char_ops(old_text: &str, new_text: &str) -> Vec<CharOp> {
    // 块内字级上限独立于行级上限：块通常很短，1200 字内 LCS 够用，
    // 超出则整块视为 Replace，避免 O(n·m) 的 DP 撑爆内存。
    const MAX_CHARS_FOR_LCS: usize = 1200;
    let old_chars: Vec<char> = old_text.chars().collect();
    let new_chars: Vec<char> = new_text.chars().collect();
    if old_chars.len() > MAX_CHARS_FOR_LCS || new_chars.len() > MAX_CHARS_FOR_LCS {
        return vec![CharOp::Replace {
            span: CharSpan {
                old_start: 0,
                old_end: old_chars.len(),
                new_start: 0,
                new_end: new_chars.len(),
            },
        }];
    }
    let mut dp = vec![vec![0usize; new_chars.len() + 1]; old_chars.len() + 1];
    for i in (0..old_chars.len()).rev() {
        for j in (0..new_chars.len()).rev() {
            dp[i][j] = if old_chars[i] == new_chars[j] {
                dp[i + 1][j + 1] + 1
            } else {
                dp[i + 1][j].max(dp[i][j + 1])
            };
        }
    }
    let mut ops = Vec::new();
    let (mut i, mut j) = (0usize, 0usize);
    while i < old_chars.len() && j < new_chars.len() {
        if old_chars[i] == new_chars[j] {
            ops.push(CharOp::Equal);
            i += 1;
            j += 1;
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            ops.push(CharOp::Delete { old_start: i, old_end: i + 1 });
            i += 1;
        } else {
            ops.push(CharOp::Insert { old_start: i, new_start: j, new_end: j + 1 });
            j += 1;
        }
    }
    while i < old_chars.len() {
        ops.push(CharOp::Delete { old_start: i, old_end: i + 1 });
        i += 1;
    }
    while j < new_chars.len() {
        ops.push(CharOp::Insert { old_start: i, new_start: j, new_end: j + 1 });
        j += 1;
    }
    coalesce(ops)
}

/// 合并字级操作序列：先折叠连续的 Equal/Delete/Insert，
/// 再把"相邻删除 + 插入"合并为 Replace——UI 渲染成整段替换
/// 比渲染成先删后插更符合用户对"改了一句话"的直觉。
fn coalesce(ops: Vec<CharOp>) -> Vec<CharOp> {
    let mut out: Vec<CharOp> = Vec::with_capacity(ops.len());
    for op in ops {
        match (out.last_mut(), &op) {
            (Some(CharOp::Equal), CharOp::Equal) => {}
            (
                Some(CharOp::Delete { old_end, .. }),
                CharOp::Delete { old_start: s, old_end: e },
            ) if *old_end == *s => {
                *old_end = *e;
            }
            (
                Some(CharOp::Insert { old_start: os, new_end: ne, .. }),
                CharOp::Insert { old_start: s, new_start: ns2, new_end: e },
            ) if *os == *s && *ne == *ns2 => {
                *ne = *e;
            }
            _ => out.push(op),
        }
    }
    // Equal 与相邻删除/插入合并为 Replace（UI 更直观）。
    let mut merged: Vec<CharOp> = Vec::with_capacity(out.len());
    for op in out {
        let (old_start, old_end) = match (merged.last(), &op) {
            (Some(CharOp::Delete { old_start, old_end }), CharOp::Insert { old_start: s, .. })
                if old_end == s =>
            {
                (*old_start, *old_end)
            }
            _ => {
                merged.push(op);
                continue;
            }
        };
        if let CharOp::Insert { new_start, new_end, .. } = op {
            merged.push(CharOp::Replace {
                span: CharSpan {
                    old_start,
                    old_end,
                    new_start,
                    new_end,
                },
            });
        }
    }
    merged
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 多块按行分组且不重叠() {
        let base = "第一段。\n第二段。\n第三段。\n第四段。";
        let candidate = "第一段改。\n第二段。\n第三段改。\n第四段。";
        let blocks = compute_blocks(base, candidate);
        assert_eq!(blocks.len(), 2);
        assert!(blocks[0].old_start < blocks[1].old_start);
        assert!(blocks[0].old_end <= blocks[1].old_start, "块不得重叠");
        assert_eq!(blocks[0].old_text, "第一段。\n");
        assert_eq!(blocks[0].new_text, "第一段改。\n");
    }

    #[test]
    fn 行数超上限退化为整文单块() {
        let base = (0..1600).map(|i| format!("行{i}")).collect::<Vec<_>>().join("\n");
        let candidate = base.clone();
        let blocks = compute_blocks(&base, &candidate);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].old_start, 0);
    }

    #[test]
    fn 字级差异合并为替换并支持emoji() {
        let replace = char_ops("她说好", "她说坏");
        assert!(
            replace.iter().any(|op| matches!(op, CharOp::Replace { .. })),
            "单字替换应合并为 Replace"
        );
        let insert_only = char_ops("她说：“走。”", "她低声说：“走吧。”");
        assert!(insert_only.iter().any(|op| matches!(op, CharOp::Insert { .. })));
        let emoji_ops = char_ops("开头😀结尾", "开头😀尾");
        assert!(emoji_ops.iter().any(|op| matches!(op, CharOp::Delete { .. })));
    }

    #[test]
    fn crlf行尾不折叠() {
        let base = "甲\r\n乙";
        let candidate = "甲改\r\n乙";
        let blocks = compute_blocks(base, candidate);
        assert_eq!(blocks.len(), 1);
        assert!(blocks[0].old_text.contains("\r\n"), "CRLF 整块保留");
    }
}
