import { applySuggestion } from "../previewModel";
import { makeSuggestion } from "../cowrite/model";
import {
  currentTarget,
  mappedAfterReplacement,
  acceptThreadVersion,
} from "./threadModel";
import type { Studio } from "../useStudio";
import type { ThreadStore } from "./useThreadStore";

/**
 * 候选动作：准备示例候选、采纳、拒绝。
 * 原生模式下候选生成/采纳被显式禁用（正式候选须走后端版本校验），只提示不动作。
 */
export function useThreadCandidates(studio: Studio, store: ThreadStore, generation: { preview(): void; apply(): void; reject(): void }) {
  const thread = store.active;
  /** 生成示例候选（仅预览模式）；锚点失效时提示先固定讨论目标。 */
  function propose() {
    if (studio.native) { generation.preview(); return; }
    if (!thread) return;
    const quote = currentTarget(studio.chapter, thread);
    if (!quote) {
      studio.setNotice("选中正文并固定讨论目标后，可以准备候选。");
      return;
    }
    store.patch(thread.id, {
      candidate: makeSuggestion(studio.chapter, quote),
      view: "candidate",
      compare: false,
    });
  }
  /**
   * 采纳候选：应用到工程正文（CAS 校验在 applySuggestion 内），
   * 先映射其他线程锚点再记录"已采纳"版本；失败以通知条透出，不静默。
   */
  function apply() {
    if (studio.native) { generation.apply(); return; }
    if (!thread?.candidate || studio.surface !== "manuscript") return;
    try {
      const project = applySuggestion(studio.project, thread.candidate);
      const chapter = project.chapters.find(
        (item) => item.id === thread.chapterId,
      )!;
      const candidate = thread.candidate;
      store.setRecords((current) =>
        mappedAfterReplacement(current, studio.chapter, chapter.body).map(
          (item) =>
            item.id === thread.id
              ? acceptThreadVersion(item, candidate, chapter)
              : item,
        ),
      );
      studio.setProject(project);
      store.close();
      studio.setNotice("已采纳这处修改，可在正文撤销。");
    } catch (error) {
      studio.setNotice(String(error));
    }
  }
  /** 拒绝候选：丢弃并回到讨论视图，正文不动。 */
  function reject() {
    if (studio.native) { generation.reject(); return; }
    if (!thread) return;
    store.patch(thread.id, { candidate: null, view: "discussion" });
  }
  return { propose, apply, reject };
}
