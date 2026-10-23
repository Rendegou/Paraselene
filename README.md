# 幻月 Windows 写作工作台

Flutter 桌面展示层 + Rust 本地业务核心。生产编辑器、原位讨论、资料/出处和版本工作流已接入；默认工作台使用真实桥接的应用自有持久合成库。原 Tauri 工程保持只读，作者数据库尚未接管。

## 当前入口

- [产品目标与本阶段范围](docs/product-scope.md)：做什么、用户结果与非目标。
- [当前状态与任务队列](docs/progress.md)：最新验证、已知失败与下一动作。
- [Agent 工程入口](AGENTS.md)：常驻环境/数据边界与按任务阅读。
- [架构与数据合同](docs/engineering/architecture-contracts.md)：Rust 权威、Unicode、保存/版本/关闭及原生边界。
- [前端工程规范](docs/engineering/frontend-standards.md)与[设计系统](DESIGN.md)：怎么实现、允许哪些视觉/控件差异。
- [Agent 开发与验收流程](docs/engineering/agent-workflow.md)、[任务合同模板](docs/engineering/task-template.md)：一张任务如何实施、验证与交接。
- [历史索引](docs/history/README.md)：原迁移计划和进度原字节快照；历史报告不覆盖当前目标或状态。

当前应用验证仍有明确失败与未测项，具体以进度页为准。真实模型、物理 IME、DPI/多屏、屏幕阅读器、净机安装和发布各自验收，不能从本机编译或历史测试数字推断通过。

## 工程与检查

- `apps/desktop/`：Windows Flutter 应用；[桌面包说明](apps/desktop/README.md)。
- `packages/text_contract/`：纯 Dart Text/Locale 合同。
- `rust/application/`、`rust/bridge/`、`rust/core/`：应用编排、FRB 和固定核心快照。
- `tools/frontend_checks/`：AST/主题/ARB 检查；[工具说明](tools/frontend_checks/README.md)。
- `scripts/`：PowerShell 检查与构建入口；`docs/evidence/`：分次验证证据。

在仓库根目录使用 PowerShell 7：

```powershell
pwsh -NoProfile -File scripts/check-docs.ps1
pwsh -NoProfile -File scripts/check-frontend.ps1
pwsh -NoProfile -File scripts/check-frontend.ps1 -Test
```

文档检查核对当前入口的本地链接和历史快照完整性。前端默认入口核对全部自有生产 Dart 的结构/主题、ARB、官方本地化生成物、格式及分析；`-Test` 增加普通回归与隔离 FFI。应用、纯文本包和检查工具须预先按锁文件恢复依赖，原生检查须有正确的生产/test-support DLL；脚本参数可覆盖 SDK/DLL 路径。

golden、Release、原生矩阵和发布完成条件见工作流。现有脚本的成功只代表所选自动检查成功，不代表产品发布认证。验证日志先写 `build/`，确认后按任务归档必要证据。

## 文本、语言与模型

保留确切 Unicode 原文，Rust 维护正文 hash/事务权威。UI locale、稿件语言、输出语言独立；当前 UI 验证资源范围为 zh-Hans/en，其他语言和 RTL harness 不代表已发布翻译。模型仅官方 DeepSeek BYOK 接缝，发送前完整预览并明确确认；日常开发检查不读取真实凭据、不操作作者库或发模型请求。
