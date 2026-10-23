import { useEffect, useRef, useState } from "react";
import { Icon } from "../Icon";
import type { Notebook } from "./useNotebook";
import { shortcutAction } from "./shortcutAction";

/** Chapter-local search and native shortcuts do not intercept IME composition or editor undo. */
// 本章内查找 + 全局快捷键（查找/保存）。
// 判定集中在 shortcutAction，IME 组字（isComposing/keyCode 229）期间一律不拦截，输入法体验不被破坏。
export function ChapterSearch({ notebook }: { notebook: Notebook }) {
  const [open, setOpen] = useState(false), [query, setQuery] = useState(""), [result, setResult] = useState("");
  const input = useRef<HTMLInputElement>(null), cursor = useRef(-1);
  // 监听器只注册一次，用 ref 取最新 notebook，避免闭包捕获旧章节。
  const latest = useRef(notebook); latest.current = notebook;
  // 换查询词或切章时重置查找游标与结果提示。
  useEffect(() => { cursor.current = -1; setResult(""); }, [query, notebook.chapter.id]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      const action = shortcutAction(event, !!latest.current.native);
      if (action === null) return;
      event.preventDefault();
      if (action === "find") setOpen(true);
      if (action === "save") void latest.current.native?.flush().catch(() => undefined);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  useEffect(() => { if (open) input.current?.focus(); }, [open]);
  function find() {
    if (!query) return;
    const body = notebook.chapter.body;
    // 从上次命中之后继续找；到章末则回绕到开头，形成"下一处"的循环语义。
    let at = body.indexOf(query, cursor.current + 1);
    if (at < 0) at = body.indexOf(query);
    if (at < 0) { setResult("本章没有匹配文字。"); return; }
    cursor.current = at;
    notebook.editor.current?.locate(at, at + query.length);
    // 位置提示按 Unicode 码位计数（Array.from），与存储层字符口径一致。
    setResult(`已定位第 ${Array.from(body.slice(0, at)).length + 1} 字`);
  }
  return <div className="writing-menu">
    <button type="button" className="writing-find" aria-label="查找正文" onClick={() => setOpen((value) => !value)} aria-expanded={open}>
      <Icon name="search" size={16} />
      <span>查找正文</span>
    </button>
    {open && <form className="writing-menu-popup" onSubmit={(event) => { event.preventDefault(); find(); }}
      onKeyDown={(event) => {
        if (event.key === "Escape" && !event.nativeEvent.isComposing && event.nativeEvent.keyCode !== 229) {
          event.preventDefault(); event.stopPropagation(); setOpen(false); notebook.editor.current?.focus();
        }
      }}>
      <label htmlFor="chapter-find-input">查找当前章</label>
      <input id="chapter-find-input" ref={input} value={query} onChange={(event) => setQuery(event.target.value)} />
      <button type="submit">下一处</button><p role="status">{result}</p>
    </form>}
  </div>;
}
