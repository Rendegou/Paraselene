# 批次 F（R15 文档入口整理、R16 文件清理与重建）交付记录

工作树：`D:\MyAgent\paraselene-flutter`，HEAD `cb2271778163a0fb98d1ebf4737ade0a0790b619`（未提交）。
依据：`docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md`（批次 F、R15/R16）。
本文件随 R15/R16 逐项追加。

## R15 文档入口整理

改动（不删除任何既有文档/历史结论）：

- `README.md`：新增「当前状态（2026-10-20）」——生产编辑器、视觉对齐、R01–R16 整改进度、当前 NOT_RUN 边界；给出进度、整改证据、视觉对齐、注释规范入口与目标测试命令；原 M0–M2 段落保留并标明为历史里程碑描述。
- `docs/progress.md`：在标题下新增「当前状态（2026-10-20）」表，逐项列出 M0、M1、M2、M2-W、M3、M4、M5–M9、视觉对齐、中文注释、批次 A–E、批次 F、最终门禁的状态与证据指针；标明后续历史段落保留当时结论、不回溯改写。
- `docs/M3-PRODUCTION-EDITOR-PLAN.md`：在状态行后补充后续状态说明——候选 C 已生产化，R05/R06/R08 修正了当时的槽位/滚动假设；原文与决策点保留为设计历史。
- `docs/ADR-003-editor-spike.md`：在状态行后补充后续状态说明——候选 C 已生产化，原始决策与性能数字保留不改写。
- 新建 `docs/evidence/operation-parity-20261020/README.md`：批次 A–F 文件索引、R01–R16 状态表、V01–V28 指向 `batch-E.md`、统一命令入口、NOT_RUN 汇总。

验证：
- 所有新增引用路径均存在（`UI-PARITY-20261020.md`、`COMMENT-PASS-20261020.md`、`comment-style-20261020.md`、`batch-A-B.md`、`batch-C.md`、`batch-D.md`、`batch-E.md`）。
- 本批次仅改 Markdown，无代码/生成文件变更；未运行测试（文档变更不影响构建）。

未测/NOT_RUN：无（文档整理）。历史 NOT_RUN 项保持原样，不因文档整理改成 PASS。

## R16 文件清理与重建

### 保留交付

- 最新且唯一实际 PASS 的 M1 独立包：`m1-distribution-393029de294444c5b2c35c2c20979c2f`（2026-10-20T14:45:35 创建，65 文件；`docs/evidence/m1/copied-bundle-status.json` 于 14:45:47 记录 `Status=PASS`、`ProbeExitCode=0`、`MissingDllExitCode=1`、`SdkRemovedFromPath=true`）。
- 归档位置：`build/release-archive/m1-20261020-1445/`，内含完整包目录、`copied-bundle-status.json`、`copied-bundle-report.json`、`copied-bundle-manifest.json`、`missing-bundle-dll-report.json`、`copied-bundle-transcript.txt`、`README.md`、`SHA256SUMS.txt`。
- 其余 10 个 `build/m1-distribution-*` 旧副本路径集合与归档包一致、无独有文件，已删除。

### 台账与执行

- 扫描：`cleanup-scan.ps1` → `cleanup-scan.json`（HEAD `cb22717…`、git status 302、Flutter 3.32.1、OS 10.0.26200、PS 7.6.7、2026-10-20T20:38:22+08:00）；C01–C14 的文件数/字节/`git ls-files`/`check-ignore` 全部记录；11 个分发副本路径集合完全一致。
- Dry-run 与执行：`cleanup-apply.ps1 -DryRun` 输出写入 `cleanup-apply-dryrun.json`，随后同一脚本 `-Execute` 写入 `cleanup-apply-execute.json`；逐项 `GetFullPath` 校验在仓库根内，失败即停。
- 实际释放：**19,960 文件、12,431,014,076 字节（约 11.58 GiB）**：C01 14,087/8,615,939,783；C02 3,012/1,855,087,884；C03 1,538/402,249,153；C04 414/329,520,914；C06 27/43,793,891；C07 4/28,649,712；C10 dist 7/17,752,179 + browser-profile 221/9,384,436；旧 D 副本 10 个共 650/1,128,636,124。
- 保留：C05 `build/learning-native`（28 junction，未完成专项证明）、C08 `build/vendor`（WebView2 SDK）、C09 `spikes/editor_comparison`（4 链接）、C11 失败证据、C12 goldens、C13 evidence、C14 `build/m4-owned-synthetic-v1`，以及 §9.5 排除的 `build/comment-work`、`build/full-suite-after-restyle.log`、`build/lifecycle-*.log` 等。
- 逐项台账见 `cleanup-manifest.md`；未使用 `git clean -fdx` / `reset --hard`，未整清 `build/`。
- 产物生命周期：`scripts/verify-m1-bundle.ps1` 新增 `-KeepPreviousDistributions`；PASS 后默认只保留本次副本（最多 2 个），避免 `build/m1-distribution-*` 无限累积，已归档包不受影响。

