import { useState } from "react";
import type { ChangeDesc } from "@codemirror/state";
import { mapThread, newThread } from "./threadModel";
import type { Chapter, Selection } from "../types";
import type { ParagraphThread } from "./threadTypes";
import type { NativeStudio } from "../native/contracts";
import { usePersistentThreads } from "../native/usePersistentThreads";

/**
 * 线程存储：预览模式用 React state，原生模式委托持久化注册表（每作品独立缓存）。
 * 打开线程有相同锚点/全文语义去重；原生模式在 busy 或未就绪时拒绝开线程。
 */
export function useThreadStore(chapter: Chapter, native?: NativeStudio | null) {
  const [previewRecords, setPreviewRecords] = useState<ParagraphThread[]>([]);
  const persistence = usePersistentThreads(chapter, native);
  const records = native ? persistence.records : previewRecords;
  const setRecords = native ? persistence.setRecords : setPreviewRecords;
  const [activeId, setActiveId] = useState<string | null>(null);
  const forChapter = records.filter(
    (thread) => thread.chapterId === chapter.id,
  );
  const active = forChapter.find((thread) => thread.id === activeId) ?? null;
  /** 局部补丁更新指定线程。 */
  function patch(id: string, values: Partial<ParagraphThread>) {
    setRecords((current) =>
      current.map((thread) =>
        thread.id === id ? { ...thread, ...values } : thread,
      ),
    );
  }
  /** 打开（或复用）线程：有选区时按锚点精确匹配，无选区时复用全文线程；返回线程 id。 */
  function open(selection: Selection | null) {
    if (native && (persistence.readiness !== "ready" || native.busy)) {
      native.reportThreadError("讨论尚未加载或正在切换，请等待或重试读取");
      return "";
    }
    const existing = forChapter.find((thread) =>
      selection
        ? thread.anchor?.valid &&
          thread.anchor.from === selection.from &&
          thread.anchor.to === selection.to
        : thread.target === null,
    );
    const thread = existing ?? newThread(chapter, selection);
    if (!existing) setRecords((current) => [...current, thread]);
    setActiveId(thread.id);
    return thread.id;
  }
  /** 编辑器变更重映射所有线程锚点；原生模式走注册表（ChangeDesc 是映射证明，busy 期也有效）。 */
  function remap(changes: ChangeDesc, body: string) {
    const nextChapter = { ...chapter, body };
    const mapped = (current: ParagraphThread[]) => current.map((thread) => mapThread(thread, changes, nextChapter));
    // ChangeDesc supplies a mapping proof even when native.busy blocks author discussion edits.
    if (native) persistence.remapRecords(nextChapter, mapped);
    else setRecords(mapped);
  }
  return {
    records,
    setRecords,
    activeId,
    setActiveId,
    forChapter,
    active,
    patch,
    open,
    remap,
    close: () => setActiveId(null),
    readiness: persistence.readiness,
    retryPersistence: persistence.retryPersistence,
  };
}
/** 线程存储对外类型（由 useThreadStore 返回值推断）。 */
export type ThreadStore = ReturnType<typeof useThreadStore>;
