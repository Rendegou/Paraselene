# M4-4 / M4-5 工作台接线实施合同

此切片在 SaveCoordinator 与 owned-synthetic 持久化独立审查通过后实施。只实现 M4，不做 M3 生产编辑器/M5 AI/作者数据迁移。

## 设计与接口

- Windows / pwsh；固定 Flutter 3.32.1，仓库 AGENTS.md 必须遵循。现有 ChangeNotifier/Listenable 和 constructor DI，不迁 Riverpod/Drift/GoRouter。
- `WorkspaceRepository` 已提供全部章节/作品/版本/工作区 API；`domain/editing/save_coordinator.dart` 提供 350ms 防抖、CAS、flush/retry/hydrate/release、loadedStates。业务状态保持 UI 不依赖生成 FRB 类型。
- 默认应用用 `RealWorkspaceRepository.openOwned()`；原临时 open 用于旧 probes/tests，不能在启动失败时降级假仓库。合成模式仅显式注入。
- 每次只加载当前章节正文，导航后释放旧 clean 槽位；不能整部作品正文驻留全局。元数据列表与正文分离。

## 控制器屏障

- 切章/切作品/刷新/创建/归档/恢复/确认/回滚/关闭前等待当前相关保存及 UI prefs。失败保留当前身份、正文、revision，错误与 retry/export 始终可达，不能清空后再尝试。
- 快速导航/晚响应只能应用到匹配身份+generation；保存回执不能覆盖后来输入。明确 busy 状态和交互策略；不能让待切换输入写到下一章。异步每个 await 后检查 generation/身份/生命周期。
- 作品创建、章节创建/改名/重排（全集）、归档/恢复均提供可操作入口。失败不显示成功；归档只处理元数据，不丢版本。
- 确认流程：flush→prepareConfirmation→显示返回的精确 body→用户决定→原样送回 token。预览期间新的输入必须有明确屏障或使核对失效，不能另 prepare 静默确认未展示内容。
- 确认后编辑稿保留且 revision rebase；回滚则删除编辑稿。操作后重新 loadDocument/hydrate，目录 head/版本列表同步；再输入用新 CAS。
- 可预览历史版本的精确正文；回滚前明确展示目标和对当前编辑稿的影响。
- 稳定失败码驱动 localized 文案；保留技术 ASCII code，不做中文文本判错。`durable_save_failed` 提示导出后重新打开，不能自动 reload/掩盖未持久状态。

## 临时编辑与多语言

- 简易 TextField/EditableText 明示临时编辑面，不宣称 20 万字性能。保持 TextEditingController 生命周期/选区/composing；不能在每次保存状态通知中重设全文，不得 normalize/trim 作者正文，空稿可保存。
- UI en/zh-Hans ARB +metadata，所有新增用户文案走 AppLocalizations，包括表单校验、对话框、原生导出标题、恢复状态、保存状态 dirty/saving/saved/conflict/error、旧 base 提示。
- UI locale、正文/作品语言、输出语言独立，切语言不改变正文/身份/选区；未发布语言不能伪装支持。保留 RTL/pseudo/textscale/窄窗可操作性。
- 不要把实现细节或技术架构文字堆入主流程，除必要的临时/合成数据说明。

## UI 偏好与冷恢复

- 最近作品与每作品 chapterId/wide/scrollTop 使用已有 schema；冷启动从最近成功选择恢复，章节不可用时安全选择活动章。损坏 prefs 可见警告并合理回退，不能覆盖作者正文。
- 滚动位置 finite/fractional、0..10M；保存偏好失败同样阻断导航/关闭。启动恢复位置要等待布局完成，切章后旧滚动回调不可写新章。
- 本 slice 只用现有 prefs schema，不把 UI locale 混进作品语言或更改 schema。

## Windows 关闭与恢复导出

- 使用 ADR-004 已核查的 `AppLifecycleListener.onExitRequested`，实际 WM_CLOSE→可取消 request→等待 flushAll + UI prefs + repository.close→成功 exit；失败 cancel 且保持窗口/正文及 retry/export 入口。
- busy/重复关闭请求串行共享屏障；失败后重试不能复用 permanently failed Future。dispose 不能被当作保存屏障，不能悄悄扔掉 dirty text。用户授权退出前不能释放 DB。
- 导出通过注入 gateway 使用 Windows 原生保存对话框（实现可为 runner MethodChannel/IFileSaveDialog 或精准 Dart FFI common-dialog，不新增无缓存包）。实际文件写入 UTF-8，read-back 精确验证后才显示成功；取消不显示成功。
- 恢复导出优先当前内存未保存稿，按当前目录逐章读取其他正文，读失败逐章列出 omitted/count 并明确部分导出；不能因其他章失败使当前稿导出失败。参照原端只读 `src/features/studio/native/exportSnapshot.ts`。明确范围/位置/成功，不把恢复稿叫全库备份，不包含讨论、请求或作者密钥。写出后可提供明确“导出后退出”操作，必须用户操作触发，绝不能静默丢掉 dirty 后正常退出。

## 验证和限制

- 有意义的 controller/widget tests：保存中继续输入、空正文、两作品两章、快速导航旧响应、失败不切换/不关闭、重试、confirm displayed-body/token、confirm rehydrate/rollback freshCAS、归档恢复/重排、偏好失败/冷恢复、导出取消/失败/UTF8readback、重复退出。
- 原 `m2_repository_test` 的 loadBody 替身适配 loadDocument 后保留原竞态意图。M2 widget/integration 的 SelectableText helper 要适配实际编辑器，不能删除断言或把主 UI 固定成旧预览骗过验证。
- 真实字体 M2golden 因 UI 改动时按 run-goldens-rebaseline skill 有意更新并记录，不能盲目基线漂移。保留288布局矩阵实际覆盖新 UI。
- 真实 Windows 输入/关闭/重开与 check-m4 gate 在 M4-6 统一执行；本切片 unit callbacks 不能称作真实关窗验收。
- 生产模块 <=400 行，函数目标40/上限60有效行，合理拆分 controller/actions/session/editor/dialogs/gateway。
- 单 SDK 槽位；日志仅 `docs/evidence/m4/checks/m4-ui-*`，不覆盖旧 M1/M2。报告 `docs/evidence/m4/UI_INTEGRATION_REPORT.md` 记录命令/结果/剩余 NOT_RUN。不要 commit/并行派实施代理。
