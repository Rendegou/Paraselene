import { useRef, useState } from "react";
import type { EditorApi } from "./threadTypes";
import type { ThreadStore } from "./useThreadStore";
/**
 * 内联槽位桥：把编辑器命令 API 与 Portal 宿主节点接进 React。
 * slotCallbacks 用 useRef 固化一次，避免每次渲染产生新引用触发 CodeMirror 重配。
 */
export function useInlineEditorBridge(threads: ThreadStore, clearSelection: () => void) {
  const editor = useRef<EditorApi | null>(null);
  const clear = useRef(clearSelection);
  clear.current = clearSelection;
  const [portalHost, setPortalHost] = useState<HTMLElement | null>(null);
  const slotCallbacks = useRef({
    mount: (node: HTMLElement | null, previous?: HTMLElement) =>
      setPortalHost(
        (current) => node ?? (current === previous ? null : current),
      ),
    open: (id: string) => { clear.current(); threads.setActiveId(id); },
  }).current;
  return { editor, portalHost, slotCallbacks };
}
