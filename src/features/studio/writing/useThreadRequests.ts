import { referenceSnapshots } from "../cowrite/model";
import { currentTarget } from "./threadModel";
import type { Chapter, Entity } from "../types";
import type { ThreadStore } from "./useThreadStore";

/**
 * 线程请求动作：提交讨论草稿、挂载/移除设定引用。
 * 提交契约：绑定过目标的线程在原文漂移后拒绝提交（历史保留，提示重新选段）。
 */
export function useThreadRequests(
  store: ThreadStore,
  chapter: Chapter,
  entities: Entity[],
  notify: (text: string) => void,
) {
  const thread = store.active;
  /** 提交草稿为正式请求：带当前引文快照与引用实体，清空草稿。 */
  function submit() {
    if (!thread?.draft.trim()) return;
    const quote = thread.target ? currentTarget(chapter, thread) : null;
    if (thread.target && !quote) {
      notify("原文已变化，请重新选段。历史记录仍保留。");
      return;
    }
    store.patch(thread.id, {
      requests: [
        ...thread.requests,
        {
          id: crypto.randomUUID(),
          text: thread.draft.trim(),
          quote,
          references: referenceSnapshots(entities, thread.attached),
        },
      ],
      draft: "",
      view: "discussion",
    });
  }
  /** 把设定引用挂到当前（或新建的）线程上；去重后写入。 */
  function attach(id: string) {
    const targetId = thread?.id ?? store.open(null);
    const attached = thread?.attached ?? [];
    store.patch(targetId, {
      attached: [...new Set([...attached, id])],
      view: "discussion",
    });
  }
  /** 从当前线程移除指定引用。 */
  function remove(id: string) {
    if (thread)
      store.patch(thread.id, {
        attached: thread.attached.filter((value) => value !== id),
      });
  }
  return { submit, attach, remove };
}
