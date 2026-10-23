import { targetCurrent } from "./model";
import type { Studio } from "../useStudio";

/** 判断当前候选建议是否可编辑/可采纳：有候选、处于正稿视图、且锚定段落仍是当前章节的最新内容。 */
export function candidateEditable(studio: Studio) {
  const candidate = studio.suggestion;
  return (
    !!candidate &&
    studio.surface === "manuscript" &&
    targetCurrent(studio.chapter, candidate)
  );
}

/** 审阅操作条：采纳/拒绝当前候选。采纳要求候选可编辑且替换文本非空白。 */
export function ReviewActions({ studio }: { studio: Studio }) {
  // ready 同时约束"编辑资格"与"内容非空"，避免把空替换写进正稿。
  const ready =
    candidateEditable(studio) && !!studio.suggestion?.replacement.trim();
  return (
    <footer className="cowrite-review-footer">
      <small>预览示例 · 未调用模型</small>
      <div className="cowrite-review-actions">
        <button
          type="button"
          className="cowrite-primary"
          disabled={!ready}
          onClick={studio.apply}
        >
          采纳这处
        </button>
        <button type="button" onClick={studio.reject}>
          拒绝
        </button>
      </div>
    </footer>
  );
}
