import { useEffect, useState } from "react";
import type { MutableRefObject } from "react";
import type { EditorView } from "@codemirror/view";
import type { Selection } from "../types";
/**
 * 选区浮层定位：跟随编辑器选区末尾的坐标，随滚动/resize 重新测量。
 * 可见性约束：选区滚出视口上下缘时隐藏；浮层位置夹在 16px 边距与视口内。
 */
export function useSelectionPosition(
  editor: MutableRefObject<EditorView | null>,
  selection: Selection | null,
) {
  const [position, setPosition] = useState<{
    left: number;
    top: number;
  } | null>(null);
  useEffect(() => {
    if (!selection) {
      setPosition(null);
      return;
    }
    const view = editor.current;
    if (!view) return;
    const measure = () =>
      view.requestMeasure({
        key: view,
        read: (current) => current.coordsAtPos(selection.to),
        write: (rect) =>
          setPosition(
            // 56/64 是顶栏高度带：选区被顶栏遮住或完全滚出视口时不显示浮层
            rect && rect.bottom > 56 && rect.top < innerHeight
              ? {
                  // 横向夹紧在 16px 边距内，纵向出现在选区下方 8px（贴近视口底时上收）
                  left: Math.max(16, Math.min(rect.left, innerWidth - 210)),
                  top: Math.max(
                    64,
                    Math.min(rect.bottom + 8, innerHeight - 80),
                  ),
                }
              : null,
          ),
      });
    measure();
    window.addEventListener("scroll", measure, true);
    window.addEventListener("resize", measure);
    return () => {
      window.removeEventListener("scroll", measure, true);
      window.removeEventListener("resize", measure);
    };
  }, [selection]);
  return selection ? position : null;
}
