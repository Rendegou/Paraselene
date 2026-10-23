import { useLayoutEffect, useRef } from "react";
import type { Surface } from "../types";

interface InputReturn {
  element: HTMLElement;
  start: number | null;
  end: number | null;
}
/**
 * 焦点还原：元素仍在文档直接聚焦；已卸载则按 id 找回（React 重建后还原）；
 * 都找不到才走 fallback。选区位置仅对输入类元素有效。
 */
function restoreInput(saved: InputReturn | null, fallback: () => void) {
  const element = saved?.element.isConnected ? saved.element
    : saved?.element.id ? document.getElementById(saved.element.id) : null;
  if (!element) { fallback(); return; }
  element.focus({ preventScroll: true });
  if ((element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement)
    && saved?.start != null && saved.end != null)
    element.setSelectionRange(saved.start, saved.end);
}

/**
 * Resource navigation shares a scroll container but must not reset the manuscript position.
 * 面导航的滚动/焦点记忆：设定等资源面与正文共用滚动容器，
 * 切回正文时恢复滚动位置与离开前的输入焦点，但显式跳转（jumpSequence 变化）优先、不重置位置。
 * 滚动位置经 persistence 回调上报（原生偏好落盘）。
 */
export function useSurfaceReturn(surface: Surface, chapterId: string, fallback: () => void, jumpSequence?: number,
  persistence?: { scrollTop: number; onScroll: (scrollTop: number) => void }) {
  const scroll = useRef<HTMLDivElement>(null);
  const focusRoot = useRef<HTMLDivElement>(null);
  const position = useRef(0);
  const previous = useRef(surface);
  const previousJump = useRef(jumpSequence);
  const input = useRef<InputReturn | null>(null);
  const latest = useRef({ surface, fallback });
  const latestPersistence = useRef(persistence);
  latestPersistence.current = persistence;
  latest.current = { surface, fallback };
  useLayoutEffect(() => {
    // 切章：清输入记忆，滚动位置取持久化值，下一帧落到容器（等布局稳定）
    input.current = null; position.current = latestPersistence.current?.scrollTop ?? 0;
    const frame = requestAnimationFrame(() => { if (scroll.current) scroll.current.scrollTop = position.current; });
    return () => cancelAnimationFrame(frame);
  }, [chapterId]);
  useLayoutEffect(() => {
    // 只在正文面记住最后输入焦点，供切回时还原
    const root = focusRoot.current;
    function remember(event: FocusEvent) {
      const element = event.target;
      if (latest.current.surface !== "manuscript" || !(element instanceof HTMLElement)) return;
      const field = element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement;
      if (!field && !element.isContentEditable) return;
      input.current = { element, start: field ? element.selectionStart : null, end: field ? element.selectionEnd : null };
    }
    root?.addEventListener("focusout", remember);
    return () => root?.removeEventListener("focusout", remember);
  }, []);
  useLayoutEffect(() => {
    // 显式引用跳转发生时让位（编辑器自行滚动定位），不恢复旧滚动位置
    const explicitJump = jumpSequence !== previousJump.current;
    previousJump.current = jumpSequence;
    if (surface === "manuscript" && previous.current !== surface && scroll.current && !explicitJump) {
      scroll.current.scrollTop = position.current;
      const frame = requestAnimationFrame(() => restoreInput(input.current, latest.current.fallback));
      previous.current = surface;
      return () => cancelAnimationFrame(frame);
    }
    previous.current = surface;
  }, [surface, jumpSequence]);
  return {
    ref: scroll,
    focusRoot,
    /** 滚动监听：只有正文面记录并上报位置（资源面的滚动不影响正文记忆）。 */
    onScroll: () => {
      if (surface === "manuscript" && scroll.current) {
        position.current = scroll.current.scrollTop;
        latestPersistence.current?.onScroll(position.current);
      }
    },
  };
}
