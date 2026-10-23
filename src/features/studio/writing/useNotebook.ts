import type { Studio } from "../useStudio";
import { useThreadStore } from "./useThreadStore";
import { useThreadRequests } from "./useThreadRequests";
import { useThreadCandidates } from "./useThreadCandidates";
import { useReferenceInspector } from "./useReferenceInspector";
import { useNotebookLayout } from "./useNotebookLayout";
import { useInlineEditorBridge } from "./useInlineEditorBridge";
import { useNotebookActions } from "./useNotebookActions";
import { paragraphEnd, threadMarkers } from "./threadModel";
import { useNativeGeneration } from "../native/useNativeGeneration";
/**
 * 写作笔记本总装：把线程存储、请求/候选、引用检查、布局与编辑器桥接组合为单一模型。
 * 内联槽位落在活跃线程锚点所在段落的末尾（锚点失效则无槽位）。
 */
export function useNotebook(studio: Studio, design: boolean) {
  const threads = useThreadStore(studio.chapter, studio.native);
  const requests = useThreadRequests(
    threads,
    studio.chapter,
    studio.project.entities,
    studio.setNotice,
  );
  const generation = useNativeGeneration(studio, threads);
  const candidates = useThreadCandidates(studio, threads, generation);
  const reference = useReferenceInspector();
  const layout = useNotebookLayout(studio.native?.wide, studio.native ? (wide) => studio.native?.setUi({ wide }) : undefined);
  const bridge = useInlineEditorBridge(threads, () => studio.setSelection(null));
  const actions = useNotebookActions(studio, threads, reference, layout);
  const active = threads.active;
  // 槽位位置：活跃线程段落末尾；锚点失效时收掉槽位，避免悬浮输入失锚
  const slot = active?.anchor?.valid
    ? { id: active.id, at: paragraphEnd(studio.chapter.body, active.anchor.to) }
    : null;
  return {
    ...studio,
    threads,
    requests,
    candidates,
    generation,
    reference,
    layout,
    ...bridge,
    ...actions,
    closeDiscussion: () => {
      threads.close();
      const end = active?.anchor?.to ?? studio.selection?.to;
      if (end !== undefined && end <= studio.chapter.body.length) bridge.editor.current?.resume(end);
      else bridge.editor.current?.focus();
      studio.setSelection(null);
    },
    slot,
    markers: threadMarkers(threads.forChapter),
    design,
  };
}
/** 笔记本模型类型（由 useNotebook 返回值推断）。 */
export type Notebook = ReturnType<typeof useNotebook>;
