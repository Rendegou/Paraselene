# AGENTS.md — 幻月工程入口

适用于 Codex、KIMI、Claude、Cursor 与人工协作者。优先级：用户明确指示 > 本文件 > 当前方向 > 当前看板 > Goal > 专项文档。冲突写入看板，不自行改产品范围。

## 开工必读

1. [README](README.md) → [当前方向](docs/development-direction.md) → [进度看板](docs/progress-checkpoint.md)。
2. [项目地图](docs/engineering/project-map.md) → [代码规范](docs/engineering/code-standards.md)。
3. 小说任务再读 [模块入口](docs/novel/README.md)；产品与总验收见 [brief](windows-companion-agent-brief.md)、[Goal](幻月-Agent执行Goal.md)。

## 当前任务与命名

- 2026-10-12 起只推进小说客户端：前端体验 → 真实内核接线 → 引用/Agent 深入。T05A–T05H 旧计划保留为历史与边界参考，不按全套并行展开；桌宠、学习、主动提醒退出当前排期。先看板认领，再改代码；同一任务一个负责人。
- 每个新工程会话立即设置标题：`YYMMDD | [模块] 动作 + 具体对象/问题`，中文优先，约 10–28 个汉字。
- 原因未知用“排查/定位/分析”；确认缺陷后用“修复”；新能力用“实现/增加/支持”；结构调整用“重构/拆分/迁移”。诊断明确后细化标题，禁用“继续开发/代码优化/修复问题”等空泛名称。
- 工作副本为 `D:\MyAgent\paraselene-work`；未经用户授权不向 `D:\paraselene` 同步。保留已有修改，不 reset、清库或覆盖其他 Agent 成果。

## 环境与边界

- Windows only；只用 PowerShell 7 `pwsh`，禁止 `powershell.exe` 与 Bash。原生 Windows 路径；本地不使用 Docker。
- Node.js 22；Rust `stable-x86_64-pc-windows-gnu`。构建前：`$env:PATH='C:\tools\paraselene-build\mingw64\bin;' + $env:PATH`。见 [ADR-0001](docs/adr/0001-windows-gnu-toolchain.md)。
- Tauri 2 只承载窗口/托盘/权限/IPC；领域逻辑放纯 Rust crates，核心不依赖 Tauri；lib crate-type 保持 rlib。
- React/TS 组件只通过 `src/lib/ipc.ts` 访问原生能力，不直接导入 Tauri API。SQLite/FTS5 为本机权威存储。
- 模型只走 DeepSeek 官方 API BYOK；Key 在系统安全存储；不使用网页登录态、Cookie 或反代。
- Python 仅在已验证的隔离 Worker 运行；不得放宽全局 CSP/IPC 权限。Pyodide 不是天然安全沙箱，见 [ADR-0002](docs/adr/0002-python-sandbox-pyodide.md)。

## 隐私、复用与数据

- 不读取、复制、打印或提交 `.env`、Key、SSH 私钥、Cookie、Agent auth/token 文件；原始导出与会话只读。
- 不采集屏幕/键盘/麦克风，不全盘扫描。只处理用户授权目录/文件；公司资料默认不导入，项目不绑定公司业务。
- 日志/错误/测试快照无私人正文；证据截图用合成或脱敏材料。语料、数据库、导出包不提交。
- 角色分享包不得带脚本、凭据、对话、小说正文、学习代码或私人路径。四空间隔离保持有效。
- 小说试写、AI 摘要/事实候选不自动成为正史；修改须绑定版本并经用户采纳；外发预览与一次性确认不可绕过。
- 首选 [复用清单](docs/reuse-inventory.md) 的自有 MIT 代码。第三方只作设计参考；拷贝前核对许可证，记录来源、原路径与改动。

## 质量与交接

- 目录职责、依赖方向、函数长度和复杂度按 [代码规范](docs/engineering/code-standards.md)；不得继续扩大巨型组件/模块。
- 公开 API 说明契约；注释解释原因、边界与取舍。异常、取消、过期版本必须显式处理。
- REAL / SIMULATED / PLANNED 分开。代码存在不等于验收；性能数字必须实测，历史 PASS 不自动继承。
- 每阶段记录实际命令、退出码、关键结果、限制与证据到 `docs/evidence/`，再更新看板；无断言测试不算证据。
- 结束前写明修改文件、完成项、失败/未测项和下一动作。只在凭据/授权缺失、付费依赖、需求实质矛盾、关键 spike 失败或用户要求暂停时停；普通实现选择自行推进。
