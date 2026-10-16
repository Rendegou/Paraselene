# M4-4 / M4-5 工作台接线实施报告

2026-10-16。实现 `UI_INTEGRATION_BRIEF.md`。状态：**Dart 与真 DLL 层 PASS；真实 WM_CLOSE、系统保存对话框与 M4-6 组合验收见 FINAL_GATE 阶段**。

## 实现

- **编辑会话与屏障控制器**：`editing_session.dart`（正文/协调器/确认/回滚/恢复快照，
  contentEpoch 只在导航与外部重置时递增）；`workspace_controller.dart`（忙闸门、
  flush 先行、确认 token 流程、目录操作、UI 偏好防抖与冷恢复、closeBarrier）。
  `restoreSession()` 冷启动：workspaceState → 最近/选中作品 → 每作品 chapterId/
  wide/scrollTop 恢复；损坏记录只显示警告码，不覆盖正文。
- **临时编辑面**：`manuscript_editor.dart`。TextEditingController 仅在 contentEpoch
  变化时重置；保存通知永不重写正文；滚动恢复等布局完成；明示 TEMPORARY，不宣称
  20 万字性能。`SaveStatusStrip` 本地化五态 + 稳定码 + 显式重试 + 导出入口 +
  durable_save_failed 提示。
- **目录操作与对话框**：新建/改名/归档/恢复/拖拽重排；确认预览对话框（精确正文，
  预览期间继续输入自动关闭失效）；版本列表（精确正文预览+回退警示）。
- **关闭屏障与恢复导出**：`AppLifecycleListener.onExitRequested` 两阶段关闭；
  失败 cancel 保持窗口；对话框重试=显式 retrySave 后 closeBarrier；恢复导出
  （内存稿优先、omitted 逐章明示、UTF-8 写入+读回校验、取消不报成功）经缓存的
  file_selector 系统对话框；导出后"仍然退出"必须用户显式触发。
- **默认应用**改 `RealWorkspaceRepository.openOwned()`；启动失败不降级假仓库。

## 验证（命令与退出码；日志在 docs/evidence/m4/checks/）

- 新增控制器测试 12 项（m4_controller_test）、导出/关闭 5 项（m4_export_test）。
- `check-m4.ps1` 全 8 项 exit 0：rust-fmt / rust-tests（application 全量 37 项 +
  memory-core 108+17 + novel-core 43）/ rust-clippy(-D warnings) / rust-bridge-build /
  gen-l10n-freshness / dart-fmt / flutter-analyze(--fatal-infos) / dart-tests（346 项，
  含 288 布局矩阵、2 张真实字体 golden、真 DLL FFI）。
- M2 竞态测试按屏障语义适配（替身改挂 loadDocument；busy 拒绝重入保留"晚响应不
  覆盖"意图）；golden 两次有意更新并人工审阅（编辑面与工具栏/目录操作变化）。

## 与原工程语义对照

350ms 防抖、flushAll 复查、CAS 不推进错误 revision、重试沿用原 revision、槽位隔离、
归档不丢版本、确认先展示精确正文再决定、回滚丢弃编辑稿、最近作品截断 10、
UI session 键白名单——均逐条对应原端实现（见 M4 文档首节语义提取）。

## 剩余 NOT_RUN

真实 WM_CLOSE 两路（成功/失败保持打开）、真实系统保存对话框、Release bundle 与
净机说明、整体独立审查与 FINAL_GATE 收尾。`synthetic_job` 等 M1 探针面保留未清理。
