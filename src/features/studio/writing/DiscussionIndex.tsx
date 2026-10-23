import type { Notebook } from "./useNotebook";

/** Every stored discussion remains reachable, including invalidated quotations. */
export function DiscussionIndex({ notebook }: { notebook: Notebook }) {
  const threads = notebook.threads.forChapter;
  if (!threads.length) return null;
  return (
    <details className="writing-discussion-index" onKeyDown={(event) => {
      if (event.key !== "Escape" || event.nativeEvent.isComposing) return;
      event.preventDefault();
      event.stopPropagation();
      event.currentTarget.open = false;
      event.currentTarget.querySelector("summary")?.focus();
    }} onBlur={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget as Node | null)) event.currentTarget.open = false;
    }}>
      <summary aria-label={`已存讨论 ${threads.length} 个`}>讨论记录 · {threads.length}</summary>
      <nav aria-label="本章已存讨论">
        {threads.map((thread) => (
          <button type="button" key={thread.id} aria-pressed={thread.id === notebook.threads.activeId}
            onClick={(event) => {
              notebook.reference.close(false);
              notebook.setSelection(null);
              notebook.threads.setActiveId(thread.id);
              event.currentTarget.closest("details")!.open = false;
            }}>
            <span>{thread.target?.text.slice(0, 32) || "全章讨论"}</span>
            <small>{thread.anchor && !thread.anchor.valid ? "原句已变化 · 历史仍保留" : "可继续讨论"}{thread.draft ? " · 有未发草稿" : ""}</small>
          </button>
        ))}
      </nav>
    </details>
  );
}
