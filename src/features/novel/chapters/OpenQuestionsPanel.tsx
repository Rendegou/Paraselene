// 待决议题看板。契约见下方 OpenQuestionsPanel 的文档注释。

import type { NovelOpenQuestion } from "../contracts";

/**
 * 待决议题看板：只从当前确认稿提取"没想好/不知道怎么"类表述，未确认试写不入板。
 *
 * 契约：
 * - `questions` 已由状态层从确认稿版本计算，本组件只读展示，不替用户做决议。
 * - 列表项 key 使用 `sourceVersionId + index`：同一版本可能命中多条，需 index 兜底区分。
 * - 点击"查看出处"通过 `onOpen` 跳转到来源文档，由父层负责切换选中与滚动。
 */
export function OpenQuestionsPanel(props: {
  questions: NovelOpenQuestion[];
  busy: boolean;
  onOpen: (documentId: string) => void;
}) {
  return <section className="novel-questions" aria-label="待决议题"><h3>待决议题 · {props.questions.length}</h3>
    <p>从当前确认稿中的“没想好”“不知道怎么”自动收录。改好原文并确认后，这里会同步更新。</p>
    {props.questions.length === 0 ? <p className="novel-muted">当前没有待决条目。</p> :
      <ul>{props.questions.map((item, index) => <li key={`${item.sourceVersionId}-${index}`}>
        <strong>{item.text}</strong><small>出处：{item.sourceTitle} · {item.sourceVersionId.slice(0, 8)}</small>
        <button type="button" disabled={props.busy} onClick={() => props.onOpen(item.sourceDocumentId)}>查看出处</button>
      </li>)}</ul>}
  </section>;
}
