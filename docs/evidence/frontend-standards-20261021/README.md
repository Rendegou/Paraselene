# 前端规范整改收尾 · 2026-10-21

## 上下文

前序 Codex 会话按 `docs/engineering/frontend-standards.md` 完成 F01–F14：拆分工作台、编辑器、讨论、资料与 legacy 巨型文件，集中主题令牌/控件/选择器/组件主题，新增 AST 结构与 ARB 检查工具及统一入口 `scripts/check-frontend.ps1`，证据在同目录 `final/`。该会话在最后一次修复后达到用量上限，尚未给出最终统一门禁结论；工作树留下未格式化的 `apps/desktop/test/m2_workbench_test.dart`。

本次在 DSH 会话中继续：读取本机 Codex 会话记录、复核代码与证据、修完遗留测试问题、重跑统一门禁，再提交工作树。

## 收尾改动

- `apps/desktop/test/m2_workbench_test.dart`：格式化；保留焦点/宽稿用例的 `hitTestWarningShouldBeFatal` 守卫，新增 `_chooseLayout` 辅助方法，改为点击完整 `CheckedPopupMenuItem` 菜单行而不是行内文字，消除 `Finder specifies a widget that would not receive pointer events` 命中警告。
- `docs/progress.md`：追加本轮完成条目。
- 本 README。

## 统一门禁结果（同一工作树、同一构建）

报告目录 `continuation-final/`，`RunId=9e60451bd350488098599482848b30c2`；`SelectedChecksStatus=PASS`，`OverallStatus=PARTIAL`（仅因物理项 NOT_RUN）。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| AST 结构/主题 | PASS，139 文件 0 违规 | `ast-structure-theme.txt` |
| 门禁负向测试 | PASS，21 tests | `gate-negative-tests.txt` |
| ARB 合同 | PASS，336 键 × 3 文件 | `arb-contract.txt` |
| Dart format | PASS，216 文件 0 变化 | `app-format.txt` |
| analyze（应用/文本/门禁工具） | PASS，No issues | `app-analyze.txt`、`text-analyze.txt`、`gate-analyze.txt` |
| text_contract 测试 | PASS，9 tests | `text-tests.txt` |
| 普通回归（生产 DLL） | PASS，640 tests | `regression-production.txt` |
| owned 专项（test-support DLL） | PASS，2 tests | `regression-owned.txt` |
| golden 比较 | SKIPPED（8 张历史差异图未重批） | `summary.json` |
| Windows Release 构建 | PASS | `windows-release-build.txt` |
| 独立复制包 | PASS，`m1-distribution-24ba89d16fe948a1a847303ba12fa20a`；probe 0、缺 DLL 1、PATH 移除 SDK | `bundle/copied-bundle-status.json` |
| 物理 IME / DPI 多屏 / 屏幕阅读器 / 净机安装 | NOT_RUN | `summary.json` |

`continuation-static/` 保留首次静态门禁（仅 `app-format` FAIL）与 `continuation-full/` 第二次全量门禁（`regression-production` 因上述命中警告 FAIL），作为修复前后证据；不作为产品失败或通过依据。

## 边界

- 未重批 golden、未清理既有分发历史；`scripts/verify-m1-bundle.ps1` 的保留策略未改。
- 未读取作者库/Key，未发模型或付费请求；原工程保持只读。
- 真实 Windows 物理输入、DPI/多屏、屏幕阅读器与净机安装仍需人工验收。
- 历史 UI 交互与页面覆盖证据见 `docs/evidence/ui-interaction-20261021/`、`docs/evidence/ui-completion-20261021/`；本文件只证明当前工作树所选自动检查通过。
