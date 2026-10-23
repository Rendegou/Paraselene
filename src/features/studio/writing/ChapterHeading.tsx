import { useRef, useState } from "react";
import type { Notebook } from "./useNotebook";

/** Titles are read-only until an explicit rename; IME Enter/Escape belong to the composer. */
// 章节标题区：默认只读展示，点"重命名"进入显式编辑。
// 组件带 key=chapter.id 由父级挂载，切章即重建，本地 editing/title 状态不会跨章串扰。
export function ChapterHeading({ notebook }: { notebook: Notebook }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(notebook.chapter.title);
  const input = useRef<HTMLInputElement>(null);
  async function finish(save: boolean) {
    // 空标题不允许保存：保持编辑态并聚焦输入框，让用户补全。
    if (save && !title.trim()) {
      input.current?.focus();
      return;
    }
    // 原生模式走 IPC 重命名（失败则停留在编辑态，由 native 层记录错误）；浏览器预览直接改项目状态。
    if (save && notebook.native) {
      try { await notebook.native.renameChapter(title.trim()); }
      catch { return; }
    } else if (save) notebook.setProject((project) => ({
      ...project,
      chapters: project.chapters.map((chapter) => chapter.id === notebook.chapter.id
        ? { ...chapter, title: title.trim() } : chapter),
    }));
    setEditing(false);
    // 关闭编辑态后把焦点还给正文编辑器，恢复连续写作流。
    requestAnimationFrame(() => notebook.editor.current?.focus());
  }
  return (
    <header className="writing-chapter-heading">
      {editing ? (
        <form onSubmit={(event) => { event.preventDefault(); void finish(true); }}>
          <label className="sr-only" htmlFor="writing-chapter-title">章节标题</label>
          <input ref={input} id="writing-chapter-title" autoFocus value={title}
            maxLength={120} onChange={(event) => setTitle(event.target.value)}
            onKeyDown={(event) => {
              // IME 组字期间的 Enter/Escape 属于输入法，只阻止默认提交、不结束编辑。
              if (event.nativeEvent.isComposing || event.nativeEvent.keyCode === 229) {
                if (event.key === "Enter") event.preventDefault();
                return;
              }
              if (event.key === "Escape") {
                event.preventDefault(); event.stopPropagation(); finish(false);
              }
            }} />
          <div className="writing-rename-actions">
            <button type="submit">完成</button>
            <button type="button" onClick={() => finish(false)}>取消</button>
          </div>
        </form>
      ) : (
        <div className="writing-title-display">
          <h1>{notebook.chapter.title}</h1>
          <button type="button" onClick={() => { setTitle(notebook.chapter.title); setEditing(true); }}>
            重命名
          </button>
        </div>
      )}
      <div className="writing-chapter-meta">
        <span>{Array.from(notebook.chapter.body).length.toLocaleString()} 字</span>
      </div>
    </header>
  );
}
