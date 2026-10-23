import { ParagraphEditor } from "./ParagraphEditor";
import { ChapterHeading } from "./ChapterHeading";
import type { Notebook } from "./useNotebook";
/**
 * 正稿视图：章节标题 + 段落编辑器 + 章末操作（撤销/重做/讨论本章）。
 * 编辑器通过 api ref 暴露命令式接口（undo/redo/locate），正文变更走 onChange 单向回流。
 */
export function NotebookManuscript({ notebook }: { notebook: Notebook }) {
  return (
    <article className="writing-manuscript">
      {/* key 绑定章节 id，切章时强制重建标题区，清掉上一章的输入状态。 */}
      <ChapterHeading key={notebook.chapter.id} notebook={notebook} />
      <ParagraphEditor
        chapterId={notebook.chapter.id}
        body={notebook.chapter.body}
        entities={notebook.project.entities}
        jump={notebook.jump}
        selection={notebook.selection}
        slot={notebook.slot}
        markers={notebook.markers}
        activeId={notebook.threads.activeId}
        slotCallbacks={notebook.slotCallbacks}
        api={notebook.editor}
        onChange={notebook.editBody}
        onMap={notebook.threads.remap}
        onSelection={notebook.setSelection}
        onReference={notebook.inspect}
        onDiscuss={notebook.discuss}
      />
      <footer className="writing-chapter-end">
        <span>本章结束</span>
        <div>
          <button type="button" onClick={() => notebook.editor.current?.undo()}>
            撤销
          </button>
          <button type="button" onClick={() => notebook.editor.current?.redo()}>
            重做
          </button>
          <button
            type="button"
            className="writing-link"
            onClick={() => notebook.threads.open(null)}
          >
            讨论本章
          </button>
        </div>
      </footer>
    </article>
  );
}
