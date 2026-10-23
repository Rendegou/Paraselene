import type { Chapter, EditorSelection, PendingChange } from "./model";

/**
 * Applies only to the exact frontend snapshot; no fuzzy relocation or canonical writes.
 * 候选修改只在前端快照上试算，不做模糊重定位，也不直接写正史。
 */

/**
 * 将待采纳候选套用到章节正文快照上，返回应用后的新正文。
 * 契约：要求章节 id 与正文快照（baseBody）完全匹配，且目标区间内容仍为 before；
 * 任一核对失败都抛错，避免把候选错贴到已变化的正文上（保护手写内容）。
 */
export function applyCandidate(chapter: Chapter, change: PendingChange): string {
  if (chapter.id !== change.chapterId || chapter.body !== change.baseBody) throw new Error("正文已经变化，请重新生成修改，避免覆盖你的手写内容。");
  if (chapter.body.slice(change.from, change.to) !== change.before) throw new Error("选段无法核对，请重新选择文字。");
  return chapter.body.slice(0, change.from) + change.after + chapter.body.slice(change.to);
}

/**
 * 生成一条"体验用"修改候选（模拟 Agent 产出）。
 * 有有效选区时在选区后追加固定文本；无选区时在文末追加。仅用于演示工作台，不接真实模型。
 */
export function createExperienceChange(chapter: Chapter, selection: EditorSelection | null, instruction: string): PendingChange {
  // 选区必须属于当前章节且非空，否则视为"全文追加"
  const active = selection?.chapterId === chapter.id && selection.text.length > 0;
  const from = active ? selection.from : chapter.body.length;
  const to = active ? selection.to : from;
  const before = chapter.body.slice(from, to);
  // 追加文案是写死的演示文本（虚构故事，无隐私内容）
  const after = active
    ? before + "\n\n她停了一下，把剩下的问题留在了心里。"
    : "\n\n林汐听见钥匙碰到口袋里的信封。她按住衣角，走向窗边。\n\n“你先说。”她说。";
  return { id: crypto.randomUUID(), chapterId: chapter.id, baseBody: chapter.body, from, to, before, after, instruction };
}
