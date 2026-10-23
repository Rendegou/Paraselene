# 幻月工程入口

适用于本仓库的人工与 Agent 协作者。用户明确要求优先；以下文档各自维护一种事实，技能和历史记录不另建产品范围或覆盖当前合同。

## 按任务读取

- 新功能、排期或接手续作：[产品目标](docs/product-scope.md) → [当前状态](docs/progress.md)。
- 架构、存储、编辑器、原生接线：[架构与数据合同](docs/engineering/architecture-contracts.md)。
- Flutter 界面或交互：[前端规范](docs/engineering/frontend-standards.md) → [设计系统](DESIGN.md)。
- 实施、验证与交接：[Agent 工作流](docs/engineering/agent-workflow.md)；较大任务按[任务合同模板](docs/engineering/task-template.md)落定范围和验收。
- 历史方案、日期化报告与 evidence 用于追溯；当前任务、授权和完成状态只看上述入口。[历史索引](docs/history/README.md)不作为执行队列。

## 环境与数据边界

- Windows only，只用 PowerShell 7 `pwsh`，禁止 Bash 和 `powershell.exe`。
- 工作仅在本独立目标仓库。原 `D:\MyAgent\paraselene-work` 只读；不 reset、清理或覆盖其他协作者成果。
- 不读取 Key、env、认证或作者 DB/作品，不发真实模型/付费请求。现有模型接缝仅官方 DeepSeek BYOK；真实外发仍须完整材料预览与明确确认，不能把历史报告当本次外发许可。
- Rust 是数据库、正式版本、采纳事务和正文 BLAKE3 的权威；保留 UTF-16/Unicode 标量合同，不归一化或翻译作者正文。
- 纯 Dart 包的生产代码不依赖 Flutter、IO 或数据库；测试/probe 可使用受控合成文件。UI locale、稿件语言与输出语言独立。

## 实施与交付

- 沿用构造注入、ChangeNotifier/Listenable 和现有 repository/native gateway；技能中的其他架构、依赖和长度阈值不自动引入。
- 按完整用户流程交付正常、失败、取消和适用边界状态。代码组织、60/400 有效行上限、主题、异步和控件要求由前端规范唯一维护；不复制成另一套清单。
- 已授权范围内的常规实现、合成测试和失败修正自主推进。产品范围或数据合同实质冲突时写明冲突；不以旧计划中的“未授权/暂停”代替当前用户指示。
- 文档入口检查：`pwsh -NoProfile -File scripts/check-docs.ps1`。前端静态检查：`pwsh -NoProfile -File scripts/check-frontend.ps1`；普通全量回归加 `-Test`。按改动风险选择验证，详见工作流。
- 当前提交/工作树、命令、退出码、断言与失败/未测项必须对应。mock 不代表 FFI/IME/Windows 通过；截图不代表 golden 通过。不得吞错、删功能/断言、忽略检查或自动改基线换绿。
- 更新同一份当前状态与证据，已完成的检查不因交接重复冒充新验证；开发通过、UI 验收和发布批准分别说明。
- 每个新任务立即设置 `YYMMDD | [幻月] 动作 + 具体目标` 标题；原因未知用“排查/定位”，确认缺陷后才用“修复”，目标实质变化时更新标题。
