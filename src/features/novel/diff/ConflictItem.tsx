// 单条人物冲突候选。勾选语义与判定归属见下方 ConflictItem 的文档注释。

import type { NovelDraftConflict } from "../contracts";

/**
 * 单条人物冲突候选：逐字规则 + 试写命中文字 + 出处。
 * 勾选语义是"我已核对，仍要覆盖此提示"，覆盖集合由 DraftReview 汇总，
 * 最终是否允许采纳由 reviewGuards.acceptBlocked 统一判定，本组件不做判定。
 */
export function ConflictItem(props: {
  conflict: NovelDraftConflict;
  checked: boolean;
  disabled: boolean;
  onToggle: (checked: boolean) => void;
}) {
  return <label><input type="checkbox" checked={props.checked} disabled={props.disabled}
    onChange={(event) => props.onToggle(event.target.checked)} />
    <span><strong>{props.conflict.rule}</strong>
      <small>试写命中“{props.conflict.matchedText}” · 出处：{props.conflict.sourceTitle} / {props.conflict.sourceVersionId.slice(0, 8)}</small>
      <em>我已核对，仍要覆盖此提示并采纳</em></span></label>;
}
