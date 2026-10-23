# Flutter 前端与 Agent 开发评估 · 2026-10-23

本文件记录审查发现和建议，不新增现行工程规则，不代表下列整改已经实施。现行规则仍以 `AGENTS.md`、`frontend-standards.md`、`DESIGN.md` 为准。

审查基点：`046530f3149e8e4abdb4342a818503119832c5ee`。当前 Flutter 迁移分支已推送到既有 GitHub 远端。原 Tauri 工程保持只读。审查前和自动检查后生产工作树均干净；本报告及附属证据在推送之后新增，尚未提交。

## 结论

目前最需要补齐的是：在仓库内明确下一版的产品结果，用具体交互合同约束实现，并让当前提交的验证结果决定完成状态。

已经具备的基础包括 Rust 数据权威、构造注入与 ChangeNotifier/Listenable、主题令牌、共享控件状态、Unicode 合同、AST 正反例、布局/对比度测试和本地化生成物一致性。应沿这些基础收敛规则，不因使用通用 Flutter 技能就替换状态管理、数据库或路由架构。

## 本次实际验证

执行 `pwsh -NoProfile -File scripts/check-frontend.ps1 -Test -ReportDirectory build/agent-audit-20261023-elevated`，退出 **1**。

- 普通回归：**673 通过、3 失败，共 676 项**。
- AST：141 个自有生产文件、0 违规；门禁工具：22 项通过。
- ARB：338 键 × 3 文件；官方生成物逐字节一致。
- 应用、文本包和门禁工具的 format/analyze 通过；纯文本合同 9 项、隔离 owned FFI 2 项通过。
- golden 和 Windows Release 构建本次未选择；物理 IME、DPI/多屏、屏幕阅读器、净机安装未运行。

首轮受限沙箱无法写 Flutter SDK `cache/lockfile`，保留于 `build/agent-audit-20261023/`；停止本次自有进程后在具备 SDK 缓存权限的环境重跑，才得到上述结果。环境失败不计为产品缺陷。

可移植摘要与三项失败片段见 [验证记录](../evidence/agent-frontend-assessment-20261023/verification.json) 和 [失败片段](../evidence/agent-frontend-assessment-20261023/failure-excerpts.txt)。完整原始日志保留在 `build/agent-audit-20261023-elevated/`，该目录不进入 Git。

## 1. 开发目标没有在当前仓库形成完整入口

**已证实事实：** `AGENTS.md:5` 和 `README.md:3` 指向仓库外的迁移计划。该文件在当前电脑上存在，但不会随本仓库的 clone/checkout 获取。`apps/desktop/README.md:3` 仍描述正文只读、云接口禁用；根 README 已说明生产编辑器接入。`pubspec.yaml` 的描述也仍停留在 M1 合成验收 runner。

**影响：** 新 Agent 或人工协作者需要依赖本机目录和交接信息，才能判断现有能力与下一步范围。实现计划、当前产品承诺和历史迁移状态容易混用。

**建议：** 在本仓库维护一份简短的当前产品范围，包含目标用户、下一版的完整用户流程、保留的数据不变量、本轮非目标和完成条件。仍有效的迁移合同应有仓库内版本；外部原计划保留为历史来源，不能继续作为唯一开工依据。同步根/子 README 的入口和运行描述。

产品优先级仍需要明确决策：下一版优先交付小说写作闭环，还是同时追求历史多模块等价迁移。建议先收敛写作闭环；这是本次建议，不冒充已批准范围，也不据此删除已有模块。

## 2. 当前状态与历史流水需要分开维护

**已证实事实：** `docs/progress.md` 同时包含当前表、连续追加的交接、旧授权/未授权说明和大量历史测试数字。文件已经说明历史记录不覆盖当前规则，但读者仍需跨多段核对。`.superpowers/sdd/progress.md` 仍保留旧基点和未结束的 M4 台账；它不是现行入口，却可能在全文搜索中被读到。

**影响：** Agent 容易继续旧任务、重复整改，或把某个历史 PASS 用于解释新源码。当前只有里程碑状态，缺少逐项功能与证据的稳定映射。

**建议：** 保留一个精简的当前表，按功能记录“已实现 / 当前提交已验证 / 发布待验”，并关联需求 ID、源码提交和证据；旧流水移入明确的历史区域。只维护一个当前负责人/任务状态入口。新增任务按相关范围读取历史，不要求每次重读所有证据。

## 3. 当前菜单合同测试已经与实现失配

**本次已复现：**

