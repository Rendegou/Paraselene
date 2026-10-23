import { candidateEditable } from "./ReviewActions";
import { TargetQuote } from "./TargetQuote";
import type { Studio } from "../useStudio";

/**
 * 候选审阅卡片：无候选时空态引导；有候选时展示原文、可编辑的替换文本，
 * 并在锚定段落已变化时给出"回到原章重新核对"的警告。
 */
export function Review({ studio }: { studio: Studio }) {
  const suggestion = studio.suggestion;
  if (!suggestion)
    return (
      <div className="cowrite-empty">
        <h3>没有待审阅的修改</h3>
        <p>在正文选一段，固定讨论目标，再准备候选。</p>
        <button
          type="button"
          className="text-link"
          onClick={() => studio.cowrite.setMode("chat")}
        >
          返回本章共写
        </button>
      </div>
    );
  const editable = candidateEditable(studio);
  return (
    <section className="cowrite-review">
      <div className="cowrite-review-label">
        <strong>一处修改候选</strong>
        <span>预览示例</span>
      </div>
      <TargetQuote studio={studio} target={suggestion} />
      <label htmlFor="suggestion-replacement">替换为</label>
      {/* 替换文本直接受控写回 suggestion，随采纳/拒绝一起被消费或丢弃。 */}
      <textarea
        id="suggestion-replacement"
        rows={4}
        value={suggestion.replacement}
        placeholder="填写新的文字；候选在原段落旁预览…"
        onChange={(event) =>
          studio.setSuggestion({
            ...suggestion,
            replacement: event.target.value,
          })
        }
      />
      <p>正文中显示原文与候选，只修改这一处。</p>
      {/* editable=false 说明锚定段落已不是正文最新内容，此时禁止采纳防止写错位。 */}
      {!editable && (
        <p className="cowrite-warning">
          正文已变化，或当前不是所属章节。请回到原章重新核对。
        </p>
      )}
      <small>采纳只写编辑稿，可在正文撤销。</small>
    </section>
  );
}
