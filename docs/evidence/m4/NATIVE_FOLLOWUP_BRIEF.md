# M4 checkpoint 原生与测试隔离修正

接手 d426219。先读 CHECKPOINT_NATIVE_REVIEW.md 的完整 findings；逐项修正并验证，本合同补充当前真实安全边界。此切片等待 m4_close_followup 释放SDK后派发，不并行实施。

- Windows/pwsh，固定MSVC Rust/offline/locked，原工程只读、core79文件不改。ADRs004与OWNED_PERSISTENCE_BRIEF约束保持。
- 测试专用 open_owned_at_for_test/helper 放显式 test-support feature 隔离，默认release/bridge不含；实际FRB生产只固定ownedroot。更新Rust测试/gate feature调用，不能通过漏跑test冒充通过。报告明确crateAPI/FRB/打包helper三种不同暴露范围。
- 已有 snapshot.pending 可能是上次本应用崩溃遗留，需要安全恢复；删除非空pending前认证DPAPI/版本/目的/绑定根，并验证有效SQLite image，未知/坏内容原样保留并报错。不能以保留文件名当来源证明；empty partial staging如何处理需明确且验证。
- P1容量边界：read_file上限128MiB而publish没有对称限制，不能成功确认写出自己下次拒读的snapshot。加密包发布前校验同一上限（含DPAPI开销），拒绝时保留旧已发布snapshot并毒化已变更会话；测试边界使用可控小限制验证真实相同行为，不必生成巨型库。
- 跨进程恢复断言直接比较 body UTF8/codepoints 与独立预期，并重算BLAKE3而不只比较存储hash；confirmed/rebased/空稿至少覆盖相关hash规则。
- 新owned-store hardlink与reparse目录/payload/pending拒绝测试；旧M1 provenance不是新入口覆盖证据。不能更改Windows设置/权限以跑测试，无权限场景诚实NOT_RUN。
- 原子替换前失败与替换后响应丢失都证明old/new完整态；cfg-only fault seam或独立helper强杀，不能提供生产faultAPI。
- 部分 staging 写入被杀与未知 pending 必须同时正确：建议新建staging先用 Windows delete-on-close 句柄，完整写入+flush后才清除delete disposition再关句柄/rename；因此写到一半强杀由内核删自己新建staging，完整后强杀留下可认证pending。不能只让未知pending报错却忽略本程序中途崩溃导致永远打不开最后成功稿的情况。如选其他协议需证明等价与不删未知内容，覆盖during-staging/afterflush/prerename/postrename边界，不声称硬件断电。
- 重点修正测试隔离：当前 test/m4_owned_repository_test.dart 与 integration_test/m4_app_test.dart 会递归删除生产固定ownedstore。这是本轮已存在synthetic编辑状态，绝不能再删除。优先受控独立 test feature bridge + 临时ownedroot、严格allowlist及test-sentinel；生产没有任意pathAPI。若无法无成本测试bridge，则可靠保存并恢复原store也必须异常/强杀安全，不能用脆弱try/finally复制后delete冒充隔离。可以改FFI test运行独立process/诊断helper，评估最小安全方案并与root说明。
- 隔离架构采用独立 `test-support` feature / `build/rust-m4-test-msvc` DLL，正式无参数入口固定生产根，测试构建固定在 `build/m4-owned-test-v1` 基目录，允许仅测试feature读取严格十六进制runId创建子目录。打开store前通过无副作用的bridge build-info校验 production/test 身份与scope；NativeRuntime初始化缓存记录身份，错误DLL/缺失runId/非法runId不得回退生产DLL或打开store。原M1 diagnosticOverride仅代表受控DLL路径，不等于test-support身份，两者要分开。生产bundle误载testDLL也拒绝。可加FRB公共build-info DTO/查询但不加生产任意路径入口。
- 两个Dart测试用共享fixture，初始化并校验专用DLL后排他创建run root/sentinel，仅清理自己已创建/核验且落在测试基目录内的目录；未知已有root拒绝。check-m4区分普通productionDLL回归与专用owned测试，Windows m4测试显式diagnostic override+expected test身份；保留production bundle独立验证。运行前请向root报告具体隔离设计，无需再向用户提问。
- 不读取/删除未知数据，不主动清扫整个temp。强杀owned临时fixture积累若处理必须限定明确拥有的根，句柄/锁验证后再删；安全做不到记录后续，不能扫带前缀目录就删。
- 模块<=400行，函数<=60有效行。默认API保持，不迁框架，不改Dart关闭逻辑。只针对故障与测试隔离修正，Context7不可用已由当前实现者尝试，查固定缓存源码并记证据。
- 测试日志新写m4-native-followup-*；不得覆盖旧门禁PASS，SDK单槽位。权限workspace-write+auto-review，必要缓存/进程权限申请自动审查，不盲试。报告NATIVE_FOLLOWUP_REPORT.md含命令/results/limitation；不commit/不派实施子代理，完成释放SDK。
