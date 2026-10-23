import type { Chapter, Entity, Selection, Suggestion } from "../types";
import type { ChapterSession, Target } from "./contracts";

/**
 * Reject mismatched or stale live selections; never relocate by matching a similar phrase.
 * 把编辑器选区冻结为讨论目标：逐字符核对坐标与文本，任何不符都抛错——
 * 绝不做相似句重定位。
 */
export function captureTarget(chapter: Chapter, selection: Selection): Target {
  if (
    selection.chapterId !== chapter.id ||
    !Number.isInteger(selection.from) ||
    !Number.isInteger(selection.to)
  )
    throw new Error("选段不属于当前章节");
  if (
    selection.from < 0 ||
    selection.to <= selection.from ||
    selection.to > chapter.body.length ||
    chapter.body.slice(selection.from, selection.to) !== selection.text
  )
    throw new Error("选段已变化，请重新选择正文");
  return { ...selection, baseBody: chapter.body };
}

/** 目标是否仍然"当前"：同章、正文未漂移、区间文本未变（三方核对）。 */
export function targetCurrent(chapter: Chapter, target: Target): boolean {
  return (
    chapter.id === target.chapterId &&
    chapter.body === target.baseBody &&
    chapter.body.slice(target.from, target.to) === target.text
  );
}

/** 目标的人类可读标签："全章" 或 "第N段 · M字"。 */
export function targetLabel(target: Target | null): string {
  if (!target) return "全章";
  const paragraph = target.baseBody
    .slice(0, target.from)
    .split(/\n\s*\n/).length;
  return `第${paragraph}段 · ${Array.from(target.text).length}字`;
}

/** 演示会话的初始状态：仅示例工程 ch-3 预绑定名句作为目标，其余章节无目标。 */
export function initialSession(chapter: Chapter): ChapterSession {
  const quote = "“你还是来了。”";
  const from = chapter.id === "ch-3" ? chapter.body.indexOf(quote) : -1;
  const target =
    from < 0
      ? null
      : captureTarget(chapter, {
          chapterId: chapter.id,
          from,
          to: from + quote.length,
          text: quote,
        });
  return { draft: "", target, attached: [], notes: [] };
}

/**
 * Store the author's selected references at submission time; later edits cannot rewrite a note.
 * 取作者选定的引用快照：提交时刻冻结 id/name/body，
 * 之后对设定的任何修改都不能回溯改写已有批注。
 */
export function referenceSnapshots(entities: Entity[], ids: string[]) {
  return entities
    .filter((entity) => ids.includes(entity.id))
    .map(({ id, name, body }) => ({ id, name, body }));
}

/** 生成示例候选（预览演示）：目标漂移即拒绝；替换文本仅对示例引文有预设值。 */
export function makeSuggestion(chapter: Chapter, target: Target): Suggestion {
  if (!targetCurrent(chapter, target))
    throw new Error("讨论原文已变化，请重新引用选段");
  return {
    ...target,
    replacement: target.text === "“你还是来了。”" ? "“我猜你会来。”" : "",
  };
}
