# M4-3 保存协调器

状态：实现与定向验证 PASS；未声称本切片完成真实 SQLite、Windows 输入或窗口关闭验收。

生产代码位于 `apps/desktop/lib/domain/editing/`，仅依赖 `dart:async` 与无 Flutter 依赖的 repository 合同。未改 widget、controller、repository、native 或 ARB。

## 接口

- `SaveCoordinator(WorkspaceRepository)` 或 `SaveCoordinator.withSave(SaveDocument, schedule: SaveScheduler?)`。
- `hydrate(ChapterDocument)` 安装干净快照并递增 generation。
- `edit(workId, documentId, body)` 同步保留原始正文，默认 350ms 防抖。
- `getState` / `stateFor` 与 `subscribe`（返回退订函数）。
- `flushDocument` / `flushAll` 等待最后一次输入及 flight 结束；失败以 `WorkspaceFailure(code)` 阻断屏障。
- `retryDocument` 显式重试，保持失败时 CAS revision；不会 reload 或自动覆盖远端。
- `releaseDocument` 要求干净、无 flight、无订阅；`dispose` 要求全部干净且无 flight，否则抛错并保留正文与定时器所有权。
- `loadedStates` 为恢复导出提供已加载槽位的不可变快照；`listenerErrors` 提供订阅者异常诊断，不把 UI 异常误归为数据库失败。

`SaveState` 含 identity/body/revision/baseHead/head/hash/generation/editSequence/savedSequence/dirty/status/errorCode。编辑后旧 hash 清除；Rust 回执提供 hash 权威值。状态错误码使用 repository 稳定码；未知异常映射 `save_failed`，非法回执 revision 映射 `invalid_save_reply`。`durable_save_failed` 保留正文及 revision，进入 error；会话重开/导出策略由后续控制器处理。

## 证据

- 原端只读参考 `saveCoordinator.ts` 与 8 组测试，复刻 8 组场景。
- 额外 10 组：虚拟调度器精确防抖、定时器错误无未处理 Future、flush 重入、最终回执监听中继续编辑、flushAll 重查、订阅异常隔离、三类非法回执及无歧义组合身份。
- `checks/m4-3-tests.txt`：18 tests PASS。
- `checks/m4-3-analyze.txt`：定向 analyze 无问题。
- `checks/m4-3-format.txt`：5 files，0 changed。

测试使用可控 Completer 和虚拟毫秒调度，不依赖 sleep，不把受控保存替身称作磁盘/FFI 故障注入。

## 修改文件

- apps/desktop/lib/domain/editing/save_coordinator.dart
- apps/desktop/lib/domain/editing/save_state.dart
- apps/desktop/test/domain/editing/save_fixture.dart
- apps/desktop/test/domain/editing/save_coordinator_test.dart
- apps/desktop/test/domain/editing/save_coordinator_race_test.dart
- docs/evidence/m4/SAVE_COORDINATOR_REPORT.md 与 checks/m4-3-*.txt

## 实际命令与结果

工作目录 D:\MyAgent\paraselene-flutter\apps\desktop，全部使用 pwsh：

```powershell
& D:\flutter_sdk\flutter\bin\flutter.bat test test/domain/editing --reporter expanded
& D:\flutter_sdk\flutter\bin\flutter.bat analyze lib/domain/editing test/domain/editing
& D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe format --output=none --set-exit-if-changed lib/domain/editing test/domain/editing
```

最后测试 18/18 PASS（exit 0）；analyze 无问题（exit 0）；format 5 files 0 changed（exit 0）。最后一次测试增加了观察者诊断为空的外层断言，确保回调里的 flight/release 断言不会被异常隔离机制掩盖。

## 已知限制

仅状态机控制后端验证，未运行本切片真实数据库或 Windows UI。加载槽位由控制器按导航释放；协调器不会加载其他正文。显式 retry 可能再次遇到 durable_save_failed，应用层需提示恢复导出和重开会话。监听器异常通过 listenerErrors 供控制器诊断；持久化正确性不依赖 UI 回调成功。

## P2 复审修正：重入发布顺序

确认缺陷：旧 _publish 保存一次 state；监听器 A 在 saved 回调中同步 edit，监听器 B 会先收到嵌套的新正文，随后收到外层旧正文。

已修复：每次调用下一位监听器前检查捕获快照与当前 slot/state 身份；发生重入更新时停止旧轮广播，由嵌套发布完成最新状态通知。同时跳过已退订监听器。

新增双监听器受控回归：精确检查 B 的正文、editSequence、status 顺序，没有旧 submitted/saved 回弹；检查 listenerErrors 为空。定向全套现在 19/19 PASS；同样命令 analyze 无问题，format 5 files 0 changed。日志更新于 checks/m4-3-{tests,analyze,format}.txt。未改公共 API。
