// 待确认试写列表。guard 语义见下方 PendingDraftList 的文档注释。

import type { NovelDraft } from "../contracts";
import { compactDate } from "../format";

/**
 * 待确认试写列表：点击进入核对。
 * 点击已处于核对中的条目直接重新打开（跳过 guard）；切换到其他条目要先过
 * `guard()` 未保存保护，防止丢弃手写修改。
 */
export function PendingDraftList(props: {
  pending: NovelDraft[];
  reviewId: string | null;
  busy: boolean;
  guard: () => boolean;
  onOpen: (draft: NovelDraft) => void;
}) {
  if (props.pending.length === 0) return null;
  return <div className="novel-pending"><h4>待确认试写</h4><div className="novel-pending-list">
    {props.pending.map((item) => <button type="button" disabled={props.busy} className={props.reviewId === item.id ? "selected" : ""} key={item.id}
      onClick={() => { if (props.reviewId !== item.id && !props.guard()) return; props.onOpen(item); }}>
      {compactDate(item.createdAt)} · {item.origin === "ai" ? "AI" : "手动"}
    </button>)}</div></div>;
}
