import { createPortal } from "react-dom";
import { ThreadPanel } from "./ThreadPanel";
import type { Notebook } from "./useNotebook";
/**
 * 判断当前活动讨论串是否需要以抽屉形式呈现（有目标段落但锚点失效，或没有目标）。
 * 供协作层与线程面板共用同一套"何时降级为抽屉"的判定。
 */
export function notebookNeedsDrawer(notebook: Notebook) {
  const thread = notebook.threads.active;
  return !!thread && (!thread.target || !thread.anchor?.valid);
}
/**
 * 协作面板宿主：满足条件时把 ThreadPanel 以 Portal 渲染到 portalHost
 * （章节正文区内的注入点），使线程 UI 与编辑器 DOM 结构解耦。
 * key 取 thread.id，切换线程时强制重建面板内部状态。
 */
export function NotebookCollaboration({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active;
  // 无活动线程、需要抽屉、非正稿视图或宿主已卸载（切章/切作品）时均不渲染。
  if (
    !thread ||
    notebookNeedsDrawer(notebook) ||
    notebook.surface !== "manuscript" ||
    !notebook.portalHost?.isConnected
  )
    return null;
  return createPortal(
    <ThreadPanel notebook={notebook} />,
    notebook.portalHost,
    thread.id,
  );
}
