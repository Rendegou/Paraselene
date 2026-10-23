import { ChangeSet, type ChangeDesc } from "@codemirror/state";
import { captureTarget } from "../cowrite/model";
import type { Chapter, Selection } from "../types";
import type { ParagraphThread, Marker } from "./threadTypes";
import type { Suggestion } from "../types";
import { inlineSpans } from "../../novel/editor/textDiff";

/**
 * Immutable generation quotes and mapped display ranges have separate lifetimes.
 * 新建线程：target 是不可变的"代际引文"快照，anchor 是映射后的展示区间——
 * 两者生命周期独立，正文改动只影响 anchor 的有效性。
 */
export function newThread(
  chapter: Chapter,
  selection: Selection | null,
  id: string = crypto.randomUUID(),
): ParagraphThread {
  const target = selection ? captureTarget(chapter, selection) : null;
  return {
    id,
    chapterId: chapter.id,
    target,
    anchor: target ? { from: target.from, to: target.to, valid: true } : null,
    draft: "",
    attached: [],
    requests: [],
    candidate: null,
    view: "discussion",
    compare: false,
    versions: target
      ? [
          {
            id: crypto.randomUUID(),
            text: target.text,
            label: "原稿",
            body: chapter.body,
          },
        ]
      : [],
  };
}

/** 取锚点当前对应的引文快照；锚点失效/跨章/无目标时返回 null。 */
export function currentTarget(chapter: Chapter, thread: ParagraphThread) {
  const anchor = thread.anchor;
  if (!anchor?.valid || !thread.target || thread.chapterId !== chapter.id)
    return null;
  const text = chapter.body.slice(anchor.from, anchor.to);
  return captureTarget(chapter, {
    chapterId: chapter.id,
    from: anchor.from,
    to: anchor.to,
    text,
  });
}

/**
 * Never search for a similar sentence. Undo can restore a known version only at the mapped range.
 * 把线程锚点映射过编辑器变更：只认映射区间内文本与"原引文或某个已知版本"完全一致——
 * 绝不去搜相似句。已折叠的失效锚点用 -1/1 关联方向保留定位语义。
 */
export function mapThread(
  thread: ParagraphThread,
  changes: ChangeDesc,
  chapter: Chapter,
): ParagraphThread {
  if (thread.chapterId !== chapter.id || !thread.anchor || !thread.target)
    return thread;
  // 全文撤销恢复已冻结的正文快照时，原坐标可精确恢复；不搜索相似句。
  if (restoresFrozenTarget(thread, chapter.body)) {
    return { ...thread, anchor: { from: thread.target.from, to: thread.target.to, valid: true } };
  }
  const collapsed =
    !thread.anchor.valid && thread.anchor.from === thread.anchor.to;
  // 折叠锚点用负关联（靠前一位置），普通锚点用正关联（靠后一位置）
  const from = changes.mapPos(thread.anchor.from, collapsed ? -1 : 1);
  const to = Math.max(
    from,
    changes.mapPos(thread.anchor.to, collapsed ? 1 : -1),
  );
  const text = chapter.body.slice(from, to);
  const valid =
    to > from &&
    (text === thread.target.text ||
      thread.versions.some((version) => version.text === text));
  return { ...thread, anchor: { from, to, valid } };
}

/** A complete immutable snapshot supplies exact coordinates after whole-body undo. */
function restoresFrozenTarget(thread: ParagraphThread, body: string) {
  const target = thread.target;
  return !!target && body === target.baseBody &&
    body.slice(target.from, target.to) === target.text;
}

/** 求 to 之后最近一个空行的段落结尾；无空行则到文末。 */
export function paragraphEnd(body: string, to: number) {
  const at = Math.max(0, to - 1);
  const end = body.indexOf("\n\n", at);
  return end < 0 ? body.length : end;
}

/**
 * Minimal external changes retain unrelated thread positions and CodeMirror undo boundaries.
 * 把两版正文压成最小单点变更（from/to/insert）：保持无关的线程位置不动，
 * 也保住 CodeMirror 的撤销边界（合成一个大替换会破坏撤销栈）。
 */
export function bodyChange(before: string, after: string) {
  const spans = inlineSpans(before, after);
  const first = spans[0];
  const from = first.kind === "equal" ? first.text.length : 0;
  const removed = spans
    .filter((span) => span.kind === "removed")
    .map((span) => span.text)
    .join("");
  const insert = spans
    .filter((span) => span.kind === "added")
    .map((span) => span.text)
    .join("");
  return { from, to: from + removed.length, insert };
}

/** 预测"应用候选后的正文"会让各线程锚点落在哪（用于替换前的试算）。 */
export function mappedAfterReplacement(
  threads: ParagraphThread[],
  chapter: Chapter,
  nextBody: string,
) {
  const changes = ChangeSet.of(
    bodyChange(chapter.body, nextBody),
    chapter.body.length,
  );
  return threads.map((thread) =>
    mapThread(thread, changes, { ...chapter, body: nextBody }),
  );
}
/** 由有效锚点生成章节内有序编号的书边标记。 */
export function threadMarkers(threads: ParagraphThread[]): Marker[] {
  return threads
    .filter((thread) => thread.anchor?.valid)
    .sort((a, b) => a.anchor!.from - b.anchor!.from)
    .map((thread, index) => ({
      id: thread.id,
      ...thread.anchor!,
      number: index + 1,
    }));
}
/** 采纳候选：把线程目标迁移到替换文本上，追加"已采纳"版本，视图切到版本对比。 */
export function acceptThreadVersion(
  thread: ParagraphThread,
  candidate: Suggestion,
  chapter: Chapter,
): ParagraphThread {
  const target = {
    chapterId: chapter.id,
    from: candidate.from,
    to: candidate.from + candidate.replacement.length,
    text: candidate.replacement,
    baseBody: chapter.body,
  };
  return {
    ...thread,
    target,
    anchor: { from: target.from, to: target.to, valid: true },
    candidate: null,
    versions: [
      ...thread.versions,
      {
        id: crypto.randomUUID(),
        text: candidate.replacement,
        label: "已采纳",
        body: chapter.body,
      },
    ],
    view: "versions",
  };
}
