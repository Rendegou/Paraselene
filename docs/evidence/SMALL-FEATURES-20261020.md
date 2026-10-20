# 剩余小功能迁移与验证（2026-10-20）

状态：小功能已迁移并完成本机合成验证；完整原生系统矩阵、真实模型、作者库接管与发布仍未执行。原 `paraselene-work` 未改动，未读取作者数据/凭据，未发起模型请求，未重写 golden。

## 目的

对照原 React 原生写作壳与遗留想法入口，补齐 2026-10-20 进度核对中确认仍缺的小功能；不改变 Rust 权威、schema、作者数据合同，不新增模型/网络能力。

## 本次迁移的功能

| 原功能 | Flutter 实现 | 关键边界 |
| --- | --- | --- |
| 章内查找（Ctrl+F / 工具栏，循环“下一处”） | `lib/workspace/presentation/chapter_find.dart`，`ManuscriptTools` 入口，`ManuscriptEditor` 窗口级快捷键 | 精确字面匹配，不改正文；位置按 Unicode 码位数报告；Esc 关闭并还焦点；IME 组字期间不拦截 |
| Ctrl+S 立即保存 | `ManuscriptEditor` 全局键盘处理 → `editing.flushAll()` | 仅刷新保存状态，不伪造成功；失败由 `SaveStatusStrip` 的稳定错误码展示 |
| 章节标题区字数 + 内联重命名 | `ManuscriptEditor` 标题行、`showTitlePrompt` + `controller.renameChapter` | 字数按 Unicode 码点；重命名走既有 CAS/刷新路径 |
| 章末“撤销/重做/讨论本章” | `ManuscriptEditor` 底部 Wrap | 复用 EditorDocument 撤销栈；窄窗/大字号不溢出 |
| 全章讨论（无选段的 target=null 线程） | `DiscussionThread.createChapter`、`DiscussionRegistry.chapterThread`、`DiscussionPanel` 对话框 | 仅讨论，不冒充生成；生成仍需有效选段；作者快照不含服务端 projection |
| 讨论索引（含失效选段、未发草稿标记、跳转） | `lib/cowrite/discussion_index.dart`、`ManuscriptEditor._openThread` | 每个已存讨论可达；失效选段仍可定位到历史宿主或打开全章讨论 |
| 章节目录搜索过滤 | `WorkbenchContents` 本地标题过滤 | 仅标题（非当前章正文按设计不入内存）；过滤态禁用拖拽重排；空态明确 |
| 正文与资料 Markdown 导出 | `RecoveryExporter` 增加 `includeLore`/扩展名，`ExportMode.manuscript`，工具栏“导出正文与资料” | 复用同一套系统保存对话框 + 写后读回校验；资料读取失败则不写文件；恢复导出保持原 `.txt` 草稿语义 |
| 旧想法转换目标查看/编辑（原 TargetPage 等价） | `IdeaTargetDialog`、`MemoryActions` 新增“查看/编辑目标”，`LegacyRepository.ideaTarget/updateIdeaTarget` | 目标指针来自作者 payload 的 `convertedTo`；复用既有 memoryDetail/memoryCorrect 的 CAS；小说作品名随目标标题同步；无新增 FRB 接口/schema |

本地化：新增 31 个 key（271 keys × en/zh-Hans/zh），`flutter gen-l10n` 无差异。

## 验证（本机、合成数据）

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib test integration_test bin` | 0 变更 | 本记录 |
| `flutter analyze --fatal-infos` | 0 issue | 本记录 |
| ARB key/占位符一致性（3 个 ARB，271 keys） | PASS | 本记录 |
| `flutter gen-l10n` 前后哈希 | 一致（3 个生成文件） | 本记录 |
| Flutter 普通/生产 DLL 回归（36 文件，排除 golden 与隔离 owned 文件） | **502 / 502 PASS** | `docs/evidence/m5/small-features-regression-20261020.txt` |
| 真实生产 DLL 迁移专项（全章讨论持久化 + 转换目标读写） | 1 / 1 PASS | `docs/evidence/m5/small-features-real-ffi-20261020.txt` |
| 隔离 test-support 加密持久库 | 2 / 2 PASS（独立 DLL + run id） | `docs/evidence/m5/small-features-owned-ffi-20261020.txt` |
| Rust 工作区测试（test-support） | **292 / 292 PASS** | `docs/evidence/m5/small-features-rust-workspace-20261020.txt` |
| `cargo fmt --check`（application/bridge） | 退出 0 | `docs/evidence/m5/small-features-rust-20261020.txt` |
| 严格 Clippy `-D warnings`（application/bridge） | 退出 0 | 同上 |
| `flutter build windows --release` | PASS | `docs/evidence/m5/small-features-release-20261020.txt` |
| 复制 Release 包探针（移走 SDK PATH） | 探针退出 0；最终包 `build/m1-distribution-703462be59544eb79a51538de1f79859` | `docs/evidence/m5/small-features-bundle/copied-bundle-status.json` |
| 复制包缺 bridge DLL | 退出 1（fail closed） | 同上 |
| 基线复核（改动前） | analyze 通过；普通回归 483 PASS + 1 个隔离 owned 文件因测试 DLL 作用域不符被单列（非缺陷） | `docs/evidence/m5/baseline-20261020.txt` |

## 新增测试文件

- `test/chapter_find_test.dart`：匹配/循环/位置/未命中/Esc 关闭。
- `test/writing_features_test.dart`：字数、重命名、目录过滤、全章讨论持久化、索引、Ctrl+F、导出入口；窄窗布局由既有 `m2_workbench_test.dart` 矩阵覆盖。
- `test/idea_target_test.dart`：convertedTo 指针解析（对象/编码/缺失/损坏）、目标加载/保存/CAS 失败/目标缺失。
- 扩展：`test/cowrite/discussion_registry_test.dart`（全章线程复用与 target=null 持久化）、`test/m4_export_test.dart`（Markdown+资料、资料失败不写文件）、`test/m9_real_ffi_test.dart`（真实 DLL 全章线程 + 目标读写）。

## 已知边界（未随本次提升）

- 未重写/未审阅视觉 golden；现有两张 golden 差异为既有状态，本次 UI 调整后需在 M2/M3 收尾时统一复审。
- 未做真实 Windows IME、DPI、多屏、Snap、系统保存对话框人工流程；导出使用注入 gateway 的单元测试 + 复制包 M1 探针，不等同原生对话框验收。
- 未实现仅存在于旧浏览器预览/设计路由的功能（Ctrl+K 项目搜索、预览 JSON 导出、AgentPanel 旧聊天、llm 模型列表等）；它们不属于活动原生写作入口。
- M5–M9 阶段出口、真实 DeepSeek、作者库接管、净机安装与发布状态不变。
- `scripts/check-m2-l10n.ps1` 仍按 M2 时期要求每个 key 都有 description，当前 ARB 中大量后续 key 无该元数据（历史状态），本次以 gen-l10n 成功 + 键/占位符一致性脚本核验；未改该脚本口径。
