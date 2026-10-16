# Kimi M4 接续：关闭与导出正确性

2026-10-16，接手基线 d426219（Kimi 已提交 M4；原实现和旧日志保持）。用户要求检查 Kimi 最新工作并继续。本切片不进入 M5，不接作者库。

## 已确认问题与要求

1. workbench_app.dart 的 AppLifecycleListener 是 late final 懒初始化，只在 dispose 引用，正常运行没有注册。initState 必须实际创建监听器。监听回调使用有 MaterialApp/Navigator/Localizations 的 context，State.context 在 MaterialApp 外侧不能用于本地化或 showDialog。实际退出请求需等待成功保存，失败保持窗口+内存稿。
2. RecoveryExportFlow.run 返回 void，调用者无条件弹出 exportDone/仍然退出，即使取消或写出失败。返回明确成功/取消/失败结果，仅 verified success 能解锁导出后退出；普通导出入口保留反馈。导出期间新编辑必须冻结或重新验证导出与当前 memory sequence 一致，避免“导出后退出”丢掉导出后新输入。
3. 重复退出/对话框只能一个；busy 期间退出等待当前合法操作完成再走关闭屏障，不能把 busy=false return 当存储失败，不能跳过晚输入；失败后的 retry 可再次失败并继续可见。所有异步 Future 错误受控，mounted/context 用法正确。
4. restoreSession 和 seedDemo 也统一忙屏障，避免与导航/关闭交错。偏好写入必须单飞 drain：当前 _flushPrefs 只写一次，不会等在途或循环追平；导航可能在新偏好尚未保存时切走。保存失败保留原身份/正文/prefs。针对定时器与 barrier 并发、await 期间 scroll/write 的精确竞态补测试。
5. 检查 _openWork 在 loadDocument 失败时先改 currentWork/目录但 editing仍旧章的问题；失败应保持一致身份/正文，不能旧正文挂到新作品。添加失败加载与恢复/导航并发回归。
6. 生产模块<=400行、函数目标40/上限60有效行；当前 workspace_controller 已超限，合理拆分（part/private collaborator可）同时保持现有公开接口和ChangeNotifier/constructorDI。新文案全ARB en/zh-Hans，用户正文不normalize/翻译。
7. 恢复导出按 workId+documentId 过滤内存稿；当前 drafts仅按documentId，测试跨作品相同chapterId也不得串稿。恢复导出默认文件名的中文后缀当前硬编码，需要本地化。

## 验证与工作规则

- Windows pwsh；仓库 D:\MyAgent\paraselene-flutter；分支codex/flutter-migration-20261015。原 paraselene-work只读，rust/core/**不改，禁止作者DB/凭据/模型请求。
- 读AGENTS.md、docs/evidence/m4/{UI_INTEGRATION_BRIEF,FINAL_GATE_BRIEF}.md及当前editing_session/controller/app/export。
- 先通过针对性 controller/widget tests验证以上问题，含实际 AppLifecycleListener framework exit signal测试（不只controller.closeBarrier），取消导出不得出现成功/退出操作，失败重试/重复退出。可注入 repository/save gateway，原生操作保持真实实现。不能让widget替身冒充实际Windows关窗验收。
- 只本切片生产修复与测试；真正Windows X/Alt+F4与系统保存对话框由root后续验收。不得删除现有固定ownedstore或运行会删除它的m4_app_test；它现在可能含用户本轮合成编辑状态。新测试独立synthetic目录或内存fixture。
- 固定D:\flutter_sdk\flutter\bin\flutter.bat、Dart3.8.1；SDK独占槽位归你。当前权限workspace-write/auto_review；必要SDK/cache写入失败时用require_escalated+明确justification申请自动审查（不重复盲试）。日志只新建m4-close-*，不覆盖旧PASS。
- 遵守Context7 resolve→query获取SDK API文档，结合固定SDK源码。仅缓存依赖不加框架迁移。
- 不派实施子代理，不commit；报告docs/evidence/m4/CLOSE_FOLLOWUP_REPORT.md写具体改动/测试命令结果/未验收项。完成短回复并释放SDK槽位。
