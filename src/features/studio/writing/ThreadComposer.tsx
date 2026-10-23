import type { Notebook } from "./useNotebook";
/**
 * 讨论串内的输入区：提交"记录要求"、管理本次引用的设定、发起候选准备。
 * 原生模式先签发外发预览，明确确认后才由服务端生成持久候选。
 */
export function ThreadComposer({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active;
  if (!thread) return null;
  // 由 thread.attached 反查实体，与项目目录同源。
  const references = notebook.project.entities.filter((entity) =>
    thread.attached.includes(entity.id),
  );
  return (
    <form
      className="thread-composer"
      onSubmit={(event) => {
        event.preventDefault();
        notebook.requests.submit();
      }}
    >
      {references.length > 0 && (
        <div className="thread-attached" aria-label="本次引用">
          {references.map((entity, index) => (
            <span key={entity.id}>
              <button
                type="button"
                className="writing-link"
                onClick={() => notebook.reference.show(entity.id)}
              >
                [{index + 1}] {entity.name}
              </button>
              <button
                type="button"
                aria-label={`移除${entity.name}引用`}
                onClick={() => notebook.requests.remove(entity.id)}
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}
      <label className="sr-only" htmlFor={`request-${thread.id}`}>
        写作要求
      </label>
      <textarea
        id={`request-${thread.id}`}
        rows={2}
        value={thread.draft}
        onChange={(event) =>
          notebook.threads.patch(thread.id, { draft: event.target.value })
        }
        placeholder="写下这段想调整的地方…"
      />
      <div className="thread-composer-actions">
        <span>{notebook.native ? "本机讨论 · 发送前先预览" : "会话记录 · 模型未连接"}</span>
        {/* 候选必须绑定选段锚点：全章讨论没有锚点，永远禁用的死按钮不展示。 */}
        {thread.target && (
          <button
            type="button"
            className="writing-link"
            // 锚点失效或原生模式下都不能在本地准备候选。
            disabled={!thread.anchor?.valid || (!!notebook.native && (!thread.draft.trim() || notebook.generation.state.phase !== "idle"))}
            onClick={notebook.candidates.propose}
          >
            {notebook.native ? "查看外发内容" : "准备候选"}
          </button>
        )}
        <button
          type="submit"
          className="writing-primary"
          disabled={!thread.draft.trim()}
        >
          记录要求
        </button>
      </div>
    </form>
  );
}
