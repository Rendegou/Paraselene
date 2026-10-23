import { useState } from "react";
import { locateSource } from "./previewModel";
import type { EditorJump, Selection, StudioProject, Surface } from "./types";

/** 游标状态集合：当前面、选中章节/设定、编辑器选区、跳转请求与提示条。 */
function useCursor() {
  const [surface, setSurface] = useState<Surface>("manuscript");
  const [chapterId, setChapterId] = useState("ch-3");
  const [entityId, setEntityId] = useState<string | null>("lin");
  const [selection, setSelection] = useState<Selection | null>(null);
  const [jump, setJump] = useState<EditorJump | null>(null);
  const [notice, setNotice] = useState("");
  return {
    surface,
    setSurface,
    chapterId,
    setChapterId,
    entityId,
    setEntityId,
    selection,
    setSelection,
    jump,
    setJump,
    notice,
    setNotice,
  };
}

/** 设定类别到其所属页面的映射：打开设定时切到对应的面。 */
const entitySurface: Record<string, Surface> = {
  character: "characters",
  world: "world",
  location: "map",
};

/**
 * 工作室导航：维护游标状态并派生当前章节/设定。
 * chapterId 失效时回退到第一章；引用跳转要求 locateSource 唯一命中，
 * 失败则只提示、不跳转（避免跳到编造位置）。
 */
export function useStudioNavigation(project: StudioProject) {
  const cursor = useCursor();
  const chapter =
    project.chapters.find((item) => item.id === cursor.chapterId) ??
    project.chapters[0];
  const entity =
    project.entities.find((item) => item.id === cursor.entityId) ?? null;
  function openChapter(id: string) {
    cursor.setChapterId(id);
    // 切章必须清掉旧选区与跳转标记：两者都只属于上一章的正文坐标
    cursor.setSelection(null);
    cursor.setJump(null);
    cursor.setSurface("manuscript");
  }
  function openEntity(id: string) {
    const target = project.entities.find((item) => item.id === id);
    if (!target) return;
    cursor.setEntityId(id);
    cursor.setSurface(entitySurface[target.kind]);
  }
  function openSource(id: string, quote: string) {
    const found = locateSource(project, id, quote);
    if (!found) {
      cursor.setNotice("出处原文已变化或存在多处匹配，请重新绑定引用。");
      return;
    }
    openChapter(id);
    // sequence 用时间戳：同一出处反复点击时让编辑器把它当作新请求，强制重新定位
    cursor.setJump({ from: found.from, to: found.to, sequence: Date.now() });
    cursor.setNotice("已定位到出处原文；点击“讨论这段”固定引用。");
  }
  return { ...cursor, chapter, entity, openChapter, openEntity, openSource };
}
