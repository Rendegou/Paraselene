import { targetCurrent, targetLabel } from "./model";
import type { Studio } from "../useStudio";
import type { Target } from "./contracts";

/**
 * 讨论目标引用卡：展示被固定段落的快照，提供"定位原文"跳转与"改为全章讨论"。
 * 段落已变化时（current=false）禁用定位并提示快照过期——引用是历史快照，不回写正文。
 */
export function TargetQuote({
  studio,
  target,
  clear = false,
}: {
  studio: Studio;
  target: Target | null;
  clear?: boolean;
}) {
  const current = target ? targetCurrent(studio.chapter, target) : true;
  // 通过 jump 信号驱动编辑器滚动定位；sequence 取时间戳保证重复点击同一目标也能再次触发。
  function locate() {
    if (!target || !current) return;
    studio.setJump({ from: target.from, to: target.to, sequence: Date.now() });
  }
  return (
    <section className="cowrite-quote" aria-label="讨论目标">
      <div>
        <span>{targetLabel(target)}</span>
        {target && (
          <button
            type="button"
            className="text-link"
            disabled={!current}
            onClick={locate}
          >
            定位原文
          </button>
        )}
      </div>
      {target ? (
        <blockquote>{target.text}</blockquote>
      ) : (
        <p>围绕本章讨论。选中正文，可以把讨论固定到具体段落。</p>
      )}
      {!current && (
        <p className="cowrite-warning" role="status">
          原文已变化，这份引用保留为快照。请重新选段。
        </p>
      )}
      {clear && target && (
        <button
          type="button"
          className="text-link"
          onClick={studio.cowrite.clearTarget}
        >
          改为全章讨论
        </button>
      )}
    </section>
  );
}
