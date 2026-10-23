// 设定条目的状态展示与决议动作（T05D）。状态分流见下方 LoreActions / loreStatusText 的文档注释。

import type { LoreEntry } from "../contracts";

/**
 * 设定条目的状态文案：作者确认（带版本号）/ AI 候选待决议 / 已否决。
 * 版本号随确认态展示，便于用户核对"看到的是不是最新确认版"。
 */
export function loreStatusText(entry: LoreEntry): string {
  if (entry.status === "confirmed") return `作者确认 · v${entry.headVersion}`;
  if (entry.status === "candidate") return "AI 候选 · 待决议";
  return "已否决";
}

/**
 * 设定条目的可行动作（T05D）：按状态分流——
 * 候选只给 确认/否决 两个决议动作；已否决只读（返回 null）；
 * 已确认给"保存为新版本"，正文为空时禁用，防止存出空版本。
 */
export function LoreActions(props: {
  entry: LoreEntry;
  busy: boolean;
  bodyEmpty: boolean;
  onSave: () => void;
  onResolve: (confirm: boolean) => void;
}) {
  if (props.entry.status === "candidate") {
    return <>
      <button className="secondary" type="button" disabled={props.busy}
        onClick={() => props.onResolve(false)}>否决候选</button>
      <button className="primary" type="button" disabled={props.busy}
        onClick={() => props.onResolve(true)}>确认进正史</button>
    </>;
  }
  if (props.entry.status === "rejected") return null;
  return <button className="primary" type="button" disabled={props.busy || props.bodyEmpty}
    onClick={props.onSave}>保存为新版本</button>;
}
