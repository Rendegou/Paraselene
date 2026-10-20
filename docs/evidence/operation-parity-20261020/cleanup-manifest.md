# R16 清理台账与 manifest（2026-10-20）

范围：严格按 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md` §9 执行；先冻结记录，再保留可验证交付，逐项证明可再生产物，`-WhatIf`/dry-run 后同一轮执行，失败即停。

## 1. 冻结基线

| 项 | 值 |
| --- | --- |
| 工作树 HEAD | `cb2271778163a0fb98d1ebf4737ade0a0790b619` |
| git status 条目 | 302 |
| Flutter | 3.32.1 stable |
| OS | Windows 10.0.26200 |
| PowerShell | 7.6.7 |
| 扫描时间 | 2026-10-20T20:38:22+08:00 |
| 扫描脚本 | `cleanup-scan.ps1`（只读，输出 `cleanup-scan.json`） |
| 执行脚本 | `cleanup-apply.ps1`（`-DryRun`/`-Execute`，逐项 `GetFullPath` 越界校验，失败即停） |

## 2. C01–C14 清理台账

```text
目标                                          文件数    字节          处置      依据
C01 build\rust-m1-msvc                        14087    8,615,939,783  删除      cargo --target-dir 可再生；git 未跟踪且 ignored
C02 build\rust-m4-test-msvc                    3012    1,855,087,884  删除      测试支撑 DLL 构建产物；按 §9.7 重建
C03 rust\target                                1538      402,249,153  删除      cargo target 可再生
C04 apps\desktop\build                          414      329,520,914  删除      Flutter 构建产物；最新 PASS 包已先归档
C05 build\learning-native                      6143      259,759,832  保留      含 28 个 junction，未完成链接专项证明，按文档保留整树
C06 apps\desktop\.dart_tool                      27       43,793,891  删除      pub 缓存可再生（flutter pub get --offline）
C07 packages\text_contract\.dart_tool             4       28,649,712  删除      同上
C08 build\vendor                                 91       53,937,273  保留      WebView2 SDK，必须保留
C09 spikes\editor_comparison                    111      289,118,864  保留      含 4 个链接，按文档保留，仅核实非白名单子目录
C10 spikes\codemirror_baseline                  236       27,161,749  部分删除  dist/(7 文件 17,752,179 B)、browser-profile/(221 文件 9,384,436 B) 可再生；源码 8 个跟踪文件保留
C11 apps\desktop\test\failures                    8          499,530  保留      测试失败证据
C12 apps\desktop\test\goldens                     2          116,176  保留      golden 基线，禁止清理
C13 docs\evidence                               898        9,184,320  保留      证据，含历史 NOT_RUN 记录
C14 build\m4-owned-synthetic-v1                   2          344,294  保留      §9.5 明确排除的合成库
```

- 删除目标均满足：`git ls-files` 数量 0、`git check-ignore` 为 true、路径在仓库根内且不是根本身；未使用 `git clean -fdx` / `reset --hard`，未按名称批量清空 `build/`。
- 排除项按 §9.5 保留：`build/m4-owned-synthetic-v1`、`build/m4-owned-test-v1`、`build/comment-work`、`build/full-suite-after-restyle.log`、`build/lifecycle-*.log`、`build/vendor`、`build/learning-native`、`spikes/editor_comparison`、`.computer-use-probe`、evidence/goldens。

## 3. D01–D11 分发副本

11 个副本的相对路径集合完全一致（各 65 文件）；字节数约 112.8 MB/包。最新且唯一实际验证 PASS 的正式包：

- 目录：`build/m1-distribution-393029de294444c5b2c35c2c20979c2f`（创建 2026-10-20T14:45:35+08:00）
- 证据：`docs/evidence/m1/copied-bundle-status.json`（修改 2026-10-20T14:45:47+08:00）`Status=PASS`、`ProbeExitCode=0`、`MissingDllExitCode=1`、`SdkRemovedFromPath=true`
- 报告 checks：unicode_reopen、revision_conflict、identity_mismatch、session_closed、cloud_disabled、cancelled、closed、bounded_notifications、authoritative_status、unsubscribe、invalid_synthetic_root

处置：该包整体移动至 `build/release-archive/m1-20261020-1445/m1-distribution-393029de294444c5b2c35c2c20979c2f/`，同时归档 status/report/manifest/transcript/README/SHA256SUMS；其余 10 个旧副本（均被新 PASS 包取代、路径集合相同、无独有文件）已删除，共 650 文件、1,128,636,124 字节（约 1076.35 MiB）。

## 4. 执行结果

- Dry-run：`cleanup-apply.ps1 -DryRun`，逐项打印目标/文件数/字节，总字节与执行一致，无越界。
- 执行：`cleanup-apply.ps1 -Execute`，输出 `cleanup-apply-execute.json`。
- 实际释放：**19,960 文件、12,431,014,076 字节（约 11.58 GiB）**。
- 保留后可验证交付：`build/release-archive/m1-20261020-1445/`（完整 65 文件包 + SHA256SUMS + PASS 证据）。
- 清理后构建产物需按 §9.7 重建（C01/C02/C06/C07/C04），重建前不得把 Release 门禁结果当作本轮证据。

## 5. 产物生命周期修订

`scripts/verify-m1-bundle.ps1` 增加 `-KeepPrevious` 开关：默认 PASS 后只保留本次验证的副本并移入 `build/release-archive/<时间戳>/`，不再让 `build/m1-distribution-*` 无限累积；`-KeepPrevious` 时额外保留上一份作为回退。EvidenceDirectory 语义不变。

## 6. 未执行/NOT_RUN

- C05/C09 的链接专项拆除：未证明安全，保留整树（不是清理漏项）。
- 净机安装、真实作者数据接管、系统级卸载残留检查：NOT_RUN（见批次 F 证据）。