- `m2_workbench_test.dart`：`focus exits and wide mode changes readable manuscript width` 失败。
- `ui_completion_contract_test.dart`：选择器 1.0 和 2.0 文字缩放的两项测试失败。

`workbench_select.dart:50` 已生成 `WorkbenchCheckedMenuItem<T>`，其基类为 `PopupMenuItem<T>`（`workbench_controls.dart:148`）。但 `m2_workbench_test.dart:133` 与 `ui_completion_contract_test.dart:53` 仍查找旧的 `CheckedPopupMenuItem`。首项日志明确记录期望 2 个、实际 0 个；其余两项在取旧 finder 的 last 时出现 `Bad state: No element`。

**影响：** 历史的 676/676 PASS 不证明当前提交通过；静态门禁也不能覆盖交互测试与组件替换的同步问题。本次没有因此断言实际用户无法选择菜单。

**建议：** 第一张整改任务应修复这些合同测试，并核对禁用态的 `findsNothing` 是否也绑定了旧类型。按稳定菜单值、selected 语义、真实命中、键盘选择和焦点恢复验收，避免只机械替换类型名。提交级验证同时记录 HEAD、工作树是否有差异、SDK/字体指纹及所选检查，不能仅依赖日期和测试数量。

## 4. 前端规范已有条款，但跨页面落实仍有缺口

**源码事实：** 前端规范 F09 要求弹窗中的失败在当前弹窗显示原因并保留恢复入口。`MemoryDialog` 是 Dialog（`legacy/memory_dialog.dart:52`）；内部 `MemoryActions` 的异常路径只通过 `ScaffoldMessenger` 发通用 `saveError`（`legacy/memory_actions.dart:130`），未保存局部错误状态。

**边界：** 缺少弹窗内失败状态是源码事实；提示是否被具体窗口层级遮挡，本次没有原生 UI 复现，不能写成已复现故障。

**建议：** 在条目或父 Dialog 内保留稳定错误与可达恢复动作，以失败注入验证数据不变、弹窗保留和重试可用。复用现有控件合同与页面采集 harness，整理少量可直接运行的组件/状态样例：菜单、表单、任务弹窗、浏览弹窗、内嵌讨论及加载/空/失败/忙碌状态。让 Agent 在修改前看到现有样例和允许差异，减少逐页面重新猜测。

