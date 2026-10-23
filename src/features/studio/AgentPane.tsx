import { AgentComposer } from "./AgentComposer";
import { Discussion } from "./cowrite/Discussion";
import { Inspector } from "./cowrite/Inspector";
import { References } from "./cowrite/References";
import { Review } from "./cowrite/Review";
import { ReviewActions } from "./cowrite/ReviewActions";
import { Icon } from "./Icon";
import { targetLabel } from "./cowrite/model";
import type { Studio } from "./useStudio";

/**
 * 本章共写侧栏：按 mode 分发到讨论 / 审阅 / 资料 / 查看设定四个子视图。
 * inspect 模式由"查看设定"进入，不属于页签之一，故提供返回按钮而非高亮页签。
 */
export function AgentPane({ studio }: { studio: Studio }) {
  const { mode } = studio.cowrite;
  return (
    <aside className="studio-agent" aria-label="本章共写">
      <header className="cowrite-header">
        <div>
          <h2>
            {mode === "inspect"
              ? "查看设定"
              : mode === "review"
                ? "审阅修改"
                : "本章共写"}
          </h2>
          <p>
            {studio.chapter.title} · {targetLabel(studio.cowrite.target)}
          </p>
        </div>
        <button
          type="button"
          aria-label="收起共写区"
          onClick={() => studio.cowrite.setVisible(false)}
        >
          <Icon name="close" size={15} />
        </button>
      </header>
      <nav className="cowrite-tabs" aria-label="共写视图">
        {(
          [
            { id: "chat", label: "讨论" },
            { id: "review", label: "修改" },
            { id: "references", label: "资料" },
          ] as const
        ).map((item) => (
          <button
            type="button"
            key={item.id}
            aria-pressed={mode === item.id}
            onClick={() => studio.cowrite.setMode(item.id)}
          >
            {item.label}
            {/* 修改页签在有候选时显示角标，提示有待办审阅。 */}
            {item.id === "review" && studio.suggestion && <span>1</span>}
          </button>
        ))}
      </nav>
      <div className="cowrite-body">
        {mode === "inspect" ? (
          <Inspector studio={studio} />
        ) : mode === "review" ? (
          <Review studio={studio} />
        ) : mode === "references" ? (
          <References studio={studio} />
        ) : (
          <Discussion studio={studio} />
        )}
      </div>
      {mode === "review" && studio.suggestion && (
        <ReviewActions studio={studio} />
      )}
      {/* inspect（查看设定）与 review（审阅）用各自的底栏操作，不显示通用输入区。 */}
      {mode !== "inspect" && mode !== "review" && (
        <AgentComposer studio={studio} />
      )}
    </aside>
  );
}
