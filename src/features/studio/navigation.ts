import type { IconName } from "./Icon";
import type { Surface } from "./types";

/** 顶部导航条目表：Surface 标识 + 显示名 + 图标，顺序即界面展示顺序。 */
export const navigation: { id: Surface; name: string; icon: IconName }[] = [
  { id: "manuscript", name: "正文", icon: "book" },
  { id: "characters", name: "人物", icon: "people" },
  { id: "world", name: "世界观", icon: "world" },
  { id: "map", name: "地图", icon: "map" },
  { id: "framework", name: "项目框架", icon: "layers" },
];
