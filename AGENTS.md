# AGENTS.md — 「幻月」Windows 常驻陪伴 Agent

本文件是对在本仓库工作的所有 Agent（Codex / Kimi / Claude / Cursor / 人工协作者）的**强制约束**。

**指令优先级**：用户当次明确指示 > 本文件 > `docs/development-direction.md` > `docs/progress-checkpoint.md` > `幻月-Agent执行Goal.md` > 其他文档。冲突时以优先级高者为准，并在看板记录。

## 1. 项目定位

- 产品方向唯一来源：`windows-companion-agent-brief.md`（同一只常驻桌宠入口 → 旧想法花园 / 小说共写 / Python 5 分钟练习）。
- 本仓库是**独立新产品**，不绑定任何公司业务项目；公司资料默认不导入、不作为数据来源、不作为需求来源。
- 验收合同：`幻月-Agent执行Goal.md` 的 G01–G20；执行看板：`docs/progress-checkpoint.md`。

## 2. 环境硬约束

- Windows 11 开发机；Shell 一律用 **PowerShell 7（`pwsh`）**，禁止 Windows PowerShell 5.1。
- Node.js 22、Rust stable（**MSVC 工具链**为正式打包路径；MinGW 仅应急验证）。
- 本地开发**禁用 Docker**；需要的运行时全部原生进程。
- 一切路径、脚本、文档必须跨会话可复现：新机器按文档能重建环境。

## 3. 技术基线

- **Tauri 2 + Rust**：Cargo workspace；核心逻辑为纯 Rust crate（不依赖 Tauri，可独立 `cargo test`），`src-tauri` 只做窗口/托盘/IPC 转发。
- 前端 React + TypeScript + Vite；所有 IPC 调用收敛到**单一封装层**（参考 local-ai-chat-manager 的 `lib/ipc.ts` 模式），禁止组件内直接调 Tauri API。
- 本地存储 **SQLite（FTS5）**；记忆原文与索引只留本机。
- 模型：**DeepSeek 官方 API，用户自带 Key（BYOK）**；不使用网页版 ChatGPT 反代、Cookie 或登录态。
- Python 执行环境：首选 Pyodide（WASM，天然隔离），备选受限本地进程；由 T00 技术 spike 实测后用 ADR 锁定，未锁定前不得大面积开发依赖该选择的代码。
- 关键选型与版本用 `docs/adr/NNNN-主题.md` 锁定。

## 4. 密钥与隐私红线（不可协商）

- 禁止读取、复制、打印、提交任何凭据类内容：`.env`、API Key、SSH 私钥、浏览器 Cookie、各编码 Agent 的 `auth.json` / token 文件。
- 不采集屏幕、键盘、麦克风；不做全盘扫描；只索引**用户明确授权**的目录与导出文件。
- 原始会话/对话文件**只读**，永不修改。
- 日志、错误上报、测试快照不包含记忆正文；截图类证据必须脱敏。
- 分享角色包**不得**包含对话、小说正文、学习代码、文件路径、凭据；打包前自动检查（对应 G02）。
- **仓库卫生**：只提交代码与说明文档。语料（对话记录、导出包）、密钥、本地数据、记忆库永不提交；`.gitignore` 已覆盖 `secrets/`、`data/`、`*.zip`、`ChatGPT-*`；新增文件类型时先判断它该不该进仓库。

## 5. 事实标记

- 功能与数据一律标注 **REAL / SIMULATED / PLANNED**；禁止静默降级，禁止把"文档写了"说成"功能做了"。
- 性能数字（冷启动、驻留内存、CPU、电量）必须来自本机实测，并记录硬件与系统环境。
- 找不到证据时明确说"没找到 / 未验证"，不把模型猜测写成用户事实或项目事实。

## 6. 验证纪律

- 结论必须附：**实际命令、退出码、关键输出、证据路径**（`docs/evidence/Txx-YYYYMMDD.md`）。
- "文档或代码存在"不算通过；历史 PASS 不自动有效，关键验收必须在当前代码上复跑。
- 禁止无断言测试；目标测试失败与全量测试失败分开报告。

## 7. 代码与注释质量

- 注释写"为什么"：协议坑、逆向出的格式细节、权限边界、性能取舍；不复述代码在做什么。
- 从其他仓库移植的代码，文件头必须注明：**来源仓库、原路径、许可证、移植改动**。
- 公开 API（Rust 模块、TS 模块）写清契约：输入、输出、错误、副作用。

## 8. 复用纪律

- 首选复用 `docs/reuse-inventory.md` 中列出的**自有代码**（local-ai-chat-manager，MIT 许可）。
- 第三方/上游克隆项目（DeepTutor、prime-agent 等）**只作设计参考**，不直接拷贝代码；确需引用先确认许可证。
- 复用不是复制粘贴了事：移植后必须能通过新项目的测试，原项目的已知坑（见复用清单）必须一并处理或显式记录。

## 9. 多 Agent 接手流程

1. 开工前必读：`windows-companion-agent-brief.md` → `docs/development-direction.md` → `docs/progress-checkpoint.md`。
2. 认领任务：在看板填负责人（分支或会话标识）、状态改 IN_PROGRESS；同一任务只能有一个负责人。
3. 完成时：记录实际命令、退出码、关键结果、证据路径，才能把 `[ ]` 改 `[x]`、状态改 PASS。
4. `PARTIAL / FAIL / NOT_RUN / BLOCKED / IN_PROGRESS` 一律不勾选。

## 10. 允许停止的阻塞条件

以下情形允许暂停并在看板记录（说明需要用户做什么）：

1. 需要用户提供凭据、API Key 或数据授权；
2. 需要付费资源或外部服务持续不可用；
3. 需求矛盾或产品方向文档未覆盖的取舍；
4. 技术 spike 证明关键假设不成立（如 Pyodide 资源占用超标）；
5. 用户明确要求暂停。
