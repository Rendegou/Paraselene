// 出处锚点列表。旧版出处的展示约定见下方 AnchorList 的文档注释。

import type { SourceAnchor } from "../contracts";

/**
 * 当前正稿的出处锚点列表。
 * `isCurrent=false` 的旧版出处仍可见，但明确提示需重绑定——锚点坐标基于旧版本字符区间，
 * 正稿变化后原坐标可能已漂移，继续引用会给出错误出处。
 */
export function AnchorList({ anchors }: { anchors: SourceAnchor[] }) {
  if (anchors.length === 0) return null;
  return <details className="novel-history"><summary>出处锚点 · {anchors.length}</summary>
    <ol>{anchors.map((anchor) => <li key={anchor.id}>
      <div><strong>{anchor.isCurrent ? "当前版本" : "旧版出处"}</strong>
        <span>{anchor.startChar}–{anchor.endChar} · {anchor.sourceVersionId.slice(0, 8)}</span></div>
      {!anchor.isCurrent && <p className="novel-ai-warning">正稿已变化，此为旧版出处；请核对后重新绑定。</p>}
      {anchor.note && <p>{anchor.note}</p>}
    </li>)}</ol>
  </details>;
}
