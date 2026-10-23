import NotebookApp from "./writing/NotebookApp";
import NativeStudioApp from "./native/NativeStudioApp";
import { isNativeRuntime } from "../../lib/ipc";

/** The writing workspace is primary; ?design=paragraph isolates synthetic review scenes. */
// Studio 入口路由：优先挂载真实写作工作区；只有显式带上 ?design=paragraph 查询参数
// 时才单独渲染 NotebookApp 的合成审阅场景，供设计走查而不污染正常写作流程。
export default function StudioApp() {
  // 原生运行时（Tauri）且非设计走查模式下进入 NativeStudioApp；浏览器预览或设计模式则走 NotebookApp。
  const design =
    new URLSearchParams(location.search).get("design") === "paragraph";
  return isNativeRuntime() && !design ? <NativeStudioApp /> : <NotebookApp design={design} />;
}