UI 任务同时给出符合现有设计系统的参考截图、允许调整的部分和目标状态；实现后检查实际渲染。OpenAI 的前端指导也强调明确设计原则、视觉参考和设计系统。[官方前端指导](https://developers.openai.com/blog/designing-delightful-frontends-with-gpt-5-4)

## 5. 长度与主题检查还不能证明架构边界正确

**源码事实：** `metrics.dart` 已检查有效行、主题、菜单等规则，尚无 import 依赖方向检查。`backup_dialog.dart:5` 导入 IO，`:23` 依赖具体 `RealWorkspaceRepository`，State 中同时协调文件选择、持久化屏障、写入、回读和恢复演练。视图职责与文件操作的边界仍可改进。

`discussion_registry.dart:58` 返回不可修改的列表，但 `DiscussionThread` 的 `snapshot/revision/generation/savedGeneration` 在 `discussion_thread.dart:92` 起仍公开可变，元素及嵌套 Map 没有形成深只读边界。

**影响与边界：** 这些接缝增加页面修改连带影响存储流程、或绕过通知/dirty 代数的风险。本次未发现调用者直接污染线程，也未复现丢稿。现行规范允许的 workspace/editor `part` 拆分本身不构成违规。

**建议：** 优先把备份协调抽到小型 coordinator/文件网关，封闭讨论状态的可变出口。沿用现有构造注入和 Rust 权威，只对受影响接缝整改。再将 presentation、native/generated、纯 Dart 包的允许依赖和单一写路径做成少量可测试规则；不要把“小文件数量”当作架构完成指标。

Flutter 官方把分层、repository、单向数据和可测试边界列为主要建议；`ChangeNotifier`/`Listenable` 属于可选择的实现方式。当前工程的质量问题不构成迁移 Riverpod/Drift 的依据。[官方架构建议](https://docs.flutter.dev/app-architecture/recommendations)

## 6. 日常检查与发布准入需要不同的完成条件

**已证实事实：** 仓库没有版本化的 `.github/workflows/` 文件；本次未核实外部 CI 或分支保护配置。`check-frontend.ps1` 的 golden、Release 是可选项，物理项是单独的 NOT_RUN；所选项决定退出码，脚本如实报告覆盖范围。

`m2_golden_test.dart:15` 的比较环境仍是固定 1280×900/100% 的中/RTL 两张图。辅助页面已有 11 页 × 3 组合的采集，但 `ui_completion_capture_test.dart:154` 是写 PNG，没有进行 golden 比较。历史记录明确保留了 golden FAIL/SKIPPED；这不是本次重新运行 golden 的结果。

**建议：** 保留轻量开发检查，同时明确 UI 验收与发布验收的入口。先解决少量高风险流程的视觉基线，再扩展必要组合；基线变更附视觉差异与批准记录。发布批准还应关联 IME、DPI/多屏、窗口关闭恢复、读屏和净机证据，不能用 widget 测试替代。不要要求每次小改动都跑物理全矩阵。

编辑器计划已有 20 万字 P95 预算，也如实保留极长单行冷跳等限制。后续需要绑定设备、profile、数据样本、当前提交和可接受退化，不能把旧 benchmark 数字直接继承为当前性能结论。

Flutter 官方区分 widget 与 integration 测试，并说明 `integration_test` 无法直接操作系统原生 UI；Windows 系统对话框与输入法应保留独立验证路径。[官方测试说明](https://docs.flutter.dev/testing/overview)

## 7. Agent 工作流应收敛到项目合同和可执行检查

当前仓库 `AGENTS.md` 已较短，且前端规范已经规定技能按需使用。环境中的通用 Flutter 技能却还包含 Riverpod、Drift、不同长度阈值等强约束；这些与项目既有架构并不全部相符。不能把安装技能的数量当作项目规范成熟度。

建议只提炼几种项目工作流：功能实施、UI 验收、文档同步、发布检查。它们复用当前脚本和设计合同，用简短触发条件按任务加载。稳定的数据/环境边界留在 AGENTS；具体步骤交给脚本；单次目标写在任务合同。OpenAI 官方资料也建议让工作流随仓库维护，并压缩过宽技能描述和过时常驻指令。[工作流示例](https://developers.openai.com/blog/skills-agents-sdk)、[指令维护建议](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)

对中等以上前端任务，开工前固定以下信息即可：

- 要实现的用户结果及本次非目标。
- 涉及页面、共用组件、允许修改的代码边界。
- 正常、空、失败、忙碌、取消、迟到响应等适用状态。
- 窄窗、文字缩放、键盘/焦点、本地化等相关交互合同。
- 证明成功的真实操作、断言和命令；哪些项目仍需系统/人工验收。
- 交付提交、实际结果、剩余问题和下一动作。

实现按完整用户流程切片，避免把“写页面”“补测试”“补错误态”“补文档”长期分成互不相连的任务。独立复核应验证验收条款与失败路径，而非只统计代码行和测试数。并行工作时才为文件与 Flutter SDK/原生构建标明唯一所有者。

## 建议的整改顺序

1. 修复本次三项菜单测试失配，确认当前提交有可信的行为检查结果。
2. 收敛仓库内产品范围与当前状态，修正文档陈旧入口，为下一版写出明确验收条件。
3. 用一个小流程落实任务合同、共享状态样例和独立复核；可从菜单选择合同、记忆弹窗失败恢复开始。
4. 针对备份协调/讨论状态等明确接缝整改，再补依赖边界检查、提交级证据和 CI。
5. 单独处理已知视觉基线与发布验收欠项，形成可批准的发布状态。

下一步的成功标准应是：换一个 Agent、换一个干净 checkout，能够从仓库内定位同一目标、复用同一组件合同、运行同一验证，并得到与当前提交一致的完成结论。

## 一张具体任务合同的示例（建议，尚未实施）

任务：修复菜单选择合同与实现失配。

目标：宽稿切换与通用选择器在中英、适用窄窗及 1×/2× 字号下，通过真实菜单操作改变正确值，关闭后焦点回到触发器，作者正文逐字不变。

范围：现有菜单控件、相关调用点与测试；沿用当前主题/状态管理/数据权威，不改业务范围或作者数据。

验收：菜单值与 selected 语义正确；Enter 打开和选择、Escape 取消和归还焦点；禁用态不能打开；点击真实命中区域；失败的三项回归恢复，受影响共享合同通过。全量检查在该切片完成后运行一次；有新失败或新改动时再按风险复跑。

交付：源码提交 SHA、工作树差异状态、所选命令和退出码、测试数量、实际失败/未测项、证据位置；现有 golden 与物理未测项继续显式列出。
