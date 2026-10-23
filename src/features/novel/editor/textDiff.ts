// 正稿与候选试写的文字差异：先做前后缀裁切定位变化区间，再带上下文展示。
// T05C 会替换为按行/段的 patch 结构；当前口径保留是为了试写核对不退化。
// 纯函数，不依赖 React 与 IPC，行为由同目录测试锁定。

/// 差异区间 + 两侧上下文 + 省略号标记，供"查看文字差异"折叠区渲染。
export type DiffSpan = {
  before: string;
  removed: string;
  added: string;
  after: string;
  leadingEllipsis: boolean;
  trailingEllipsis: boolean;
};

/// 差异展示保留的上下文字符数；只影响显示宽度，不影响变化区间定位。
const CONTEXT_CHARS = 55;

/// 字级 diff 的最小渲染单元。
export type InlineSpan =
  | { kind: "equal"; text: string }
  | { kind: "removed"; text: string }
  | { kind: "added"; text: string };

/// 块内字级展示：公共前后缀裁切后，中段整体标为删除+插入。
/// 与后端 patch 纯逻辑相互独立，只服务显示；坐标判断永远以后端为准。
/// 公共前缀长度（字符）。
function commonPrefix(oldChars: string[], newChars: string[]): number {
  let start = 0;
  while (start < oldChars.length && start < newChars.length && oldChars[start] === newChars[start]) start++;
  return start;
}

/// 公共后缀端点（不越过 prefix）。
function commonSuffix(oldChars: string[], newChars: string[], start: number): { oldEnd: number; newEnd: number } {
  let oldEnd = oldChars.length;
  let newEnd = newChars.length;
  while (oldEnd > start && newEnd > start && oldChars[oldEnd - 1] === newChars[newEnd - 1]) { oldEnd--; newEnd--; }
  return { oldEnd, newEnd };
}

/// 把两段文字拆成 equal/removed/added 三段式字级 span（公共前后缀裁切口径）。
/// 中段不做最小编辑距离对齐，只服务阅读级 diff 展示。
export function inlineSpans(before: string, after: string): InlineSpan[] {
  const oldChars = Array.from(before);
  const newChars = Array.from(after);
  const start = commonPrefix(oldChars, newChars);
  const { oldEnd, newEnd } = commonSuffix(oldChars, newChars, start);
  const spans: InlineSpan[] = [];
  if (start > 0) spans.push({ kind: "equal", text: oldChars.slice(0, start).join("") });
  if (oldEnd > start) spans.push({ kind: "removed", text: oldChars.slice(start, oldEnd).join("") });
  if (newEnd > start) spans.push({ kind: "added", text: newChars.slice(start, newEnd).join("") });
  if (oldEnd < oldChars.length) spans.push({ kind: "equal", text: oldChars.slice(oldEnd).join("") });
  if (spans.length === 0) return [{ kind: "equal", text: before }];
  return spans;
}

/// 概览式差异：定位公共前后缀后，带固定长度上下文返回 DiffSpan；
/// 超出上下文的两侧以省略号提示，避免长文把核对面板撑爆。
export function diffSpan(before: string, after: string): DiffSpan {
  const oldChars = Array.from(before), newChars = Array.from(after);
  let start = 0;
  while (start < oldChars.length && start < newChars.length && oldChars[start] === newChars[start]) start++;
  let oldEnd = oldChars.length, newEnd = newChars.length;
  while (oldEnd > start && newEnd > start && oldChars[oldEnd - 1] === newChars[newEnd - 1]) { oldEnd--; newEnd--; }
  return {
    before: oldChars.slice(Math.max(0, start - CONTEXT_CHARS), start).join(""),
    removed: oldChars.slice(start, oldEnd).join(""),
    added: newChars.slice(start, newEnd).join(""),
    after: oldChars.slice(oldEnd, Math.min(oldChars.length, oldEnd + CONTEXT_CHARS)).join(""),
    leadingEllipsis: start > CONTEXT_CHARS, trailingEllipsis: oldChars.length - oldEnd > CONTEXT_CHARS,
  };
}
