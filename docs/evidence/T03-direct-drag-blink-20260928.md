# T03 桌宠本体拖动与待机动效 · 阶段证据

日期：2026-09-28。状态：**PARTIAL / T03 仍 IN_PROGRESS**。全部改动只在 `D:\MyAgent\paraselene-work`，正式仓库未同步。

## REAL：实现

- 移除宠物顶部抓手；主图按钮在鼠标按下后移动至少 6 屏幕像素时调用 Tauri `startDragging()`，短点击仍打开卡片，拖动后不触发卡片点击。键盘聚焦与点击保留。
- 以内建 ImageGen 对现有月、星、云原创待机图各生成一张闭眼帧，保留透明背景、轮廓与三种额记/尾饰；新增 `moon-blink.png`、`star-blink.png`、`cloud-blink.png`。待机帧用 CSS 定时切换眨眼，并加入小幅呼吸；系统减少动态效果规则覆盖动画。
- 采用实时 PNG 帧切换而非 GIF，便于姿态切换和减少动态效果生效。只新增所需帧，未替换既有四姿态素材。

## REAL：命令与结果

1. `pnpm typecheck`：退出码 **0**，`tsc --noEmit` 无报错。
2. `node 'D:\paraselene\node_modules\.pnpm\vite@8.3.1\node_modules\vite\bin\vite.js' build --configLoader runner`：退出码 **0**，Vite 8.3.1 转换 **46 modules**，三张 blink 图均进入 `dist/assets`。
3. `git diff --check -- src/App.tsx src/App.css`：退出码 **0**，仅 LF/CRLF 提示。
4. PowerShell 7 的 `System.Drawing.Bitmap` 检查：退出码 **0**；三张新图均为 **1402 × 1122**，左上角 alpha **0**。生成后逐张查看，闭眼、额记与尾饰可辨。

## 尚未验收

- 原生 120 × 120 透明窗口中的拖动、短点击互斥和动画观感需要手动操作确认；自动化构建不证明 Windows 原生拖动成功。
- T03/G01 的托盘与专注状态切换仍待原生验收。
