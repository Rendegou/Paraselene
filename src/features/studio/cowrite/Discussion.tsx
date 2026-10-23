import { TargetQuote } from "./TargetQuote";
import type { Studio } from "../useStudio";

/**
 * 共写讨论区：当前固定目标 + 历史讨论记录（作者请求及其引用快照）。
 * 目前为预览示例流程，"准备修改候选"生成的是本地 mock 候选，未调用模型。
 */
export function Discussion({ studio }: { studio: Studio }) {
  return (
    <>
      <TargetQuote studio={studio} target={studio.cowrite.target} clear />
      <div className="cowrite-discussion">
        <h3>{studio.cowrite.target ? "围绕这段继续讨论" : "本章创作笔记"}</h3>
        <p>记录改写意图、查阅设定，再在原段落审阅候选。正文始终由你决定。</p>
        <button
          type="button"
          className="text-link"
          disabled={!studio.cowrite.target}
          onClick={studio.propose}
        >
          准备修改候选（预览示例）
        </button>
      </div>
      {studio.cowrite.notes.map((note, index) => (
        <article key={note.id} className="cowrite-note">
          <header>
            <strong>讨论 {index + 1}</strong>
            <span>作者请求 · 尚未外发</span>
          </header>
          <TargetQuote studio={studio} target={note.target} />
          <p>{note.instruction}</p>
          {note.references.length > 0 && (
            <details>
              <summary>本次引用快照 · {note.references.length} 项</summary>
              {note.references.map((reference) => (
                <section key={reference.id}>
                  <h4>{reference.name}</h4>
                  <p>{reference.body}</p>
                  <button
                    type="button"
                    className="text-link"
                    onClick={() => studio.cowrite.inspectEntity(reference.id)}
                  >
                    查看当前设定
                  </button>
                </section>
              ))}
            </details>
          )}
        </article>
      ))}
    </>
  );
}
