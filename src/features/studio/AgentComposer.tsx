import { targetLabel } from "./cowrite/model";
import type { Studio } from "./useStudio";

/**
 * 共写输入区（composer）：提交"记录请求"形成一条讨论记录。
 * 附带展示本次引用的设定（可跳转查看、可移除）；draft 纯空白时禁止提交。
 */
export function AgentComposer({ studio }: { studio: Studio }) {
  // 由 attached 里的实体 id 反查完整实体，保证引用区与目录数据同源。
  const references = studio.project.entities.filter((entity) =>
    studio.cowrite.attached.includes(entity.id),
  );
  return (
    <form
      className="cowrite-composer"
      onSubmit={(event) => {
        event.preventDefault();
        studio.cowrite.submit();
      }}
    >
      <label htmlFor="studio-instruction">
        继续讨论 · {targetLabel(studio.cowrite.target)}
      </label>
      {references.length > 0 && (
        <div className="cowrite-attached" aria-label="本次引用">
          {references.map((entity) => (
            <span key={entity.id}>
              <button
                type="button"
                className="text-link"
                onClick={() => studio.cowrite.inspectEntity(entity.id)}
              >
                {entity.name}
              </button>
              <button
                type="button"
                className="cowrite-reference-remove"
                aria-label={`移除${entity.name}引用`}
                onClick={() => studio.cowrite.removeReference(entity.id)}
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}
      <textarea
        id="studio-instruction"
        rows={3}
        value={studio.cowrite.draft}
        onChange={(event) => studio.cowrite.setDraft(event.target.value)}
        placeholder="例如：更克制一些，但别透露钥匙来源…"
      />
      <div>
        <small>
          模型未连接
          <span className="cowrite-session-hint"> · 请求只在本次会话记录</span>
        </small>
        <button
          className="cowrite-primary"
          type="submit"
          disabled={!studio.cowrite.draft.trim()}
        >
          记录请求
        </button>
      </div>
    </form>
  );
}