### 重建（清理后）

| 命令 | 退出码 | 证据 |
| --- | --- | --- |
| `flutter pub get --offline`（apps/desktop） | 0 | `rebuild-pubget-desktop.log` |
| `dart pub get --offline`（packages/text_contract） | 1（缓存缺 lints 6.1.0） | `rebuild-pubget-text_contract.log` |
| `dart pub get`（同上，联网补齐；lock SHA256 未变） | 0 | `rebuild-pubget-text_contract-online.log` |
| `cargo … build -p paraselene-bridge --target-dir build/rust-m1-msvc --locked --offline` | 0 | `rebuild-cargo-prod.log` |
| `cargo … build -p paraselene-bridge --features test-support --target-dir build/rust-m4-test-msvc --locked --offline` | 0 | `rebuild-cargo-testsupport.log` |
| `flutter build windows --release` | 0 | `rebuild-flutter-release.log` |
| `scripts/verify-m1-bundle.ps1 -EvidenceDirectory docs/evidence/operation-parity-20261020/bundle-probe` | 0（PASS） | `bundle-probe/copied-bundle-status.json`（新副本 `m1-distribution-017abf…`，ProbeExitCode 0、MissingDllExitCode 1） |

`packages/text_contract` 的离线恢复因本机 pub 缓存只有 `lints 5.1.1`、而 lock 固定 `lints 6.1.0` 失败；联网重建后 `pubspec.lock` SHA256 未变化，记录为环境偏差，不宣称离线可复现该包 `.dart_tool`。

### 最终统一门禁（清理后重建的同一构建）

| 门禁 | 结果 | 证据 |
| --- | --- | --- |
| `flutter gen-l10n` | 退出 0 | `final-gen-l10n.log` |
| `dart format --output=none --set-exit-if-changed lib test integration_test bin` | 168 文件 0 变化，退出 0 | `final-format.log` |
| `flutter analyze --fatal-infos` | No issues，退出 0 | `final-analyze.log` |
| 生产能力 DLL 全量 Flutter（排除 golden 与 owned 专项） | **571 tests All passed**，退出 0 | `final-full-suite.log` |
| owned 专项（test-support DLL + 独立 runId） | **2 tests All passed**，退出 0 | `final-owned.log` |
| golden 单独报告 | 2 failed（既有视觉基线未重批；未执行 `--update-goldens`） | `final-golden.log` |
| Windows integration m1 | 1 passed，退出 0 | `final-integration-m1.log` |
| Windows integration m2 | 1 passed，退出 0 | `final-integration-m2.log` |
| Windows integration m4 | 2 passed，退出 0 | `final-integration-m4.log` |
| Rust 单测/clippy | NOT_RUN（Rust 源码未改动，§7.4 允许；桥接 debug/test-support/release 已重建并通过真实 DLL 测试） | — |

Windows 集成测试随视觉/交互改造更新到当前入口（侧栏「切换作品」、`EditorViewport` 正文读取、语言菜单宽窄两种入口、纸张标题「重命名章节」、右键章节菜单归档、版式菜单回调），未放宽断言；m2 截图证据写入 `docs/evidence/m2/windows-real-zh.png`、`windows-real-en.png`。

### R16 未执行/NOT_RUN

- 净机安装、安装器/卸载残留、真实作者数据库迁移与接管：NOT_RUN。
- C05/C09 链接专项拆除：未证明安全，按文档保留整树（不是清理漏项）。
- golden 基线重批：未执行，保持历史 NOT_RUN；本轮不宣称视觉 golden PASS。
- 真实 IME/物理 DPI/系统剪贴板/关闭失败恢复：仍为 NOT_RUN（见批次 E 汇总）。

**结论：R16 完成。V28（清理后重建）PASS。R01–R16 全部完成，工作树未提交。**
