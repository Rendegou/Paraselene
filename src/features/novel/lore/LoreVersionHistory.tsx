// 设定条目的版本历史。展示约定见下方 LoreVersionHistory 的文档注释。

import type { LoreVersion } from "../contracts";

/**
 * 设定条目的版本历史：倒序展示，作者/AI 来源与确认留痕可见。
 * 列表用后端返回顺序（最新在前），不做前端重排。
 */
export function LoreVersionHistory({ versions }: { versions: LoreVersion[] }) {
  return <details className="novel-history"><summary>版本历史 · {versions.length}</summary>
    {versions.length === 0 ? <p className="novel-muted">保存第一版后出现版本记录。</p> :
      <ol>{versions.map((version) => <li key={version.id}>
        <div><strong>v{version.version}</strong><span>{version.origin === "author" ? "作者" : "AI"} · {version.confirmed ? "已确认" : "未确认"}</span></div>
        <p>{version.body.slice(0, 120)}{version.body.length > 120 ? "…" : ""}</p>
      </li>)}</ol>}
  </details>;
}
