# 迁移进度接续核对

日期：2026-10-18（Asia/Shanghai）。本次仅核对代码、历史证据和补充计划；未运行 SDK、测试、构建、原生 UI 或模型请求，未访问作者数据。当前 HEAD `cb22717`，分支 `codex/flutter-migration-20261015`。

## 核对结论

| 模块 | 当前可确认状态 | 剩余事项 |
| --- | --- | --- |
| M0 | 合同模块已实施，历史 Dart/Rust/跨语言向量证据齐全 | 后续改动按合同回归 |
| M1 | Windows runner、FRB、Rust 存储及独立 bundle 已有通过证据 | 新插件和新产物仍需重新验证分发 |
| M2 | 中英工作台及历史布局／golden／Windows 验收已有通过证据 | 当前编辑器接入改变布局，旧结果不覆盖新工作树；新增 M2-W 标题栏计划 |
| M3 | C 编辑器可行性通过，已记录 stress 滚动与冷跳限制 | 生产化方案已提交，但实现处于未提交、未验收状态 |
| M4 | 作品、保存、版本、关闭／导出主链已实施，修复提交 `77e8498` | 原生持久化审查阻断项、最终复审、真实 WM_CLOSE／系统保存对话框验收未收尾 |
| M5–M9 | NOT_RUN | 不因编辑器或标题栏计划宣称讨论、模型或作者数据接管完成 |

## 工作树与证据差异

- `git status` 显示 15 个已跟踪修改项及未跟踪的 `lib/editor/`、`test/editor/` 两组目录。前者包含 manuscript_editor 接线、characters 依赖、测试适配及 8 个 golden 失败图像。保留这些既有改动；图像存在只能证明有失败产物，不能判断最后一次运行结果。
- 生产编辑器目录有 document/input/layout/frontier/scene/session-adapter/viewport 七个实现文件及五个测试文件；`ManuscriptEditor` 已从临时 TextField 接入自定义编辑面。代码存在与注释中的“production”不等于生产验收通过。本次未确认这些改动的来源或实施授权，不重做或扩展它们。
- `docs/M3-PRODUCTION-EDITOR-PLAN.md` 仍写“草案，待用户审阅授权”；`docs/progress.md` 和 M4 证据中的“临时编辑面”描述对应已提交基线。后续实施前应核对编辑器改动的实际范围与验证证据，不能用旧基线测试数证明新代码。
- `CLOSE_FOLLOWUP_REVIEW.md` 的两项 P2 对应旧审查时点。当前代码已有 `controller == null` 允许退出与 `_closeFlight ??= Future<bool>.microtask(...)`；这些修正已进入 `77e8498`。旧 FAIL 文档保留审查历史，但缺后续独立复审结论，不能只因文件写 FAIL 判定代码未修，也不能由源码检查宣称原生验收通过。
- `.superpowers/sdd/progress.md` 最后一段还写关闭修正进行中，为过时台账；本核对记录与主 progress 新增说明优先。原计划前十二节为 2026-10-15 历史审计，不代表今天所有模块仍 NOT_RUN。

## M4 仍须处理的阻断项

对照 `m4/CHECKPOINT_NATIVE_REVIEW.md` 与当前源码，以下审查问题仍可定位：

1. **P1**：`owned_store.rs` 读取拒绝超过 128 MiB 的 payload，而发布未在替换前做对应最终 sealed 大小限制，可能确认保存后无法恢复。
2. **P1**：发布仍按 staging 文件名删除既有 `snapshot.pending`，缺少对未知非空内容的来源认证。
3. **P2**：`open_owned_at_for_test` 仍公开编译，Cargo 未见非默认 test-support／helper required-features 门控。
4. **P2／证据缺口**：原审查要求对实际加载正文重新计算 UTF-8 BLAKE3，并补足发布故障边界、owned 路径攻击和完整状态强杀恢复等证据；未发现新的原生收尾报告。此项保持待验证，不重复原报告中的 PASS。

先处理这些项及测试隔离，再完成真实 X／Alt+F4、系统导出取消／失败／成功读回及最终复审。禁止调用会清理固定 owned-store 的旧测试入口；不删除现有合成稿。

## 自定义标题栏计划

已加入 `D:\MyAgent\paraselene-flutter-migration\MIGRATION_PLAN.md` 第 13 节，编号 M2-W，状态 PLANNED。包括隐藏系统标题栏候选、拖动区与窗口按钮、唯一关闭决策、保存／导出屏障、DPI／Snap／键盘及无障碍验收、独立 bundle 和回退条件。当前未增加窗口插件或修改 runner。

本次交付到进度核对与计划更新为止，后续建议顺序：M4 原生阻断项和关闭验收 → M2-W 独立探针与接线；M3 既有编辑器草稿另行核对、验收，不与已提交里程碑混算。
