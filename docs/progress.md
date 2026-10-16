# Flutter 迁移进度

2026-10-15；Owner：当前迁移会话。原工程只读，独立分支 `codex/flutter-migration-20261015`。

- M0 Text/Locale Contract：IMPLEMENTED，9项Dart测试/2项Rust测试、静态检查、5组跨语言向量通过；独立审查已修正质量入口失败证据记录，最终交付验证见 `docs/evidence/M0-20261015.md`。
- M1 Windows runner/FRB/storage：IMPLEMENTED。Build Tools安装退出0；Windows doctor、Release构建、182项Rust测试、严格Clippy、真实FFI/CLI与Windows集成通过。独立复制包移除SDK PATH后验收通过，缺DLL退出1。FRB2.11.1生成绑定重跑无变化；5个core crate的79份快照及原工程559份文件不变。最终独立审查与证据见 `docs/evidence/M1-20261015.md`。
- M2 多语言与视觉工作台：IMPLEMENTED。中英47条ARB、脚本感知fallback、离线字体、目录/作品选择/专注/宽稿/错误区已实现；301项非golden检查（含288组双语布局矩阵）、2项真实字体golden、真实Windows缩放/语言切换、M1诊断回归与Release构建通过。九项统一检查均退出0，独立整体审查批准。详见 `docs/evidence/M2-20261015.md`。
- M3：C_FEASIBILITY_PASS。用户已接受C隔离验证3–5有效人日粗估，并按"优化代价大就通过"规则裁决通过。第二轮增量布局51测试、analyze、profile构建通过，同机profile exit 0：7/7样本输入P95≤29.24ms、装载≤71ms、普通滚动全部通过；首轮真实IME重复字符已修复并经同一物理按键序列复测通过（raw51/`ni`/composing10:12，trace与截图存档）。第三轮单次排版优化（页高取自探针行测，取消双重排版）后51测试/analyze/build/profile仍全过，编辑P95进一步改善（单行25.4→19.8、非重复29.2→22.6），但stress全幅滚动（连续118/120帧超33ms）与无换行长文档中段冷跳（2319ms）确认为懒测量架构固有代价，消除需动验收契约或架构，故按规则接受为已记录限制。此前A/B字体打包错误已更正，重采A/B200k编辑P95约85/214ms；`m3/flutter-profile.json`在19:11被一次误构建重写，A/B对照以`m3/ab-font-validated-profile.json`为准。M3 截止时正式工作台保持只读；后续已获授权进入 M4，作者数据接管仍未授权；C生产化（ADR-003另估12–20人日）未授权。当前见 `docs/evidence/M3-C-20261015.md`，实现细节见 `docs/evidence/m3/c-incremental-implementation.md`，原A/B历史见 `docs/evidence/M3-20261015.md`，投入边界见 `docs/ADR-003-editor-spike.md`。
- M4：IN_PROGRESS（2026-10-16 接续复核；Kimi checkpoint `d426219` 的门禁通过，真实关窗/系统导出验收及新发现修正待完成）。切片计划、出口映射与逐片记录见 `docs/evidence/M4-20261015.md`。M4-1 Rust 硬化、M4-2 桥接/repository、M4-3 保存协调器均经独立复审通过；owned-synthetic 冷启动持久化（ADR-004）跨进程/强杀/篡改/毒化验证齐全（`docs/evidence/m4/OWNED_PERSISTENCE_REPORT.md`）；M4-4 工作台接线与 M4-5 关闭屏障/恢复导出完成（`docs/evidence/m4/UI_INTEGRATION_REPORT.md`）。整体独立审查可交付，2 项低危发现已修并补回归，3 项记录为已知问题（REVIEWS.md）。check-m4 门禁 12 项全部 exit 0：rust 全套、gen-l10n、dart-fmt、analyze、346 项 Dart 测试、release 构建、真 Windows 集成 m1/m2/m4。完整性：原工程 559 源码哈希、core 79 快照、176 git 状态全部一致。范围边界：M4 使用明示的临时简易编辑面（不宣称长文性能），M3 生产编辑器、作者数据接管、真实模型仍未授权。
- M5–M9：NOT_RUN。

本轮实施授权已获得。之前规划中的“本轮不实施”仅约束规划交付，不限制本次用户明确要求执行。

M0放在 `packages/text_contract` 而非根Flutter依赖中，保证纯Dart/无UI测试边界；M1未来app引用该包。原计划目录职责不变。
