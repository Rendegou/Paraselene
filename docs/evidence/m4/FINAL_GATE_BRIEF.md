# M4-6 验收与收尾合同

在所有实施切片及独立 spec/quality review 通过后执行。M4 整体仍 IN_PROGRESS，不能以单片测试称完成。

## 门禁脚本

新增 `scripts/check-m4.ps1`，继承现有 M1/M2 有意义门禁但所有输出写 `docs/evidence/m4/checks`，保留历史 M1/M2/M3 日志。结构化记录命令、参数、时间、退出码，每步失败最终 nonzero。

- ARB parity/gen-l10n freshness/format/Flutter analyze。
- application Rust tests（含 hardening/migration/selection/owned-store 跨进程/fault/provenance），owned crates fmt/clippy；core snapshot 不变。固定 MSVC/offline/locked。
- Dart 行为、布局矩阵、真实字体 goldens、真实 DLL repository/SaveCoordinator/controller 组合。
- 真 Windows M4 runnable flow、M2适配后回归、M1诊断回归；实际 X/Alt+F4 关闭屏障成功和故障保持打开+重试/导出，不以直接调用回调代替。
- Release Windows bundle，同次同源 native DLL；产物文件/hash、支持资料、合成数据hash、OS/工具链/locale/window/DPI。

## 真 Windows 合成流程

建两作品，各两章；持续输入时触发保存，空正文保存，跨章/跨作品隔离，改名/重排/归档/恢复，正式确认精确预览/新 revision 再编辑，历史回滚不复制版本，再编辑可保存。中英切换正文/选区保持。最近作品/章节/宽稿/滚动关闭重开恢复。作者数据始终不接入。

真实 SQLite BUSY/FULL 已由 Rust测试证明，controller替身仅证明界面失败策略；若 Windows runnable 使用故障注入必须明确哪层注入，不把替身称真实磁盘故障。至少一次真实 native 保存失败穿过 FFI 至关闭/恢复导出可见路径，读回 UTF8 精确正文并记录取消行为。

独立 native 强杀/重开证明最后成功快照；不宣称尚未保存内存稿抗强杀。版本/线程/来源计数使用既有 v10→v12 合成 fixture 证据，不能读取原作者库比较。

Computer-use 如需：先读完整 computer-use SKILL + guide/confirmations，以 node_repl/@oai/sky 操作精确识别的本应用窗口；不用 PowerShell SendInput/UIAutomation。尽量使用既有 Windows integration harness 验证；截图不能含私人窗口。

## 最终审查与交付

- 汇总 M4 当前变更 diff 包（从 febc528 接手基线起，纳入 untracked 文件），交最强可用模型做整体审查；根据完整 findings 一次派修复、覆盖测试、复审。
- 再校验原工程559源码 SHA256/176Git状态、core79快照；git diff --check、生产文件行数、生成桥/ARB freshness、产物与测试DLL匹配。
- 更新 `docs/progress.md`、M4证据、review ledger/ADR004实际状态，逐项 PASS/FAIL/NOT_RUN，明确临时编辑器与全快照成本限制。
- 合理本地 checkpoint commit，但不得未经用户请求创建PR/merge/push/publish；M5–M9保持 NOT_RUN。
- 完整bundle路径和简洁运行说明可交付；不能只发 EXE。作者迁移与 C编辑器生产化仍未授权。
