# T03 桌宠好奇姿态 · 阶段证据

日期：2026-09-27。状态：**PARTIAL / T03 仍 IN_PROGRESS**。本记录只覆盖新增第四姿态及前端资源接线；没有声明 G01 原生视觉验收通过。

## REAL：实现

- `src/assets/companions/moon-curious.png`、`star-curious.png`、`cloud-curious.png`：内建 ImageGen 根据本项目已有原创待机图生成。三种额记和尾巴各自保留。最终提示词见 `docs/design-concepts/pet-curious-prompts-20260927.md`。
- `src/App.tsx`：指针进入或按钮聚焦时切至好奇姿态，1.1 秒回到待机；指针停留期间不启动 90 秒睡眠计时。点击取消好奇计时器并切到被点姿态，卡片开关完成后才恢复待机。
- `src/App.css`：好奇姿态只做一次 0.2 秒轻微转头，不再叠加整张图的悬停上浮；`prefers-reduced-motion` 全局规则仍生效。
- `docs/design-concepts/pet-curious-scale-check.html`：深浅桌面、112px 图像置于 120px 容器的对照页；浏览器未能打开，不能算视觉验收。

## REAL：命令与结果

1. `pnpm typecheck`（隔离副本 `D:\MyAgent\paraselene-work`）：退出码 **0**，`tsc --noEmit` 无报错。
2. `pnpm build`：第一次在受限沙箱内因链接的 `node_modules/.vite-temp` 写权限退出码 **1 / EPERM**；按文件权限升级后同一命令退出码 **0**，Vite 8.3.1 转换 **41 modules**，生成三张新好奇资源和前端 bundle。
3. `node C:\Users\HP\.agents\skills\impeccable\scripts/detect.mjs --json src/App.tsx src/App.css`：退出码 **0**，输出 `[]`。
4. `git diff --check -- src/App.tsx src/App.css`：退出码 **0**；Git 仅提示工作区 LF/CRLF 转换。
5. PowerShell 7 使用 `System.Drawing.Bitmap` 读取三张新图：退出码 **0**；均为 **1402 × 1122 / Format32bppArgb**，左上角 alpha **0**，中心 alpha **253–254**；文件大小分别 **788775、787109、790102 字节**。
6. 白名单同步到正式仓库 `D:\paraselene`：退出码 **0**，10 个文件逐一 SHA-256 一致。随后在正式仓库重跑 `pnpm typecheck`：退出码 **0**；`pnpm build`：退出码 **0**，仍转换 **41 modules**，三张新资源均进入 dist；`git diff --check`：退出码 **0**，仅有 LF/CRLF 提示。

## 尚未验收

- 内置浏览器拒绝访问 `file://` 本地预览页，返回 URL 安全策略拒绝；没有尝试绕开该策略。
- Windows 通知状态此前为 `BUSY=2`，原生桌宠会遵守安静规则隐藏。本轮未在正式 120 × 120 透明窗口检查三种姿态的可读性与事件时间线。
- T03 / G01 保持 PARTIAL；待用户桌面不处于 BUSY 时做原生视觉和交互验收。
