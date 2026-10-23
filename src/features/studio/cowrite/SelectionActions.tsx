import type { Studio } from "../useStudio";

/** 正文选段悬浮操作条：显示选中字数，并发起"讨论这段"。仅在编辑器存在有效选区时出现。 */
export function SelectionActions({ studio }: { studio: Studio }) {
  if (!studio.selection) return null;
  return (
    <div className="studio-selection-actions" aria-label="选段操作">
      {/* Array.from 按码点计数，与存储层的字符口径一致。 */}
      <span>已选 {Array.from(studio.selection.text).length} 字</span>
      <button
        type="button"
        // 阻止 mousedown 默认行为，避免按钮抢走焦点导致编辑器选区先行消失。
        onMouseDown={(event) => event.preventDefault()}
        onClick={studio.cowrite.discussSelection}
      >
        讨论这段
      </button>
      <span className="studio-selection-hint">固定原文后，再提出修改要求</span>
    </div>
  );
}
