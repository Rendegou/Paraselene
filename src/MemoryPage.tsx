import { useEffect, useRef, useState } from "react";
import {
  correctMemory, deleteMemory, exportMemory, getMemoryDetail, getMemorySource, listMemories,
  type MemoryDetail, type MemoryRecord, type MemorySourceDetail, type Space,
} from "./lib/ipc";
import "./MemoryPage.css";

// 记忆空间与界面标签；与后端 Space 枚举一一对应，顺序即界面展示顺序。
const spaces: { id: Space; label: string }[] = [
  { id: "personal", label: "个人" },
  { id: "idea", label: "旧想法" },
  { id: "novel", label: "小说" },
  { id: "learning", label: "学习" },
];

/**
 * 记忆管理页：按空间浏览已保存的记忆，支持查看出处、纠正标题/摘要、移除与导出 JSON。
 *
 * Props 契约：
 * - `onEditStateChange`：编辑或删除确认进行中时上报 true，父组件据此锁定其他标签页，
 *   防止用户在表单未收尾时切走导致状态悬挂。
 *
 * 并发约定：`revision` ref 单调递增，每次发起读取前自增、清理时再自增；
 * 异步响应回来时只要发现 revision 已变就必须丢弃——切空间/切记忆后旧响应不得污染新视图。
 * 纠正与删除都携带 `updatedAt` 走乐观锁，后端版本不一致时报错并保留本地状态。
 */
