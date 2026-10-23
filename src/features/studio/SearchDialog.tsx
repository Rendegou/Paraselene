import { useEffect, useRef, useState } from "react";
import type { StudioProject } from "./model";
import { StudioIcon } from "./StudioIcon";

/**
 * 项目内搜索对话框（Ctrl K 唤起）：对章节与作品资料做大小写不敏感的标题子串匹配。
 * 点击结果回调 select(id, kind) 并关闭；Esc 或点击遮罩通过 onCancel/onClose 关闭。
 */
export function SearchDialog({ project, close, select }: { project: StudioProject; close: () => void; select: (id: string, kind: string) => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [query, setQuery] = useState("");
  // knowledge 条目本身没有 kind 字段，展开章节时补上 "chapter" 以区分结果类型。
  const entries = [...project.chapters.map((chapter) => ({ ...chapter, kind: "chapter" })), ...project.knowledge];
  const results = entries.filter((item) => item.title.toLowerCase().includes(query.toLowerCase()));
  // 挂载后立即以模态形式打开原生 <dialog>；关闭事件统一走 close，由父组件决定是否卸载。
  useEffect(() => { dialog.current?.showModal(); }, []);
  return <dialog ref={dialog} className="studio-search-dialog" onCancel={close} onClose={close}>
    <div className="search-dialog-heading"><StudioIcon name="search" /><label className="sr-only" htmlFor="project-search">搜索章节、人物和世界资料</label><input id="project-search" autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="搜索章节、人物和世界资料…" /><button type="button" className="icon-button" aria-label="关闭搜索" onClick={close}><StudioIcon name="close" size={18} /></button></div>
    <div className="search-dialog-results">{results.map((item) => <button key={item.id} type="button" onClick={() => { select(item.id, item.kind); close(); }}><StudioIcon name={item.kind === "chapter" ? "file" : "link"} size={17} /><span>{item.title}</span><small>{item.kind === "chapter" ? "正文" : "作品资料"}</small></button>)}{results.length === 0 && <p>没有匹配的内容。试试人物名或章节标题。</p>}</div>
    <div className="search-dialog-footer">搜索体验作品中的资料 <span>Esc 关闭</span></div>
  </dialog>;
}
