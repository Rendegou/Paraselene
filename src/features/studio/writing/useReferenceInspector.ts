import { useEffect, useRef, useState } from "react";
import type { ReferencePosition } from "./threadTypes";
import { canHandleMenuKey } from "../menuKeyboard";
/** 引用检查器状态：当前展示的设定 id 与卡片定位矩形。 */
interface Inspection {
  id: string;
  position: ReferencePosition;
}
/**
 * 记录引用卡打开前的焦点（优先线程面板的输入框，含选区位置），
 * 供关闭时还原；找不到可还原元素时返回 null。
 */
function referenceReturnFocus() {
  const focused = document.activeElement;
  const composer = focused
    ?.closest(".thread-panel")
    ?.querySelector(".thread-composer textarea");
  const element = composer instanceof HTMLTextAreaElement ? composer : focused;
  if (!(element instanceof HTMLElement)) return null;
  return {
    element,
    start:
      element instanceof HTMLTextAreaElement ? element.selectionStart : null,
    end: element instanceof HTMLTextAreaElement ? element.selectionEnd : null,
  };
}
/**
 * 引用检查器：show 打开卡片（定位优先用传入矩形，其次实体节点 rect，最后视口中央兜底）；
 * close 还原先前焦点与选区；Escape 关闭（IME 组字中不抢键）。
 */
export function useReferenceInspector() {
  const [current, setCurrent] = useState<Inspection | null>(null);
  const previousFocus = useRef<{
    element: HTMLElement;
    start: number | null;
    end: number | null;
  } | null>(null);
  /** 打开卡片：首次打开时记录焦点来源（连续打开不覆盖）。 */
  function show(id: string, position?: ReferencePosition) {
    if (!current) previousFocus.current = referenceReturnFocus();
    const source = Array.from(
      document.querySelectorAll<HTMLElement>("[data-entity]"),
    ).find((node) => node.dataset.entity === id);
    const bounds = position ??
      source?.getBoundingClientRect() ?? {
        left: innerWidth / 2,
        right: innerWidth / 2,
        top: 100,
        bottom: 120,
      };
    setCurrent({ id, position: bounds });
  }
  /** 关闭卡片；restore 时在下一帧还原焦点与选区（元素已被移除则放弃）。 */
  function close(restore = true) {
    setCurrent(null);
    if (!restore) return;
    requestAnimationFrame(() => {
      const saved = previousFocus.current;
      if (!saved?.element.isConnected) return;
      saved.element.focus({ preventScroll: true });
      if (
        saved.element instanceof HTMLTextAreaElement &&
        saved.start != null &&
        saved.end != null
      )
        saved.element.setSelectionRange(saved.start, saved.end);
    });
  }
  useEffect(() => {
    if (!current) return;
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && canHandleMenuKey(event)) {
        event.preventDefault();
        close();
      }
    };
    window.addEventListener("keydown", escape);
    return () => window.removeEventListener("keydown", escape);
  }, [current]);
  return { current, show, close };
}
