// 左侧作品目录：分组导航、新建、重命名、重排与待决议题。契约见下方 DocumentShelf 的文档注释。

import { useState } from "react";
import type { NovelDocumentSummary, NovelKind, NovelOpenQuestion } from "../contracts";
import { groupByKind, kindNames } from "./documentGroups";
import { OpenQuestionsPanel } from "./OpenQuestionsPanel";

/**
 * 左侧作品目录：文档分组导航、新建、重命名、重排与待决议题。
 *
 * 设计约束：
 * - 目录只是导航，不承载正文状态；顺序是显式承诺（后端 order_index），
 *   上移/下移只在同类型内交换，并向后端提交全集排列（不只提交差量），
 *   因为后端按全集顺序落库。
 * - 切换文档（选中/跳转待决议题/新建）前必须过 `guard()` 未保存保护，
 *   guard 返回 false 时中止操作，防止丢弃手写修改。
 * - 重命名/重排的失败只通过 `notify` 提示，状态由父层重新拉取纠正。
 */
export function DocumentShelf(props: {
  loading: boolean;
  documents: NovelDocumentSummary[];
  selectedId: string | null;
  busy: boolean;
  questions: NovelOpenQuestion[];
  onSelect: (id: string) => void;
  onCreate: (kind: NovelKind, title: string) => Promise<unknown>;
  onRename: (id: string, title: string) => Promise<void>;
  onReorder: (orderedIds: string[]) => Promise<void>;
  onOpenQuestion: (documentId: string) => void;
  notify: (msg: string) => void;
  guard: () => boolean;
}) {
  const [newKind, setNewKind] = useState<NovelKind>("chapter");
  const [newTitle, setNewTitle] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingTitle, setEditingTitle] = useState("");
  const groups = groupByKind(props.documents);
  const flat = props.documents;

  function startRename(item: NovelDocumentSummary) {
    setEditingId(item.id);
    setEditingTitle(item.title);
  }

  function commitRename() {
    if (!editingId) return;
    const title = editingTitle.trim();
    setEditingId(null);
    if (!title) { props.notify("标题不能为空。"); return; }
    const current = flat.find((item) => item.id === editingId);
    if (!current || current.title === title) return;
    void props.onRename(editingId, title)
      .catch((error) => props.notify(`重命名失败：${String(error)}`));
  }

  function move(id: string, direction: -1 | 1) {
    const index = flat.findIndex((item) => item.id === id);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= flat.length) return;
    // 只允许同类型内交换：分组展示顺序固定，跨组移动会打乱"人物卡→…→章节"的承诺
    if (flat[target].kind !== flat[index].kind) return;
    const next = [...flat];
    [next[index], next[target]] = [next[target], next[index]];
    void props.onReorder(next.map((item) => item.id))
      .catch((error) => props.notify(`排序失败：${String(error)}`));
  }

  function canMove(index: number, direction: -1 | 1): boolean {
    const target = index + direction;
    return target >= 0 && target < flat.length && flat[target].kind === flat[index].kind;
  }

  return <aside className="novel-shelf" aria-label="作品文档">
    <h2>作品目录</h2>
    {props.loading ? <p className="novel-muted">正在读取…</p> : props.documents.length === 0 ?
      <p className="novel-muted">先建立一张人物卡、设定或章节。</p> :
      <nav aria-label="章节与设定">{groups.map((group) =>
        <div className="novel-group" key={group.kind}><h3>{kindNames[group.kind]}</h3>
          {group.items.map((item) => {
            const flatIndex = flat.findIndex((entry) => entry.id === item.id);
            return <div className={props.selectedId === item.id ? "novel-item selected" : "novel-item"} key={item.id}>
              {editingId === item.id ?
                <input className="novel-rename" value={editingTitle} maxLength={80} autoFocus
                  aria-label="重命名文档"
                  onChange={(event) => setEditingTitle(event.target.value)}
                  onBlur={commitRename}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") commitRename();
                    if (event.key === "Escape") setEditingId(null);
                  }} /> :
                <button className="novel-item-main" type="button" disabled={props.busy}
                  aria-current={props.selectedId === item.id ? "page" : undefined}
                  onClick={() => { if (item.id !== props.selectedId && !props.guard()) return; props.onSelect(item.id); }}>
                  <span>{item.title}</span>
                  <small>{item.headVersionId ? "有正稿" : "未定稿"}</small>
                </button>}
              <span className="novel-item-actions">
                <button type="button" title="上移" aria-label={`上移 ${item.title}`} disabled={props.busy || !canMove(flatIndex, -1)}
                  onClick={() => move(item.id, -1)}>↑</button>
                <button type="button" title="下移" aria-label={`下移 ${item.title}`} disabled={props.busy || !canMove(flatIndex, 1)}
                  onClick={() => move(item.id, 1)}>↓</button>
                <button type="button" title="重命名" aria-label={`重命名 ${item.title}`} disabled={props.busy}
                  onClick={() => startRename(item)}>✎</button>
              </span>
            </div>;
          })}</div>)}</nav>}
    <form className="novel-new" onSubmit={(event) => {
      event.preventDefault();
      if (!props.guard()) return;
      void props.onCreate(newKind, newTitle).then((created) => { if (created) setNewTitle(""); });
    }}>
      <h3>新建文档</h3>
      <label htmlFor="novel-kind">类型</label>
      <select id="novel-kind" value={newKind} disabled={props.busy} onChange={(event) => setNewKind(event.target.value as NovelKind)}>
        {Object.keys(kindNames).map((kind) => <option value={kind} key={kind}>{kindNames[kind as NovelKind]}</option>)}
      </select>
      <label htmlFor="novel-title">标题</label>
      <input id="novel-title" type="text" maxLength={80} value={newTitle} disabled={props.busy} placeholder="例如：第一章"
        onChange={(event) => setNewTitle(event.target.value)} />
      <button className="novel-add" type="submit" disabled={props.busy || !newTitle.trim()}>建立文档</button>
    </form>
    <OpenQuestionsPanel questions={props.questions} busy={props.busy} onOpen={(id) => { if (!props.guard()) return; props.onOpenQuestion(id); }} />
  </aside>;
}
