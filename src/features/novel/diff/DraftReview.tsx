// 试写核对与采纳。契约见下方 DraftReview 的文档注释；
// 差异展示口径见 editor/textDiff（T05C 将升级为分块 patch）。

import type { DiffSpan } from "../editor/textDiff";
import type { NovelDraft, NovelDraftConflict } from "../contracts";
import { ConflictItem } from "./ConflictItem";
import { acceptBlocked } from "./reviewGuards";

/**
 * 试写核对与采纳面板：候选 draft 只在这里被决定命运——采纳/丢弃/继续修改。
 *
 * 契约：
 * - 采纳按钮的禁用态完全由 `acceptBlocked` 推导（busy/stale/冲突未覆盖等），
 *   本组件不额外叠加私有规则，保证 UI 与校验函数口径一致。
 * - `staleReview` 为 true（正稿已变化）时禁止采纳：draft 基于旧版本生成，
 *   采纳会静默覆盖他人/他处的修改。
 * - 冲突覆盖集合 `overrides` 是受控状态，本组件只通过 `onOverridesChange` 上报增减。
 * - diff 为前后缀裁切口径的概览（textDiff），精确核对以打开文档为准；T05C 将升级为分块 patch。
 */
export function DraftReview(props: {
  review: NovelDraft;
  staleReview: boolean;
  conflicts: NovelDraftConflict[];
  conflictsLoading: boolean;
  conflictsError: boolean;
  overrides: string[];
  onOverridesChange: (ids: string[]) => void;
  diff: DiffSpan | null;
  busy: boolean;
  onContinue: () => void;
  onDiscard: () => void;
  onAccept: () => void;
}) {
  const blocked = acceptBlocked({
    busy: props.busy, staleReview: props.staleReview, conflictsLoading: props.conflictsLoading,
    conflictsError: props.conflictsError, conflicts: props.conflicts, overrides: props.overrides,
  });
  const toggle = (id: string, checked: boolean) => props.onOverridesChange(
    checked ? [...props.overrides, id] : props.overrides.filter((item) => item !== id));
  return <div className="novel-review"><h4>正在核对这份试写</h4>
    <p>{props.staleReview ? "正稿已变化，这份试写基于旧版本。可丢弃后重新保存。" : "对照左侧正稿，决定是否采纳。"}</p>
    {props.conflictsLoading && <p>正在核对人物卡中的明确禁令…</p>}
    {props.conflictsError && <p className="novel-ai-warning">人物设定核对失败，暂不能采纳。请重新打开这份试写。</p>}
    {props.conflicts.length > 0 && <div className="novel-conflicts"><h5>可能与人物设定冲突 · {props.conflicts.length}</h5>
      <p>逐字匹配“禁止：”规则，包含引用或否定时也可能提示。请对照出处决定。</p>
      {props.conflicts.map((item) => <ConflictItem key={item.id} conflict={item}
        checked={props.overrides.includes(item.id)} disabled={props.busy}
        onToggle={(checked) => toggle(item.id, checked)} />)}
    </div>}
    {props.diff && <details className="novel-diff"><summary>查看文字差异</summary>
      {props.diff.removed || props.diff.added ? <pre>{props.diff.leadingEllipsis ? "…" : ""}{props.diff.before}<del>{props.diff.removed}</del><ins>{props.diff.added}</ins>{props.diff.after}{props.diff.trailingEllipsis ? "…" : ""}</pre> : <p>与当前正稿文字相同。</p>}
    </details>}
    <div><button className="secondary" type="button" disabled={props.busy} onClick={props.onContinue}>继续修改</button>
      <button className="secondary" type="button" disabled={props.busy} onClick={props.onDiscard}>丢弃试写</button>
      <button className="primary" type="button" disabled={blocked} onClick={props.onAccept}>采纳为正稿</button></div>
  </div>;
}
