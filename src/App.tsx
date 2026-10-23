import { lazy, Suspense } from "react";
import { currentSurface } from "./lib/ipc";
import StudioApp from "./features/studio/StudioApp";

// Archived surfaces load on demand, so the writing client does not load pet art or legacy CSS.
const LegacyApp = lazy(() => import("./LegacyApp"));

/**
 * 前端总入口组件：按原生层上报的窗口面（surface）决定渲染哪个应用。
 *
 * 契约：
 * - `currentSurface()` 在渲染前同步读取一次（同一窗口内面类型不变），为 "studio" 时直接渲染写作客户端；
 * - 其余历史面（桌宠 / 小说 / spike / 卡片）统一交给 `LegacyApp`，由其内部再分派；
 * - 非 studio 面包裹 `Suspense`，因为 `LegacyApp` 是懒加载 chunk，加载期间展示无样式占位文案。
 */
export default function App() {
  if (currentSurface() === "studio") return <StudioApp />;
  return (
    <Suspense fallback={<div role="status">正在打开本机工作区…</div>}>
      <LegacyApp />
    </Suspense>
  );
}
