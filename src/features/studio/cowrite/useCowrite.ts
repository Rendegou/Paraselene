import { captureTarget, referenceSnapshots, targetCurrent } from "./model";
import { useChapterSessions } from "./useChapterSessions";
import { useCowriteView } from "./useCowriteView";
import type { Chapter, Entity, Selection } from "../types";

/**
 * 协作写作 Hook：会话、视图与动作的组合。
 * 提交契约：绑定目标漂移时拒绝提交（批注里的引文不能脱离原文语境）。
 */
export function useCowrite(
  chapter: Chapter,
  entities: Entity[],
  selection: Selection | null,
  notify: (text: string) => void,
) {
  const { session, update } = useChapterSessions(chapter);
  const view = useCowriteView(chapter.id);
  const { setMode } = view;
  /** 把当前选区固定为讨论目标（失效选区以通知条透出）。 */
  function discussSelection() {
    if (!selection) return;
    try {
      update({ target: captureTarget(chapter, selection) });
      setMode("chat");
    } catch (error) {
      notify(String(error));
    }
  }
  /** 挂载设定引用（去重）。 */
  function attach(id: string) {
    update({
      attached: session.attached.includes(id)
        ? session.attached
        : [...session.attached, id],
    });
    setMode("chat");
  }
  /** 提交批注：冻结目标与引用快照，清空草稿。 */
  function submit() {
    if (!session.draft.trim()) return;
    if (session.target && !targetCurrent(chapter, session.target)) {
      notify("原文已变化，请重新引用选段或改为全章讨论。");
      return;
    }
    const note = {
      id: crypto.randomUUID(),
      instruction: session.draft.trim(),
      target: session.target,
      references: referenceSnapshots(entities, session.attached),
    };
    update({ notes: [...session.notes, note], draft: "" });
    setMode("chat");
  }
  return {
    ...session,
    ...view,
    discussSelection,
    attach,
    submit,
    setDraft: (draft: string) => update({ draft }),
    clearTarget: () => update({ target: null }),
    removeReference: (id: string) =>
      update({ attached: session.attached.filter((value) => value !== id) }),
  };
}
/** 协作写作对外类型。 */
export type Cowrite = ReturnType<typeof useCowrite>;
