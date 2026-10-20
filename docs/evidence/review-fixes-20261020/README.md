# 2026-10-20 整改复核 F1–F4 修复

本记录接续 `../operation-parity-20261020/review-20261020.md`。仅修改 Flutter 交互与分发验证脚本；保留工作树已有修改，未操作原工程或作者数据库，未发模型请求。

## 修复结果

- F1：全局快捷键同时检查正文自定义输入客户端的 composing 状态和普通 EditableText 的有效非空组字区间，组字中的 Ctrl+F/Escape 交还输入法。
- F2：生成运行态移入 DiscussionRegistry 持有的 DiscussionGenerations，以作品/章节/线程冻结身份；收起不取消，重开可取消。同线程禁止重复在途请求，取消准备阶段的票据、作用域切换和取消失败重试有合成回归。完整外发预览与明确发送确认保留，完成后释放预览材料。
- F3：共享当前讨论身份；资料预览打开时冻结作品/章节/讨论目标，带入和移除使用相同目标。无活动讨论时才回退到整章，跨章节返回拒绝写入。中英文提示改为“当前讨论”。
- F4：移除验证脚本按目录名称和创建时间删除历史分发的逻辑。KeepPreviousDistributions 只作兼容参数；验证过程不清理历史副本和失败现场。

## 验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 修改 Dart 文件格式 | PASS，10 文件，0 变化 | 终端 dart format |
| gen-l10n | PASS | gen-l10n.log |
| flutter analyze --no-pub | PASS，No issues found | analyze.log |
| operation_parity + cowrite | PASS，79 项 | focused-tests.log |
| 普通全量回归，生产能力 DLL | PASS，583 项 | regression-tests.log |
| owned 独占合成目录，test-support DLL | PASS，2 项 | owned-tests.log |
| Windows Release 构建 | PASS | release-build.log |
| 独立复制包探针 | PASS，正常退出 0；缺 DLL 退出 1 | bundle/copied-bundle-status.json |
| 历史分发保留 | PASS，全部已有目录仍在，合成哨兵 SHA256 不变 | bundle-retention.json |
| 启动可见客户端 | PASS，PID 37404，窗口句柄 526372 | client-launch.json |

新增 12 项永久回归，位于 `apps/desktop/test/operation_parity/review_fixes_test.dart` 与 `apps/desktop/test/cowrite/discussion_generations_test.dart`。重开面板的 UI 测试还实际点击取消，断言仓库收到一次取消。

第一次定向运行发现三个测试结束前未排空去抖计时器，已在测试内显式 flush/pump 后通过；第一次 owned 启动使用了带前缀的运行 ID，被隔离合同拒绝，改为规定的 32 位 GUID 后通过。未放宽生产校验。

普通全量排除了历史 golden 文件和单独运行的 owned 文件。既有两项 golden 失败未重跑或重批；真实物理 IME、DPI、多屏及净机安装仍 NOT_RUN。本次组字检查为注入 composing 状态的组件回归，不能替代真实输入法验收；客户端启动记录确认进程和窗口已创建，不代表人工点击矩阵通过。Rust 源码本轮未改，未重复 Rust 单元测试。

SDK 位于工作区外，Flutter 通过获准的 Dart 快照入口访问缓存运行。新客户端：`D:\MyAgent\paraselene-flutter\apps\desktop\build\windows\x64\runner\Release\paraselene_flutter.exe`；可执行文件与桥接 DLL 的 SHA256 见 client-launch.json。
