import { ReferenceCard } from "./ReferenceCard";
import type { Notebook } from "./useNotebook";
/**
 * 引用查看的浮层：跟随被引用段落的屏幕位置弹出 ReferenceCard。
 * 位置做视口夹取，保证浮层不超出窗口；移动端有活动线程时让位（避免双层遮挡）。
 */
export function ReferenceOverlay({ notebook }: { notebook: Notebook }) {
  const inspection = notebook.reference.current;
  if (!inspection || (notebook.layout.mobile && notebook.threads.active))
    return null;
  // 最大 380x520，且不超过视口高 72% 并留出 88px 顶部空间；位置在锚点右下方展开。
  const width = Math.min(380, innerWidth - 32);
  const height = Math.min(520, innerHeight * 0.72, innerHeight - 88);
  // 左右/上下均夹取到 [16, 视口-尺寸-16]、[72, ...]，top 最小 72 为顶栏预留高度。
  const left = Math.max(
    16,
    Math.min(inspection.position.right + 14, innerWidth - width - 16),
  );
  const top = Math.max(
    72,
    Math.min(inspection.position.bottom + 8, innerHeight - height - 16),
  );
  return (
    <div
      className="reference-overlay"
      style={{ left, top, width, maxHeight: height }}
    >
      <ReferenceCard notebook={notebook} />
    </div>
  );
}
