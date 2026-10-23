// 设定集侧栏。展示约定见下方 LoreShelf 的文档注释。

import { useState } from "react";
import type { LoreEntry, LoreKindName } from "../contracts";
import { loreKindNames } from "./LoreDetail";

/// 设定类型展示顺序（人物→世界→时间线→禁忌→文风）；空组不渲染，保持侧栏紧凑。
const loreKinds: LoreKindName[] = ["character", "world", "timeline", "taboo", "style"];

/// 条目状态中文名；未知状态原样展示，避免新状态被静默吞掉。
const statusNames: Record<string, string> = { candidate: "候选", confirmed: "已确认", rejected: "已否决" };

/**
 * 设定集侧栏：按类型分组的条目列表 + 新建（作者确认来源）。
 * 同名条目并列显示不合并——同名是允许的，合并会丢失作者刻意保留的区分。
 */
export function LoreShelf(props: {
  entries: LoreEntry[];
  loading: boolean;
  busy: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onCreate: (kind: LoreKindName, name: string, body: string, aliases: string[]) => Promise<unknown>;
  notify: (msg: string) => void;
}) {
  const [newKind, setNewKind] = useState<LoreKindName>("character");
  const [newName, setNewName] = useState("");
  const [newBody, setNewBody] = useState("");

  async function submit() {
    if (!newName.trim() || !newBody.trim()) return;
    try {
      await props.onCreate(newKind, newName.trim(), newBody.trim(), []);
      setNewName(""); setNewBody("");
    } catch (error) { props.notify(`设定创建失败：${String(error)}`); }
  }

  return <aside className="novel-shelf" aria-label="设定集">
    <h2>设定集</h2>
    {props.loading ? <p className="novel-muted">正在读取…</p> :
      loreKinds.map((kind) => {
        const group = props.entries.filter((entry) => entry.kind === kind);
        if (group.length === 0) return null;
        return <div className="novel-group" key={kind}><h3>{loreKindNames[kind]}</h3>
          {group.map((entry) => <div className={props.selectedId === entry.id ? "novel-item selected" : "novel-item"} key={entry.id}>
            <button className="novel-item-main" type="button" disabled={props.busy}
              aria-current={props.selectedId === entry.id ? "page" : undefined}
              onClick={() => props.onSelect(entry.id)}>
              <span>{entry.name}{entry.aliases.length > 0 && <small className="novel-alias">（{entry.aliases[0]}）</small>}</span>
              <small>{statusNames[entry.status] ?? entry.status}</small>
            </button>
          </div>)}
        </div>;
      })}
    <form className="novel-new" onSubmit={(event) => { event.preventDefault(); void submit(); }}>
      <h3>新建设定</h3>
      <label htmlFor="lore-kind">类型</label>
      <select id="lore-kind" value={newKind} disabled={props.busy} onChange={(event) => setNewKind(event.target.value as LoreKindName)}>
        {loreKinds.map((kind) => <option value={kind} key={kind}>{loreKindNames[kind]}</option>)}
      </select>
      <label htmlFor="lore-name">名称</label>
      <input id="lore-name" type="text" maxLength={80} value={newName} disabled={props.busy}
        placeholder="例如：主角" onChange={(event) => setNewName(event.target.value)} />
      <label htmlFor="lore-new-body">内容</label>
      <textarea id="lore-new-body" value={newBody} maxLength={20000} disabled={props.busy}
        placeholder="性格、底线、欲望、禁忌行为…" onChange={(event) => setNewBody(event.target.value)} />
      <button className="novel-add" type="submit" disabled={props.busy || !newName.trim() || !newBody.trim()}>保存为作者确认</button>
    </form>
  </aside>;
}
