import { useState } from "react";
import type { CowriteMode } from "./contracts";

/**
 * Scope the active view to a chapter; inspecting a setting does not navigate the manuscript.
 * 协作面板视图：视图状态按章节限定——查看设定详情（inspect）不触发正文导航，
 * 切章后模式回落到 chat。
 */
export function useCowriteView(chapterId: string) {
  const [visible, setVisible] = useState(true);
  const [view, setView] = useState<{
    chapterId: string;
    mode: CowriteMode;
    entityId: string | null;
  }>({ chapterId, mode: "chat", entityId: null });
  const current =
    // 切章即回落：current 永远属于当前章，旧章视图状态不再生效
    view.chapterId === chapterId
      ? view
      : { chapterId, mode: "chat" as const, entityId: null };
  /** 切换模式并确保面板可见。 */
  function setMode(mode: CowriteMode) {
    setVisible(true);
    setView({ ...current, mode });
  }
  /** 打开设定详情（inspect 模式），不导航正文。 */
  function inspectEntity(entityId: string) {
    setVisible(true);
    setView({ chapterId, mode: "inspect", entityId });
  }
  return {
    visible,
    setVisible,
    mode: current.mode,
    inspectedId: current.entityId,
    setMode,
    inspectEntity,
  };
}
