import type { Dispatch, SetStateAction } from "react";
import type { EntityKind, StudioProject } from "./types";

/** setProject 的别名：预览层的统一工程更新入口（React 状态 setter 形态）。 */
export type SetProject = Dispatch<SetStateAction<StudioProject>>;

/** 更新指定章节的正文（不可变更新，未命中 id 时保持原列表）。 */
export function editChapter(setProject: SetProject, id: string, body: string) {
  setProject((current) => ({
    ...current,
    chapters: current.chapters.map((item) =>
      item.id === id ? { ...item, body } : item,
    ),
  }));
}
/** 新建空白章节，标题按当前数量自动编号；返回新章节 id 供界面选中。 */
export function createChapter(setProject: SetProject): string {
  const id = crypto.randomUUID();
  setProject((current) => ({
    ...current,
    chapters: [
      ...current.chapters,
      { id, title: `第${current.chapters.length + 1}章 · 未命名`, body: "" },
    ],
  }));
  return id;
}
/** 新建设定条目：名称按类别给默认值；地点类额外分配地图坐标（横向错开摆放，避免重叠）。 */
export function createEntity(setProject: SetProject, kind: EntityKind): string {
  const id = crypto.randomUUID();
  const names = {
    character: "新人物",
    world: "新世界设定",
    location: "新地点",
  };
  setProject((current) => ({
    ...current,
    entities: [
      ...current.entities,
      {
        id,
        kind,
        name: names[kind],
        subtitle: "作者设定",
        body: "",
        related: [],
        sources: [],
        position:
          kind === "location"
            ? {
                x:
                  42 +
                  ((current.entities.filter((item) => item.kind === kind)
                    .length *
                    3) %
                    32),
                y: 42,
              }
            : undefined,
      },
    ],
  }));
  return id;
}
/**
 * 通过浏览器下载导出内容。
 * 文件名中的路径非法字符统一替换为下划线；1 秒后回收 ObjectURL，
 * 给浏览器留出发起下载的窗口期（过早 revoke 会导致下载失败）。
 */
export function downloadPreview(name: string, body: string, mime: string) {
  const url = URL.createObjectURL(new Blob([body], { type: mime }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name.replace(/[\\/:*?"<>|]/g, "_");
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
