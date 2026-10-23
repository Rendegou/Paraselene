import type { Studio } from "../useStudio";
import type { Selection } from "../types";
import type { ReferencePosition } from "./threadTypes";
import type { ThreadStore } from "./useThreadStore";
import type { useReferenceInspector } from "./useReferenceInspector";
import type { useNotebookLayout } from "./useNotebookLayout";
/**
 * 笔记本动作组合：「讨论这段」开线程、引用检查（移动端无活跃线程时先按选区开线程再展示引用卡）。
 */
export function useNotebookActions(
  studio: Studio,
  threads: ThreadStore,
  reference: ReturnType<typeof useReferenceInspector>,
  layout: ReturnType<typeof useNotebookLayout>,
) {
  /** 对当前选区发起讨论；打开失败（如选区过期）以通知条透出。 */
  function discuss() {
    try {
      if (studio.selection) threads.open(studio.selection);
    } catch (error) {
      studio.setNotice(String(error));
    }
  }
  /** 打开设定引用卡片；移动端且当前无活跃线程时，先为给定选区开线程提供上下文。 */
  function inspect(
    id: string,
    position?: ReferencePosition,
    range?: Omit<Selection, "chapterId">,
  ) {
    if (layout.mobile && !threads.active)
      threads.open(range ? { ...range, chapterId: studio.chapter.id } : null);
    reference.show(id, position);
  }
  return { discuss, inspect };
}
