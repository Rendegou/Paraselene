// 设定集详情。契约见下方 LoreDetail 的文档注释。

import { useEffect, useState } from "react";
import type { LoreEntry, LoreVersion } from "../contracts";
import { LoreVersionHistory } from "./LoreVersionHistory";
import { LoreActions, loreStatusText } from "./LoreActions";

/// 设定类型中文名；未知类型回退展示原始 kind 字符串。
export const loreKindNames: Record<string, string> = {
  character: "人物", world: "世界", timeline: "时间线", taboo: "禁忌", style: "文风",
};

/** 作用范围枚举 → 短文案。`from:chapter` 带前缀标记：具体章节在后续版本细化，
 *  这里只承诺"自指定章节起"的语义。 */
function scopeLabel(scope: string): string {
  if (scope === "whole") return "全程有效";
  if (scope === "retrospective") return "回溯改设定";
  return "自指定章节起";
}

/**
 * 设定集详情：正文/别名/作用范围编辑、版本历史、候选决议。
 *
 * 契约：
 * - 保存始终产生新版本（旧版本留痕可查），由 `onSave` 上抛执行。
 * - 候选只能确认或否决，不能静默进正史；已否决条目全部字段只读。
 * - 编辑态由 `entry.headVersion` 等派生（见下方 effect）：条目在外部被并发
 *   更新时以新版本为准重置输入，避免基于过期内容继续编辑。
 */
export function LoreDetail(props: {
  entry: LoreEntry;
  versions: LoreVersion[];
  busy: boolean;
  onSave: (body: string, aliases: string[], scope: string) => Promise<unknown>;
  onResolve: (confirm: boolean) => Promise<void>;
  notify: (msg: string) => void;
}) {
  const [body, setBody] = useState("");
  const [aliases, setAliases] = useState("");
  const [scope, setScope] = useState("whole");
  useEffect(() => {
    const head = props.versions.find((version) => version.version === props.entry.headVersion);
    setBody(head?.body ?? "");
    setAliases(props.entry.aliases.join("，"));
    setScope(props.entry.scope);
  }, [props.entry.id, props.entry.headVersion, props.entry.aliases, props.entry.scope, props.versions]);

  async function save() {
    const aliasList = aliases.split(/[,，]/).map((item) => item.trim()).filter(Boolean);
    try { await props.onSave(body.trim(), aliasList, scope); }
    catch (error) { props.notify(`设定保存失败：${String(error)}`); }
  }

  return <section className="novel-lore-detail" aria-label="设定详情">
    <div className="novel-doc-heading">
      <div><span>{loreKindNames[props.entry.kind] ?? props.entry.kind}</span><h2>{props.entry.name}</h2></div>
      <p>{loreStatusText(props.entry)}</p>
    </div>
    {props.entry.status === "candidate" && <p className="novel-ai-warning">这是 AI 候选设定，确认前不参与正史。</p>}
    <label htmlFor="lore-body">内容</label>
    <textarea id="lore-body" value={body} maxLength={20000} disabled={props.busy || props.entry.status === "rejected"}
      onChange={(event) => setBody(event.target.value)} />
    <label htmlFor="lore-aliases">别名（用逗号分隔）</label>
    <input id="lore-aliases" value={aliases} maxLength={200} disabled={props.busy || props.entry.status === "rejected"}
      onChange={(event) => setAliases(event.target.value)} />
    <label htmlFor="lore-scope">作用范围</label>
    <select id="lore-scope" value={scope} disabled={props.busy || props.entry.status === "rejected"}
      onChange={(event) => setScope(event.target.value)}>
      <option value="whole">全程有效</option>
      <option value="retrospective">回溯改设定（对全部已确认章节生效）</option>
      <option value="from:chapter">自指定章节起（章序在后续版本细化）</option>
    </select>
    <div className="novel-patch-actions">
      <LoreActions entry={props.entry} busy={props.busy} bodyEmpty={!body.trim()}
        onSave={() => void save()} onResolve={(confirm) => void props.onResolve(confirm)} />
    </div>
    <LoreVersionHistory versions={props.versions} />
  </section>;
}

export { scopeLabel };