export default function MemoryPage({ onEditStateChange }: { onEditStateChange: (active: boolean) => void }) {
  const [space, setSpace] = useState<Space>("personal");
  const [items, setItems] = useState<MemoryRecord[]>([]);
  const [selected, setSelected] = useState<MemoryDetail | null>(null);
  const [source, setSource] = useState<MemorySourceDetail | null>(null);
  const [title, setTitle] = useState("");
  const [summary, setSummary] = useState("");
  const [editing, setEditing] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [exportText, setExportText] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState("");
  const revision = useRef(0);

  // 编辑中或删除确认中时上报锁定状态；卸载时兜底复位，避免父组件锁被悬挂。
  useEffect(() => { onEditStateChange(editing || confirmDelete); }, [editing, confirmDelete, onEditStateChange]);
  useEffect(() => () => onEditStateChange(false), [onEditStateChange]);

  // 切空间即整页重置并重新拉列表；cleanup 里再自增 revision，连"快速来回切换"的竞态也一并失效。
  useEffect(() => {
    const current = ++revision.current;
    setSelected(null); setSource(null); setEditing(false); setConfirmDelete(false); setExportText("");
    setItems([]); setLoading(true); setNotice("");
    void listMemories(space).then((rows) => {
      if (revision.current === current) setItems(rows);
    }).catch((error) => {
      if (revision.current === current) setNotice(`读取记忆失败：${String(error)}`);
    }).finally(() => {
      if (revision.current === current) setLoading(false);
    });
    return () => { revision.current += 1; };
  }, [space]);

  // 打开单条详情；编辑/删除确认进行中禁止切换选中项，避免未保存的表单状态被换掉。
  async function open(record: MemoryRecord) {
    if (busy || editing || confirmDelete) return;
    const current = ++revision.current;
    setSelected(null); setSource(null); setExportText(""); setNotice(""); setLoading(true);
    try {
      const detail = await getMemoryDetail(space, record.id);
      if (revision.current === current) {
        setSelected(detail);
        setTitle(detail.memory.title);
        setSummary(detail.memory.summary ?? "");
      }
    } catch (error) {
      if (revision.current === current) setNotice(`读取记忆失败：${String(error)}`);
    } finally {
      if (revision.current === current) setLoading(false);
    }
  }

  async function showSource(sessionId: string, messageSeq: number | null) {
    if (!selected || busy) return;
    setBusy(true); setNotice(""); setSource(null);
    try { setSource(await getMemorySource(space, selected.memory.id, sessionId, messageSeq)); }
    catch (error) { setNotice(`读取出处失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 保存纠正：只改标题/摘要，出处与结构化内容保持原样；成功后同步列表行，避免回到旧值。
  async function save() {
    if (!selected || busy) return;
    if (!title.trim()) { setNotice("标题不能为空。请写好标题后再保存。"); return; }
    setBusy(true); setNotice("");
    try {
      const detail = await correctMemory(space, selected.memory.id, selected.memory.updatedAt, title, summary);
      setSelected(detail); setItems((rows) => rows.map((item) => item.id === detail.memory.id ? detail.memory : item));
      setTitle(detail.memory.title); setSummary(detail.memory.summary ?? "");
      setEditing(false); setExportText(""); setNotice("纠正已保存，原出处保留。");
    } catch (error) { setNotice(`无法保存：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 从记忆列表移除不等于删除原始导入会话；界面暂无恢复入口，所以删除需要二次确认。
  async function remove() {
    if (!selected || busy || !confirmDelete) return;
    setBusy(true); setNotice("");
    try {
      await deleteMemory(space, selected.memory.id, selected.memory.updatedAt);
      setItems((rows) => rows.filter((item) => item.id !== selected.memory.id));
      setSelected(null); setSource(null); setExportText(""); setConfirmDelete(false);
      setNotice("已从记忆列表移除；原始导入会话保留。");
    } catch (error) { setNotice(`无法移除：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 导出为 JSON 文本就地展示；聚焦即全选，方便直接复制带走，不落盘、不外发。
  async function makeExport() {
    if (!selected || busy) return;
    setBusy(true); setNotice("");
    try {
      setExportText(await exportMemory(space, selected.memory.id));
      setNotice("JSON 已生成。聚焦文本框后可全选复制到你选择的位置。");
    } catch (error) { setNotice(`生成导出失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  return <section className="page memory-page" aria-label="记忆管理">
    <div className="page-heading"><h2>我的记忆</h2><p>按空间查看、纠正和导出已保存的记忆。</p></div>
    <div className="memory-spaces" role="group" aria-label="选择记忆空间">
      {spaces.map((option) => <button key={option.id} type="button" className={space === option.id ? "selected" : ""}
        aria-pressed={space === option.id} disabled={busy || editing || confirmDelete}
        onClick={() => setSpace(option.id)}>{option.label}</button>)}
    </div>
    <div className="memory-list" aria-label="记忆列表">
      {loading ? <p className="memory-muted">正在读取…</p> : items.length === 0 ? <p className="memory-muted">这个空间还没有已保存的记忆。</p>
        : items.map((item) => <button key={item.id} type="button" className={selected?.memory.id === item.id ? "selected" : ""}
          disabled={busy || editing || confirmDelete} onClick={() => void open(item)}>
          <strong>{item.title}</strong><span>{item.summary || item.kind}</span>
        </button>)}
    </div>
    {selected && <article className="memory-detail">
      <h3>{selected.memory.title}</h3>
      <p className="memory-meta">{spaces.find((item) => item.id === space)?.label} · {selected.memory.kind}</p>
      {!editing ? <>
        <p className="memory-summary">{selected.memory.summary || "暂无摘要"}</p>
        {selected.memory.payload != null && <details className="memory-payload"><summary>查看结构化内容</summary>
          <pre>{JSON.stringify(selected.memory.payload, null, 2)}</pre></details>}
        <div className="memory-actions">
          <button className="secondary" type="button" disabled={busy} onClick={() => { setEditing(true); setConfirmDelete(false); setExportText(""); }}>纠正标题与摘要</button>
          <button className="secondary" type="button" disabled={busy} onClick={() => void makeExport()}>生成 JSON</button>
          <button className="text-action" type="button" disabled={busy} onClick={() => { setConfirmDelete(true); setExportText(""); }}>移除记忆</button>
        </div>
      </> : <form className="memory-edit" onSubmit={(event) => { event.preventDefault(); void save(); }}>
        <p>只修改这条记忆的标题和摘要；原始会话、出处及结构化内容保持不变。</p>
        <label htmlFor="memory-title">标题</label>
        <input id="memory-title" value={title} maxLength={200} disabled={busy} onChange={(event) => setTitle(event.target.value)} />
        <label htmlFor="memory-summary">摘要</label>
        <textarea id="memory-summary" value={summary} rows={4} disabled={busy} onChange={(event) => setSummary(event.target.value)} />
        <div className="memory-actions"><button className="primary" type="submit" disabled={busy}>{busy ? "保存中…" : "保存纠正"}</button>
          <button className="secondary" type="button" disabled={busy} onClick={() => {
            setTitle(selected.memory.title); setSummary(selected.memory.summary ?? ""); setEditing(false); setNotice("");
          }}>取消</button></div>
      </form>}
      {confirmDelete && <div className="memory-confirm" role="group" aria-label="确认移除记忆">
        <p>确认从记忆列表移除“{selected.memory.title}”？原始导入会话会保留，目前界面无法恢复这条记忆。</p>
        <div className="memory-actions"><button className="danger" type="button" disabled={busy} onClick={() => void remove()}>确认移除</button>
          <button className="secondary" type="button" disabled={busy} onClick={() => setConfirmDelete(false)}>保留记忆</button></div>
      </div>}
      <section className="memory-sources" aria-label="记忆出处"><h4>出处</h4>
        {selected.sources.length === 0 ? <p className="memory-muted">这条记忆没有绑定原会话。</p>
          : selected.sources.map((entry, index) => <div className="memory-source" key={`${entry.sessionId}:${entry.messageSeq ?? "all"}:${index}`}>
            <p>{entry.anchor || "整段会话引用"}</p><small>{entry.sessionId}{entry.messageSeq === null ? "" : ` · 第 ${entry.messageSeq + 1} 条`}</small>
            <button className="text-action" type="button" disabled={busy || editing} onClick={() => void showSource(entry.sessionId, entry.messageSeq)}>查看原文</button>
          </div>)}
        {source && <div className="memory-source-text"><strong>{source.sessionTitle || source.sessionId}</strong>
          <p>{source.text || source.anchor || "原消息已不在索引中；已保存的短引用仍可查看。"}</p></div>}
      </section>
      {exportText && <div className="memory-export"><label htmlFor="memory-export-json">导出 JSON</label>
        <textarea id="memory-export-json" readOnly rows={7} value={exportText} onFocus={(event) => event.target.select()} /></div>}
    </article>}
    {notice && <p className="notice" role="status">{notice}</p>}
  </section>;
}
