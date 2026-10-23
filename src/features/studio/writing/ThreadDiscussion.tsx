import type { Notebook } from "./useNotebook";
/**
 * 讨论串内的作者要求记录：按提交顺序展示每条要求，含原文快照与引用的设定依据。
 * 引用依据可点击跳转到资料浮层查看当前内容（可能已与引用时不同）。
 */
export function ThreadDiscussion({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active;
  if (!thread) return null;
  return (
    <div className="thread-discussion">
      {thread.requests.map((request, index) => (
        <article key={request.id}>
          <header>
            <strong>要求 {index + 1}</strong>
            <span>{request.status ? ({ running: "生成中", interrupted: "已中断 · 可重新预览", completed: "完整回复", cancelled: "已取消", failed: "生成失败" }[request.status] ?? request.status) : "作者记录"}</span>
          </header>
          <p>{request.text}</p>
          {request.output && <details><summary>模型回复快照</summary><p>{request.output}</p></details>}
          {request.error && <p className="thread-warning">{request.error}</p>}
          {request.quote && (
            <details>
              <summary>原文快照</summary>
              <blockquote>{request.quote.text}</blockquote>
            </details>
          )}
          {request.references.length > 0 && (
            <details>
              <summary>引用依据 · {request.references.length} 项</summary>
              {request.references.map((reference) => (
                <section key={reference.id}>
                  <h4>{reference.name}</h4>
                  <p>{reference.body}</p>
                  <button
                    type="button"
                    className="writing-link"
                    onClick={() => notebook.reference.show(reference.id)}
                  >
                    查看当前资料
                  </button>
                </section>
              ))}
            </details>
          )}
        </article>
      ))}
    </div>
  );
}
