// 候选 patch 审阅面板。不变量见下方 PatchReview 的文档注释。

import { useState } from "react";
import type { NovelPatchView } from "../contracts";
import { inlineSpans } from "../editor/textDiff";

/** 单块候选的字级 diff 渲染：equal 原样、removed 包 <del>、added 包 <ins>。 */
function BlockDiff({ original, replacement }: { original: string; replacement: string }) {
  const spans = inlineSpans(original, replacement);
  return <pre className="novel-patch-diff">
    {spans.map((span, index) => span.kind === "equal"
      ? <span key={index}>{span.text}</span>
      : span.kind === "removed"
        ? <del key={index}>{span.text}</del>
        : <ins key={index}>{span.text}</ins>)}
  </pre>;
}

/**
 * 候选 patch 审阅面板：逐块展示 原文→候选（字级红绿），可单块应用、全部应用或拒绝。
 *
 * 不变量：
 * - 应用永远经后端校验（头版本/revision/hash/块快照），本组件不自行改文本；
 *   位置重叠或原文已变化的块由后端拒绝，UI 只展示结果提示。
 * - 展开状态 `expanded` 是本地 UI 态（同一时刻至多一块），不上升为领域状态。
 * - 列表项 key 用 `block.index`：块序号在整份 patch 内唯一且稳定。
 */
export function PatchReview(props: {
  patch: NovelPatchView;
  busy: boolean;
  onApplyBlock: (index: number) => void;
  onApplyAll: () => void;
  onReject: () => void;
  onClose: () => void;
}) {
  const [expanded, setExpanded] = useState<number | null>(null);
  return <section className="novel-patch-review" aria-label="候选修改核对">
    <div className="novel-pane-heading"><h4>候选修改 · {props.patch.blocks.length} 块</h4>
      <span>应用到编辑稿，不影响正稿</span></div>
    <p className="novel-muted">逐块核对；位置重叠或原文变化的块后端会拒绝。已过期时整份候选不可用。</p>
    <ol className="novel-patch-list">
      {props.patch.blocks.map((block) => <li key={block.index}>
        <button type="button" className="novel-patch-block" disabled={props.busy}
          aria-expanded={expanded === block.index}
          onClick={() => setExpanded(expanded === block.index ? null : block.index)}>
          <span className="novel-patch-line">{block.original.trim() || "（新增段落）"}</span>
          <span className="novel-patch-arrow">→</span>
          <span className="novel-patch-line">{block.replacement.trim() || "（删除）"}</span>
        </button>
        {expanded === block.index && <BlockDiff original={block.original} replacement={block.replacement} />}
        <button type="button" className="secondary" disabled={props.busy}
          onClick={() => props.onApplyBlock(block.index)}>应用此块</button>
      </li>)}
    </ol>
    <div className="novel-patch-actions">
      <button className="secondary" type="button" disabled={props.busy} onClick={props.onReject}>拒绝候选</button>
      <button className="secondary" type="button" disabled={props.busy} onClick={props.onClose}>稍后核对</button>
      <button className="primary" type="button" disabled={props.busy} onClick={props.onApplyAll}>应用全部</button>
    </div>
  </section>;
}
