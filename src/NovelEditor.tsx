// 薄适配入口：窗口路由仍按旧路径加载本文件；实现已迁入 features/novel。
// 保留本文件是为了让 App.tsx 的路由在 T05B 窗口迁移前不需要改动。

import NovelWorkbench from "./features/novel/NovelWorkbench";

/**
 * 小说编辑窗口的薄适配入口。
 *
 * 仅透传到 `features/novel/NovelWorkbench`；窗口路由仍按旧路径加载本文件，
 * 保留它是为让 App 层路由在窗口迁移完成前无需改动。无自身状态与副作用。
 */
export default function NovelEditor() {
  return <NovelWorkbench />;
}
