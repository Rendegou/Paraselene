# 幻月：Flutter Desktop 项目审计、目标架构与迁移计划

日期：2026-10-15（Asia/Shanghai）。状态：**PLANNED / 仅规划完成，不代表迁移或运行验收通过**。

> 2026-10-18 接续说明：本文前十二节保留初次审计与估算时点；其中“本轮未创建 / 全部 NOT_RUN / 下一步 M0”是历史规划状态。后续已建立独立 Flutter 工程并实施 M0–M4 的部分工作。当前进度以目标工程 `docs/progress.md` 及 `docs/evidence/PROGRESS-REVIEW-20261018.md` 为准；本次新增的自定义标题栏计划见第 13 节，不代表已实施。

当前工程：`D:\MyAgent\paraselene-work`；分支 `codex/client-mvp-20261012`；审计时 HEAD `c64e88afd4787272952ef917f54f8e7e610621c2`。HEAD 不包含大量既有修改，不能单独作为迁移基线。初次检查有 176 行 dirty/untracked 状态，完整路径记录见 `ORIGINAL_GIT_STATUS.txt`。

规划目录：`D:\MyAgent\paraselene-flutter-migration`。未来目标：`D:\MyAgent\paraselene-flutter`，本轮未创建。未修改原项目源码/文档/看板，未 reset、清库、同步 `D:\paraselene`、构建或操作原生窗口、读取作者 DB/Key、发起真实模型请求。用户随后明确授权安装三个技能项目；技能安装是本轮独立于项目审计的已完成操作。

## 1. 结论与决策状态

1. **保留 Rust 领域核心和 SQLite 权威存储，重建 Flutter 展示层。** 不把数据库、patch 采纳、外发许可复制成一套 Dart 业务实现。`crates` 保持 rlib；未来增加独立桥接 crate，不能把原 Tauri crate 直接改成 cdylib。
2. **条件推荐 flutter_rust_bridge（FRB）作为 Rust/Dart 桥接。** 必须先通过 Windows DLL、运行时、取消、内存和安装目录探针。C ABI + Dart FFI 是受控备用方案；Rust sidecar 是 DLL 工具链无法解决时的后备，不默认引入本地 HTTP 服务。
3. **CodeMirror 替换是迁移的首要产品风险。** Flutter `TextField` 或富文本包不能直接视为替代品。先验证原生文本输入与稳定段下组件槽位的组合；未达标就停在 spike，保持旧应用可用，不为了迁移降级选段、IME、撤销或长章能力。
4. **多语言从基础合同开始。** UI locale、作品/章节语言和模型输出语言互相独立；中文与英文为首批验证语言，RTL 与混排为结构门槛，最终发布语言清单仍待产品确定。不增加自动翻译或模型请求。
5. **逐功能模块切换，禁止双客户端同时写同一作者库。** 开发/验收使用独立合成库和应用标识。最终数据接管采用停写、备份、校验、单写者锁和显式切换。

## 2. 审计边界、证据与可信度

### 2.1 扫描方法与附件

- `SOURCE_INVENTORY.csv`：559 个去重项目文件的相对路径、类别、大小、行数、SHA-256、处理建议。449 个文本文件全文词法读取，110 个资源或元数据项只检查文件元数据/哈希；不将资源哈希视为视觉 QA。
- `FILE_MAPPING.csv`：429 个源码、测试、壳层或资产文件的逐文件初步去向。目录/文件名是**拟定责任归属**，不是已创建文件，也不是承诺机械一对一翻译；下文人工模块映射优先于自动命名。CSS 必须合并提炼 token，不逐文件生成重复主题。
- `SOURCE_SYMBOLS.txt`：公开接口、命令、schema、State、Channel、事件、取消/坐标等词法定位。词法命中数量不能当实际测试通过数量。
- `audit-source.ps1`：本轮可复跑的只读扫描脚本；仅输出至规划目录。`ORIGINAL_GIT_STATUS.txt`：审计中保存的原树状态；最终完整性校验见 `AUDIT_VERIFICATION.md`。
- `SKILLS_INSTALLED.json` / `SKILLS_USAGE.md`：安装来源、固定 commit、技能清单与实际应用范围。

纳入：`src`、`crates`、`src-tauri/src|tests|examples|learning|icons`、`scripts`、`tools`、`public`、历史`spikes`自有脚本、`.impeccable`存在的项目文件、项目根配置，以及授权项目 `docs` 中的规范/计划/证据。已重点人工阅读活动入口、native adapters/session/save/thread/generation、CodeMirror setup/slot/gutter/anchor、Rust DB/migrations/working edit/generation/commands/export/credentials 的实现，其他自有文本做全量词法与接口扫描；**不声称所有代码逐行人工审查或完成独立 bug review**。

排除：`.git` 内容、`node_modules`、Cargo target、dist、包管理缓存、生成 schema、`.client-mvp-tests`、安装目录实际数据、作者导出包/作品正文、`.env`、认证/Key/私钥文件及外部素材。未跟随规范中指向私人作品的路径。锁文件和随应用分发的`public/learning/pyodide`供应商运行资源仅保留元数据/哈希，不计作自有源码审查；首次词法索引误包含后者，最终索引已排除其内容。路径统一分隔符后去重，排除了嵌套扫描造成的资产重复计数。第三方许可证只依据项目已有说明和本轮公开仓库，不构成完整许可证审计。

审计使用 Windows PowerShell 7 `pwsh`。个别早期 `rg` 调用用了 Windows 不展开的 `*.test.ts`/`working*` 路径，已改为目录 + `-g` 和白名单脚本覆盖；这些失败不算扫描成功。未执行旧测试运行器，它会在原工程创建/清理 `.web-test-tmp`；未运行可能访问凭据/模型的 examples 或全 workspace 测试。

### 2.2 规范与现实差异

已读取 AGENTS、README、当前方向、看板、项目地图、代码规范、DESIGN、PRODUCT、小说入口、client-mvp 计划/合同、复用清单、GNU ADR、C 与交互最新证据及关键源码。用户本轮只读边界覆盖 AGENTS 中“先写看板/结束更新看板”的常规流程，本轮状态只写独立目录。

- `StudioApp.tsx` 按 native runtime 且非 design 路由进入 `native/NativeStudioApp.tsx`；浏览器/设计路径仍走 Notebook 预览。地图/PRODUCT/方向中“尚未接 SQLite”的段落是旧状态，不能用作当前实现结论。
- NativeSession、SaveCoordinator、PersistentThreadRegistry 已承接按章保存、线程草稿、作品切换和退出屏障；`studio_workspace.rs` 有正式作品、归档、最近作品、UI session、确认/回退入口。
- `studio_generation.rs` 已接一次性预览、发送、取消、持久操作、采纳/拒绝；`novel-core/working_*` 复核 revision/head/hash/资料。代码存在与合成测试不等于真实 DeepSeek 验收。
- C 证据写 95 前端测试、独立审查进行中；用户交接报告 96 测试通过、审查完成。本轮源码确认 `operationModel.ts` 以 operationId 还原服务端操作，`persistentThreadRegistry.ts` 排除带 operationId 的 requests/candidate；`usePersistentThreads.test.ts` 存在“20 万字 + 4 次操作 + 下一份未发草稿 + 重开”回归。**96 通过属于交接状态，本轮未复跑**。
- 原生 A/B 仍 PARTIAL；交互证据有 150% DPI、焦点、同逻辑行两标记、切章/重开、版本回退及失败恢复导出的局部验证，不外推完整 IME/DPI 矩阵。
- 用户交接确认独立标识 `dev.paraselene.acceptance20261014` 的 debug NSIS 安装包在 `D:\MyAgent\paraselene-installed-acceptance` 因缺 `WebView2Loader.dll` 启动失败。本轮未检查/启动该安装产物，记录为**交接确认 FAIL**，不采用旧“构建中”或“构建成功”冒充可发布。迁移不接着修该包。

## 3. 当前架构与资产盘点

### 3.1 活动业务路径

`App → StudioApp → NativeStudioApp → NativeSession/adapter → lib/ipc.ts → Tauri commands/State → Rust crates → SQLite / 官方 DeepSeek`。

`NotebookWorkspace` 复用活动写作组件。`ParagraphEditor + editorSetup` 管编辑器实例、历史、选择与外部变更注解；`editorSlots` 用 StateField/块 Decoration 和稳定 Portal 挂段下线程；ResizeObserver 请求重测量；`editorMarkers` 按逻辑行分组 gutter，保留每条讨论入口；`threadModel` 依据事务 ChangeDesc 映射锚点。资料装饰来自 `editor/referenceExtension.ts`。

原生视图只装当前章正文，其余章保留摘要并按需加载。预览 localStorage 的 `StudioProject`、design fixture 与 SQLite 权威严格分开；不得把整个作品正文塞入 Flutter 全局状态，也不得将浏览器预览 DTO 原样当正式备份格式。

### 3.2 纯 Rust 能力

- `memory-core`：SQLite 单连接 Mutex、事务、迁移 v1–v12、FTS5/触发器、四空间、导入与指纹、记忆与旧想法、小说目录/working copy/不可变版本/patch/threads/operations/lore/出处/派生摘要重建、学习记录。
- `novel-core`：选择校验、context 预算与 manifest、检索/摘要材料、edit/patch/diff、质量与设定冲突、旧生成/跑团、working edit/working generation/working output、流收集与取消。
- `llm-core`：CloudGate、PreparedChat、PreviewLedger、官方 DeepSeek 预设、reqwest + rustls、SSE 分片和错误映射。当前 working-edit 在 Rust 内收集完成结果，**不是已向活动 UI 实时推送 token 的功能**；旧 llm_chat_send 的 Channel 流须单独保留映射。
- `character-core`：角色配置及分享边界；`learning-core`：练习口令与协议，不是用户代码执行器。这两项暂不进入小说迁移主线，但源代码和数据不能删。

### 3.3 Tauri 耦合与 Windows 能力

`NovelState` 管 Arc<Database>、selected workspace、preview/rpg/working-generation Mutex；其他 Memory/Idea/Import/Llm/Character State 由 `lib.rs` 注入。Commands 既有薄转发，也有作品校验、上下文组装和模型流程编排，不能只删宏后直接导出。

`AppHandle/WebviewWindow` 用于工作台/旧窗口、托盘、事件、数据目录、系统文件对话框；`tauri-plugin-dialog = 2.7.3`；`lib/ipc.ts` 是唯一前端 native 封装，含 invoke、listen、Channel、窗口关闭守卫。关键事件有 `studio-exit-requested`、`studio-open-work`、旧 `novel-work-changed`、`character-changed`，逐个登记来源、订阅生命周期与替代物，不视为 Dart 事件原生可用。

Rust `keyring` 凭据服务名 `dev.paraselene.app`、账号 `deepseek-api-key`。本轮只读常量和实现，未调用 `has/get/set/delete`。未来沿用语义、运行时读取不回传明文；测试独立服务/账号，不碰作者凭据。Key 初次输入可短暂经过设置 UI，禁止持久化/日志/事件/自动读取展示。

导出：`studio_export.rs` 在系统保存对话框选择路径，16 MiB 字节上限，校验 JSON，净化 Windows 文件名/设备名，同目录临时文件 + sync + rename，取消/成功/失败明确。`exportSnapshot.ts` 可在保存失败时保住当前内存稿，其他章读取失败有 omittedChapters；必须显示不完整，不能称完整备份。

学习壳使用 `learning-sandbox` 自定义协议、Worker/Pyodide 资产和隔离验证。原配置 CSP/能力集只适用于 WebView；Flutter 不是自动继承沙箱或权限。未来恢复此功能须另立威胁模型与隔离验证，不能直接原生执行 Python。

### 3.4 资产、构建与历史模块

React 18、TypeScript、Vite、CodeMirror 6；前端由 pnpm 锁依赖。Rust workspace 含 5 个核心 crates、Tauri 和 metrics 工具，Cargo 锁保持。现有质量门包括 TS/Rust AST、IPC 边界、类型、前端行为、领域测试、Clippy；历史 cargo fmt 和 3 个 hook 基线债务不能被迁移清零隐去。

字体有本地 Noto Serif SC Regular 与 Noto Sans SC Regular/Medium/Semibold WOFF2 及 OFL；Flutter 需核对目标引擎支持与字体字形，优先从合法源字体生成/取得 TTF/OTF 并带许可，不假设 WOFF2 可直接复用。图标、pet 图片和序列、旧学习资源登记保留；逐项区分 Flutter 可用格式、需转换与延期。

历史清单：LegacyApp、MemoryPage、IdeaPage、TargetPage、ImportSection、旧 NovelWorkbench 的 drafts/逐块 patch/版本/lore/RPG/open questions、Studio/SidebarWorkbench/AgentPanel/KnowledgePage 试稿、桌宠/角色包/托盘/quiet、学习窗口与 Worker、导入扫描/搜索/记忆来源纠正删除导出。**小说主流程优先；延期不等于删除或已被新界面覆盖**。旧小说逐块采纳和 RPG 等可用性按实际证据列为历史能力，不能默认新单候选 UI 已完整等价。

## 4. 目标架构与模块文件对应

### 4.1 拟定目录与依赖

未来独立目标目录内部：

```text
paraselene-flutter/
  lib/main.dart, bootstrap.dart, app.dart
  lib/ui/core/theme/                  DESIGN tokens、字体和基础控件
  lib/ui/features/{studio,writing,cowrite,lore,settings}/
    views/, view_models/              小 Widget + 不可变视图快照
  lib/domain/{models,editing,cowrite}/  纯 Dart 坐标/编辑状态合同
  lib/data/{models,repositories}/      正式 DTO、repository 单一写路径
  lib/native/                         Rust 桥、文件对话框、窗口/事件接口
  lib/l10n/                           ARB、格式化与错误码翻译
  assets/{fonts,icons}/
  rust/core/                          固定快照复用的原 crates
  rust/application/                   从 Commands 抽取的无 Tauri 应用服务
  rust/bridge/                        唯一 cdylib/FRB 接口与版本握手
  windows/runner/                     窗口关闭拦截和最少 Win32 适配
  test/, integration_test/, scripts/, docs/evidence/
```

View → ViewModel → Repository → NativeService → Rust application → Rust domain/store；Windows UI 能力走独立 WindowGateway/DialogGateway。业务核心不反向引用 Flutter/Tauri；Widget 不创建数据库、网络客户端或桥接句柄。官方技能的 MVVM/Listenable 与 Repository 分层为首选，先用 ChangeNotifier/Listenable + 构造注入；不因社区技能自动引入 Riverpod、Drift、GoRouter、Freezed 全套依赖。后续确有 provider 生命周期收益可单独 ADR，不改变 Rust 权威。

Rust 复用以**固定源码快照 + 原路径/许可证/哈希清单**进入新工程，避免构建随原 dirty tree 漂移；本轮不复制。抽取应用服务先在新工程完成，不强迫原项目协同改动。共享上游/回合并另行安排。源与目标双方的契约变动需同一变更交付，生成绑定固定工具版本。

### 4.2 人工确定的模块映射（CSV 为每文件追踪附件）

- `App.tsx`、`StudioApp.tsx`、`NativeStudioApp.tsx` → `main/bootstrap/app`、`studio/views/workspace_picker.dart`、`studio/view_models/workspace_view_model.dart`；真实/合成模式在 composition root 注入，发布不自动回退 fixture。
- `nativeSession.ts`、`workspaceAdapter.ts`、`documentAdapter.ts`、`uiSession.ts` → workspace/document repositories + `studio/view_models/native_session.dart` + UI session store。保留目录全集重排合并、当前章懒加载、最近作品、切换屏障。
- `saveCoordinator.ts`、`threadAdapter.ts`、`PersistentThreadRegistry` → `domain/editing/save_coordinator.dart`、`data/repositories/thread_repository.dart`、`cowrite/view_models/thread_registry.dart`。测试分别落 `test/domain/editing`、`test/data`、真实 bridge integration。
- `ParagraphEditor.tsx`、`editorSetup.ts`、`editorSlots.ts`、`editorMarkers.ts`、`useInlineEditorBridge/useInlineSlot/useEditorEffects/useSelectionPosition` → `writing/editor/{editor_controller,edit_transaction,anchor_mapper,inline_thread_layout,discussion_gutter,selection_overlay}.dart`；新实现必须替代 ChangeDesc/Portal/DOM 测量，不能照抄为 Dart。
- `threadModel/threadTypes`、`cowrite/model/contracts`、`editor/referenceExtension` → `domain/cowrite/{thread,target_snapshot,anchor,reference_snapshot}.dart` 与 editor decorations；共享测试向量由现有 tests 提取合成材料，不拷贝作者数据。
- `NotebookApp/Surface/Manuscript/Sidebar/Toolbar/Menus/ChapterHeading/ChapterSearch/useNotebook*` → 写作 Views/布局/controller；`Notebook*css`、`NativeStudio.css` → 统一主题 token/组件样式，字号、间距、断点保留。
- `ThreadPanel/Discussion/Composer/Candidate/Versions/DiscussionIndex`、`useThreadRequests/Candidates/Store` → cowrite Views/ViewModels；段落讨论/全章抽屉/历史重开/未发草稿/候选比较和撤销均独立跟踪。
- `generationController/Contracts/useNativeGeneration/operationModel/GenerationPreview` → GenerationRepository + `cowrite/view_models/generation_controller.dart` + preview/review Views；author snapshot 与服务端 operations 分源合并，不能回写派生请求。
- `nativeLore/loreAdapter/NativeEntityDetail/NativeSourceLinks/SourceVersionText/sourceCoordinates`、`ReferenceCard/Overlay/useReferenceInspector/useSurfaceReturn` → LoreRepository、SourceRepository、lore Views 和 FocusReturnController；旧版出处按版本显示，stale 明示。
- `WorldMap/MapPosition/EntityDetail` → `lore/views/world_map.dart` 与独立场景坐标/手势控制。当前 NativeLore 只投影 character/location/world，related 为空且未见正式坐标写入链路；保留预览地图调整为已存在交互，标成**正式持久化缺口**，不悄悄取消，也不宣称原库已有关系/坐标。未来若补齐需独立 schema ADR 和验收，非纯框架迁移顺带改库。
- `exportSnapshot/projectActions/useStudioExport/NativePersistenceNotice` → ExportRepository/RecoveryExportService + `lib/native/file_dialog_gateway.dart`；写文件校验/原子替换抽取至 Rust application，系统路径由对话框提供。
- `src/lib/ipc.ts` → `lib/native/core_service.dart`、generated FRB bindings、typed DTO/error；旧函数名清单保留，按 capabilities 而非一个万能字符串 invoke。`src-tauri/src/commands/{novel,studio_workspace,studio_generation,llm,key,studio_export}.rs` → 对应 Rust application services；crate 核心 API 保留。
- `src-tauri/src/lib.rs/main.rs/quiet.rs/learning_window.rs` 与 tauri config/capabilities → Flutter runner/bootstrap、WindowGateway/TrayGateway/数据目录策略；quiet/learning 延期，不复制 CSP 到无 WebView 的 Flutter 作为安全保证。
- `features/novel/**` 与其他 legacy 组件 → `docs/migration/legacy-register` + 后续可选 feature 模块，现有测试意图继续登记。`crates/{character-core,learning-core}` 保留，当前不接 UI；`memory-core` 的导入/搜索/记忆四空间数据完整留在库中。
- tests → 按层转写 Dart tests、Rust 原有测试直接复用、Tauri examples 意图转真实 Flutter Windows integration harness；源码中的 paid/keyring examples 绝不能被通用 CI 自动执行。
- `scripts/check-quality.ps1`、TS/Rust metrics 配置 → 新工程 `scripts/check-quality.ps1` 的原生 pwsh 入口；Dart 使用 analyzer/formatter 和有根据的复杂度检查，Rust 保留原阈值。前端历史 TS 检查属于旧应用回退基线，不能用“不再编译 TS”表示原问题已解决。

### 4.3 复用/抽取/重写/验证清单

直接复用并重跑：五个 Rust crates 的无 Tauri 代码、SQL 迁移/约束、patch/出处/版本算法、SSE、PreviewLedger、Rust 合成测试、可兼容格式资产与许可。直接复用不代表零构建改动。

必须抽取：Commands 中工作区选择/归属检查、SettingsGate、确认稿上下文/设定冲突、生成编排和取消收尾、keyring adapter、export 文件写入、导入许可状态。保持原 API 行为并引入 typed error，不把 Tauri State/AppHandle 放过桥。

必须重写：React hooks/JSX/CSS、DOM Portal/Decoration、菜单/focus/selection/shortcuts、窗口/托盘/关闭/对话框、ipc transport、localStorage 预览、TS 状态协调器语言实现。复用 TS 测试语义而非运行 JS 当迁移完成。

必须验证：编辑器替代、IME/Unicode/bidi、字体格式与覆盖、FRB/DLL/运行时、GNU→MSVC 核心编译、SQLite 文件和 WAL、凭据兼容、DPI/多显示器、文件覆盖和错误、长章性能、旧功能可达性、新旧写者互斥、多语言文案与模板完整性。

## 5. Rust 桥接选型与边界合同

### 5.1 方案比较与推荐条件

**FRB（条件首选）**：可生成 DTO、Future、Stream 与 opaque handle 绑定，减少手写对象编码与释放代码；代价为 codegen/版本组合、Rust async runtime、生成物审计和 DLL 构建。其 async 支持只解决调度，不自动提供业务取消、幂等或线程归属；取消必须显式 operationId API。长字符串通常仍有拷贝，不得假称零拷贝。先导出少量 CoreSession 方法，不能将整个 Database/Mutex/所有领域类型自动暴露。

**稳定 C ABI + Dart FFI（备用）**：`extern C` 导出 ABI version、open/close、request、cancel、poll/port events、free-buffer 等有限能力；DTO 用带版本的 UTF-8 字节协议，长度独立，禁止以 NUL 终止假定正文。优点是边界小且可控、DLL 诊断清晰；代价是句柄表、线程调度、Dart ports、分配释放、错误 union、序列化/生成和 ABI 兼容全要自建。不能把 Rust ABI、String、Vec、Result、Future 裸暴露给 Dart；ffigen 只对明确 C header 生成绑定。释放必须由分配该内存的 DLL API 完成，不能跨 GNU/MSVC CRT free。

**Rust sidecar（后备）**：Windows 具名管道或受控 stdio 版本协议可保留 GNU EXE；独立进程隔离崩溃、绕开 DLL ABI，但增加子进程监管、消息背压、取消/崩溃恢复、安装更新/身份校验。不开放网络监听、不把正文/Key 写诊断 stdout；不能用无鉴权 localhost HTTP 换取“简单”。

**Platform Channel**：仅窗口/COM 对话框等薄 Windows 接口的备选，不经 C++ 把全部 Rust DB/生成业务重绕一层。**WebView + CodeMirror** 只能作为明确批准的临时混合路线，仍依赖 WebView2/CSP/焦点；不是本计划默认 Flutter 原生完成定义。纯 Dart 重写 Rust/数据库或 Drift 接管现有库被排除，会产生双权威和迁移语义风险。

推荐在 M1 比较可运行证据后锁 FRB；若它不通过，先尝试有限 C ABI 的同等探针；两者均失败则单独 ADR 评估 sidecar。不得因工具链失败切到伪 native stub。所有方案均不意味着现有 Tauri Commands 可以原样调用。

### 5.2 拟定服务与生命周期

- `CoreSession.open(config)` 返回 opaque session；包含 DB、selected work、PreviewLedger、WorkingGenerationState、bounded task registry 和取消句柄；配置显式区分 synthetic/author 数据根和凭据服务名，默认不打开旧作者库。
- handshake 返回 protocolVersion/schemaVersion/capabilities/coreBuildId，Dart 不兼容时禁止写入；work/document/thread/operation ID 及 revisions 用明确非本地化类型。i64 不转 double；nullable revision 和 0 不混用。
- 对外能力：workspace list/create/select/recent；document directory/load/save/archive/reorder；versions confirm/rollback；thread load/save；lore CRUD/confirm/sources；generation preview/send/cancel/list/apply/reject；export；settings/cloud/key status。legacy API 单独 capabilities，不能默默 no-op。
- DB 和 CPU 重活不占 Dart UI isolate；Rust application 使用明确 Tokio runtime 与 blocking executor。不得持 DB Mutex 跨网络 await；取消不排在同一个长阻塞任务后。close 先拒绝新调用，完成保存屏障、使预览失效、取消并等待在途任务、退订事件，再释放 DB/session。
- 所有返回快照默认 owned immutable DTO；borrow/reference 不越过调用生命周期。Rust session handles 在显式 close 后拒绝访问；finalizer 只是兜底，不能承担保存。panic 在桥边界转内部错误且不跨 FFI unwind；释放后事件不访问 Dart 对象。
- event envelope：protocolVersion、sessionEpoch、workId/documentId/threadId/operationId、sequence、kind、payload；订阅可注销，有界队列与背压；terminal 状态不可丢失，进度可合并。重连通过 list operations 恢复持久状态，不回放 paid send。
- `cancel()` Future 只代表取消确认/已终态，不代表后端请求从未抵达供应商；不能承诺取消后零费用。取消、完成、commit 的竞争在 Rust 状态与事务处裁决，UI 不靠 StreamSubscription.cancel 推断网络已断。
- 错误协议为稳定 code + safe params + retryability/operation identity；区分 conflict/stale/cancelled/interrupted/not_found/permission/storage/network/invalid/schema_mismatch。原 commands 多以 String 返回，先在应用边界分类并测试，逐步去掉 Dart 中文字符串 includes 判错。日志不含正文、Key、材料或私人路径。

### 5.3 构建与 DLL 分发门槛

检测到 flutter/dart PATH 分别指向 `D:\flutter_sdk\flutter\bin\flutter.bat` 与 dart.bat；本轮没有执行版本/doctor 或安装编译器，不能宣称环境就绪。当前 PATH 未发现 cl/cmake 不等于机器未安装，后续用 doctor/vswhere 只读确认。

原 ADR 记载 GNU cdylib `export ordinal too large: 90895`，原 Tauri lib 因此仅 rlib；这说明风险，不证明新小桥 DLL 必然失败。Flutter Windows runner 依官方要求验证 Visual Studio C++ Desktop workload/SDK/CMake；建议新工程独立采用 Rust x86_64-pc-windows-msvc，不改变原工程 rustup default/全局工具链。需安装工具时明确范围，不在本轮顺带安装 VS。

M1 验证新 bridge cdylib 只依赖 core/application、不链接 Tauri；核查导出数、架构/ABI、SQLite bundled C 编译、reqwest TLS、DLL 依赖树。GNU DLL 备用仅在 C ABI/CRT 所有权完全隔离后考虑。FRB/工具、Flutter/Dart、Rust、MSVC、pubspec.lock/Cargo.lock、generated build hash 全记录。

发布打包**完整 Flutter Windows bundle**（EXE、flutter_windows.dll、bridge DLL、data、fonts、插件 DLL、VC runtime 按官方要求），不能只发 EXE 或仅本机 PATH 能找到 DLL。Rust DLL 用受控路径解析，拒绝意外 DLL 搜索路径。独立应用标识/快捷方式/卸载目录；干净 Windows 环境、中文带空格路径、非管理员、离线启动、升级/卸载保数据均验收。迁移后若不采用 WebView 插件，不应依赖 WebView2；这一点必须以依赖树和净机启动证据证明。

## 6. 数据、编辑与生命周期不可变合同

### 6.1 SQLite 与版本

保留表结构、ID、schema user_version 和全部 v1–v12 升级顺序。Database.open 会 prepare 并运行迁移，**不能把打开文件误称无副作用只读**。保留 WAL、synchronous=NORMAL、foreign_keys、recursive_triggers（FTS external content DELETE 触发器关键）、temp/cache 设置；完整性检查包含 FTS 真实查询与行匹配，不仅 integrity_check。

working_copies 以 documentId、baseHead、expectedRevision CAS；作者保存与不可变 novel_versions/head 分离。候选采纳只更新 working copy，不自动确认正式版本；确认和回退携 head/revision 与设定上下文。patch 正文+状态必须同一事务，重复采纳、迟到响应、头漂移、同 revision 不同 hash 均拒绝；不能保存成功后另事务补候选状态。

thread schemaVersion=1，work/document/thread 独立 revision CAS；novel_operations(v12) 独立保存 binding/status/output/patchId。作者线程只存作者数据/必要快照，不复制服务端请求和候选；读时按 operationId 派生合并。20 万字四操作后的草稿保存/重开是强制回归，不用提高快照上限掩盖重复持久化。

归档不删版本/讨论/出处；重排遵守作品文档全集，不只提交章节子集。lore type 保留 character/location/world/timeline/taboo/style，confirmed/candidate/rejected、scope、aliases 与不可变 versions 均保留；Native 当前只显示前三类的缺口明确登记，底层其余类型不丢失。

### 6.2 坐标、IME、锚点与撤销

- 编辑器和线程 from/to 使用 UTF-16 code units；Rust SourceAnchor 的 start_char/end_char 是 Unicode 标量索引，Rust bytes 又不同。分成显式类型，边界转换拒绝 surrogate 中间位置；Dart `runes` 只用于标量转换，grapheme 用于光标/用户可见计数，三者不混用。
- 不对正文做 NFC/NFKC、换行、全半角、标点、大小写或 bidi 控制符的隐式归一化；hash/quote/版本基于确切原文。CRLF/LF 既有行为先测再定，不静默改历史绑定。
- 保存完整不可变 target/baseBody；显示 anchor 只由真实 edit transaction 映射。选句改变即 stale，不相似搜索重绑。全文撤销精确回到被冻结 baseBody 时可恢复已知原坐标；恢复依据来自快照相等，不是命中相同引文。
- 同一逻辑行多标记独立可达；关闭线程保留标记与草稿，失效目标仍在讨论历史可重开。段下只展开一处；不能将讨论 Widget/占位字符塞进导出正文、选区坐标、复制或 undo 内容。
- 文本事务注明 user-input/IME/candidate-apply/external-sync/rollback；所有正文变化映射 anchors，只有需要保存的用户/领域动作触发相应写入，避免外部同步 onMap 被跳过或反馈循环。候选采纳形成单一可撤销编辑单元，撤销不把已完成服务端操作重新标成 pending 或重发。
- 原生中文微软拼音至少覆盖组合/选候选/取消、选区替换、连续输入、焦点切换、Enter/Escape/快捷键不抢 composition；日文/韩文作为多语言输入扩展测试。组合范围与持久正文语义需 spike 明确，关窗必须先让输入法提交或由作者取消关窗，不能强制丢 composing。

### 6.3 保存、导航、关闭与恢复

保留同步内存权威、350ms 调度（可配置但须测）、按文档串行快照 CAS。flush 循环覆盖 await 期间新增编辑；冲突保留原 revision，不通过更新期望值静默“重试成功”。只释放干净且无订阅/在途的章节。

切章/切作品/归档/确认/回退先置 busy 并 flush 正文、lore、UI session、线程；失败留在当前工作区，提供重试/导出。正文与线程后台保存互相独立，但退出屏障必须等需要的全部项。旧响应绑定 sessionEpoch/work/document/thread/operation，不污染新页面。

Windows Alt+F4、窗口 X、托盘退出走同一个两阶段关闭守卫：拦截 → 输入完成/flush/cancel policy → acknowledgement → 实际关闭；失败解除 busy、保留焦点/正文并显示不遮挡工具栏的通知。正常退出和崩溃恢复分开承诺；断电只保证最近事务已提交内容，不承诺尚在内存稿自动存活。

失败恢复导出优先当前内存稿，其他章读失败明确列 omitted 及部分成功；系统取消不得显示“已保存”。讨论、请求、候选不进正文 Markdown。现有 JSON 只称导出，未定义完整 round-trip restore 前不称可恢复全量数据库备份。

### 6.4 单写者和回退

M1–M7 仅合成库/授权脱敏副本，独立 app ID 与凭据命名空间。author 数据根必须精确确认，不能仅凭新包名推断旧 app_data_dir；不扫整个用户目录找库。

仅给新 Flutter 加锁不能阻止旧 Tauri。实际接管前：先备份并校验旧数据（含 WAL 一致性策略），停止旧写者并用路径/实例锁证明互斥；若需要旧客户端协作加锁，必须单独授权和交付旧端改动。采用部署级入口互斥和 OS 文件锁/命名锁双重策略，SQLite CAS 仍保留。无法保证旧写者停写就不共享作者库。

M8 优先选择作者显式接管到新独立数据根；保留关闭旧端后取得的一致性备份和恢复步骤。回退不覆盖新端新增稿：先停止两端并导出新写入/备份，再用兼容性证明决定旧端能否打开新库；schema 升级不能反向降级。迁移期不加与框架迁移无关 schema 变更，语言 metadata 若需新表也应独立版本化。

## 7. 多语言设计（本轮新增要求）

**目标是可扩展多语言能力，不是本轮完成所有语言翻译。** 首批验收规划为 `zh-Hans`、`en`；繁体中文、日文、韩文、德文/法文和阿拉伯语等具体发布范围待后续确定。测试可使用伪本地化与 RTL 合成材料，不把伪翻译列为正式语言支持。

### 7.1 三种语言设置分离

- App locale：默认跟随系统，作者可覆盖；BCP-47 language/script/region 匹配，未支持地区按语言/脚本回退到已支持语言。中文默认保持现有界面体验，不能无条件把所有 zh 解析成简体。
- Work/Document language：作品默认语言 + 可选章节覆盖 + mixed/und 状态；正文允许任意语言及混排，不因 metadata 限制输入。UI 切换语言不改正文/资料、hash、anchors、版本、文件名或已存作者草稿。
- Generation language：默认跟随作者明确的写作意图/目标段落，可覆盖；system prompt 和输出语言选择作为版本化材料进入**同一次完整外发预览和一次性许可绑定**。界面切语言不自动重发/翻译，已签发预览不在背后重建消息。

### 7.2 UI 文案、错误与布局

未来 `lib/l10n/app_en.arb` 为 key/placeholder 模板、`app_zh.arb` 为对应中文；明确 script locales 时使用规范文件与 @@locale。配置 flutter_localizations、intl、gen-l10n，生成输出放真实源码目录，`nullable-getter: false`。已装官方 localization skill 的示例含旧 synthetic-package/flutter_gen 写法，**不可照搬**，以选定 Flutter SDK 的当前官方文档和实际生成结果为准。

所有按钮、菜单、Tooltip、Semantics、保存/冲突/恢复/费用提示、默认章节名、空态、对话框标题、导出系统提示都走 ARB；作品已有标题是作者内容不翻译。中文“第N章”默认命名需按创建时 UI/作品语言策略产生，已生成名字不随 locale 自动改。数量与句序用 ICU，ARB key/placeholder/type 完整性单独门禁；不可截断译文来掩盖溢出。

Rust 返回稳定错误码和安全参数，Dart l10n 翻译；不要以中文错误字符串判 conflict。历史持久 error 字符串保持原样可见并标来源，不能改库把旧错误“翻译”导致 schema/审计失真。canonical 时间沿用既有 RFC3339 存储，不按社区“统一 epoch”建议破坏现有契约；仅在展示做 locale/timezone 日期/数字格式化。ID、revision、协议枚举不本地化。

布局用 LayoutBuilder 的窗口约束和 Directional 几何；中文既有 240px 目录、56px 顶栏、760/920 正文宽度和 900/1100/760 断点为基线，英文长标签/伪本地化允许必要弹性与换行。RTL 镜像导航/方向图标，地图地理坐标、作品内容阅读方向和固定语义图标不盲目镜像。UI RTL 与正文 LTR（反之亦然）独立控制，选区/gutter/floating card 的命中遵守实际视觉方向。

### 7.3 文本、字体、统计与搜索

字体本地打包且带许可，核对 CJK/Latin/Arabic 等目标 script 的 cmap、shaping、字重与 fallback。保留中文衬线正文、无衬线工具，不假定一个 Noto SC 字体覆盖所有语言；RTL 正文需要额外合法字体资产及真实排版验证。禁止运行时远程字体请求。

中文“字数”与英文 word count 不能共用一个不解释的计数值。保存/范围仍按原合同，展示可并列字符/词数并说明统计策略；按 locale 做词界/标点/换行属于展示或派生统计，不影响 hash。Unicode61/trigram 检索已有中文限制；多语言大小写、重音、词形和分词改进先用合成题集验证，Rust FTS 作为现有权威保持，不自动新建另一套 Dart 索引。

混排技术 ID/URL 可在展示层添加 bidi 隔离，**不得向作者正文注入，也不得无差别剥除正文里作者已有的 bidi 控制字符**；展示生成的标记不能回存/导出。坐标验证包含组合字符、ZWJ emoji、旗帜、阿拉伯连写和双向段落。

### 7.4 多语言完成门槛

M0 固定 Unicode/locale 合同；M2 起所有新 UI 文案使用 ARB；每个模块同时提供中英及伪长文案/RTL 布局测试。切语言时正文、selection、composition、undo、讨论草稿、已预览模型材料不能丢。正式声明某语言支持前，需要真实翻译复核、完整 key/placeholder、字体覆盖、原生输入法/快捷键、系统对话框/导出与核心工作流验收。系统文件对话框部分文案由 Windows 语言控制，应明确这一点，不伪称应用可完全翻译系统壳。

## 8. CodeMirror 替代 spike 与视觉基准

候选 A：Flutter 自带 EditableText 的可控编辑路径 + 自有事务/锚点/gutter/段下布局，依赖少、行为可控，但全章 TextEditingValue 的开销及在文内插非文本组件需要实测；Overlay 单纯盖住正文不满足段下占空间要求。

候选 B：经过源码/许可证/维护现状验证的文档编辑器（如 Super Editor/Flutter Quill 类）作为 spike 候选，本轮不锁其版本或宣称其 Windows IME/长章已通过。优点是 block/component 扩展潜力；代价是富文本文档→纯文本坐标映射、composition/undo、虚拟化及多语言行为，不能让富文本 delta 成为另一套正文权威。

候选 C：自研虚拟段落编辑器/RenderEditable 组合，控制力高，但跨段选择、IME、无障碍、剪贴板与撤销成本最大；只有前两条失败且估算获接受才进入。对 editor key/state 与 FocusNode/Controller 保持稳定身份，切线程、开资料、换语言不能无故重建编辑器。

spike 使用同一合成矩阵：1万/20万字长章、全作品100万字分章摘要、单逻辑行超长文本、百线程/同行多个、重复引文、空章、全文删除撤销、emoji/ZWJ/组合重音/RTL、CRLF/LF。100万字单章压力测试仅探索不突破现有后端字数上限，不能为测试偷偷放宽 schema。性能目标先采旧版同机基线，记录装载/输入到呈现 P50/P95、内存、滚动、线程开关和切章；暂定预算输入 P95 ≤50ms、单章20万字装载 ≤1s、普通滚动不持续 >33ms，必须 profile/release 实测，若基准不合理在实现前说明再调整。

视觉沿用 DESIGN：paper #faf9f5、frame #f3f4f6、accent #49659c；正文20px/1.85、工具14px，目录240、顶栏56、舒适/宽稿760/920；段下上限 min(420,50%窗口高)、全章抽屉 min(360,45%)、资料卡≤380宽/520高或72%高度。Flutter logical pixels 对照 CSS 像素，100/125/150/200% DPI 与跨屏移动实测；本轮不重做品牌或增加无关 Material 默认视觉。

验收须包含 mouse/keyboard selection、Ctrl+A/C/X/V/Z/Y、Ctrl+F、Escape、菜单层级、busy 后焦点恢复、关闭资料返回原焦点/选区/滚动、候选采纳与撤销、系统文件对话框、窄窗目录抽屉/资料内嵌和错误通知不遮挡。真 IME 与 DPI 用真实 Windows，widget enterText 不冒充输入法验证。

## 9. 分阶段迁移、依赖、工作量与出口

以下为未来实施，**本轮全部 NOT_RUN**。估算单位为有 Flutter/Rust 经验的一位工程师有效人日，含相关测试/修复；不等于日历承诺，不含等待 SDK/翻译/真实模型授权。各模块每次开工核对源哈希，若原工程变化先重审合同。

### M0：最小合同验证模块（2–4 人日）

第一项先做无 UI、无 DB、无网络的 **Text/Locale Contract**：UTF-16↔Unicode 标量转换、非法 surrogate 边界拒绝、精确引文/全文 hash 测试向量、locale 解析/回退、作者文本不被本地化、稳定错误码。未来目标 `lib/domain/editing/text_coordinates.dart`、`lib/domain/models/language_preferences.dart` 及镜像测试。仅在下一轮明确进入实施时建立隔离目标工程/包，本轮不创建。

出口：Dart format/analyze、纯 Dart 行为/属性测试、Rust 对同一合成向量核验，混排字符串逐字 round-trip；模拟错误显示不得影响正文；只使用 ASCII 协议值。记录命令/退出码/向量 hash；回退点是独立模块提交/归档，原端完全不动。M0 不称可运行桌面应用，提供可执行 Dart/Rust harness 证据。

### M1：Windows runner + 核心桥接/存储探针（5–9 人日，依赖 M0）

未来创建目标 Flutter Windows 工程，先核 doctor/toolchains，再接独立 Rust bridge/application；只操作合成新库与合成 v11→v12 fixture。功能限定 open/list/load/save-CAS/close/reopen、typed error、async cancellation 的本机合成任务、DLL handshake。key/network 后端禁用，发送接口 fail closed。

出口：`flutter analyze`、相关 Rust test/check/Clippy、Dart DTO/真实 FFI 集成、`flutter build windows`、从独立拷贝 bundle 运行真实 probe；v12 迁移失败回滚/移除阻挡后重试/重开、CAS 双写冲突、use-after-close/重复close/取消迟到、事件退订、DLL 依赖树完整。日志/屏幕只有合成数据。FRB 失败时明确 FAIL 并启动备用比较，不做 UI 大迁移。回退至 M0，保留探针日志。

### M2：多语言基础与视觉工作台（4–7 人日，依赖 M0；运行验收依赖 M1）

建立 DESIGN tokens、中文本地字体与英文 fallback、ARB 中英、伪长文案/RTL harness、空库作品选择、目录/顶栏/专注/宽稿/错误区域。repository 合成替身用于 widget 验证，另有真实 bridge 目录读取；不得用替身结果声称存储验收。

出口：gen-l10n、ARB parity、format/analyze、widget/golden（固定字体/窗口/DPI）、真实 Windows 启动/缩放/语言切换；能辨认 REAL/SYNTHETIC 模式。回退至 M1 runnable probe。

### M3：正文编辑器替代与原位讨论布局（10–20 人日，依赖 M0/M2；高风险）

先用候选 A/B 各自小 spike 对同一矩阵比较后 ADR 锁定；再实现 transaction、选择/IME、anchors、history、gutter/段下稳定槽位、资料浮卡和焦点往返。不得先全量重写再发现 IME 不合格。

出口：第8节完整输入/长章/视觉矩阵，尤其中文组合输入、同行两标记、失效重开、全文删/撤销恢复、外部rollback映射不循环保存、RTL/LTR混排、切语言不丢草稿。profile证据包含设备/构建/数据hash/原端对照。失败停在 spike 并评估路线，不进入作者数据迁移。回退至 M2；不更改旧端。

### M4：作品、保存与正式版本（6–10 人日，依赖 M1/M3）

迁移 NativeSession/SaveCoordinator/目录全集重排、归档恢复、最近作品/UI session、working copy、版本确认/回退和所有切换/关闭屏障。

出口：两作品×两章合成流程，保存时持续输入、空正文保存、头漂移/冲突/锁库/磁盘故障、旧响应跨章、退出失败后重试/恢复导出、重开恢复最近成功提交稿；版本/归档/线程/出处数量与原库 fixture 一致。每项有真实数据库测试与 Windows runnable flow。回退到 M3 + 合成库一致性备份，保留尚未保存稿的导出。

### M5：持久讨论、候选审阅与撤销（6–10 人日，依赖 M4）

迁移线程 registry、未发草稿、引用快照、历史讨论、operation 派生视图、候选 compare/apply/reject/session versions；用真实 Rust 持久合成候选，不调用模型。

出口：20万字4操作后继续写草稿/重开，服务端 requests/candidate 不进入作者 snapshot；原子采纳注入状态写失败完整回滚；重复/迟到/资料变更/选段过期拒绝；候选撤销后不重复生成或复活 pending；切作品/章/关闭保留隔离。静态/测试/Windows运行齐全后方可完成。回退 M4 与候选fixture备份。

### M6：资料、出处、地图与恢复导出（5–9 人日，依赖 M4/M5）

人物/地点/世界/历史其他类型边界、lore版本、确认资料、精确出处/旧版本/stale、地图现有交互登记、系统对话框/UTF-8导出。related/position 原生持久化缺口需要单独决定是等价保留预览能力还是补新功能，未决定前保持显式未完成项，不能删除功能让门槛通过。

出口：emoji/RTL出处/跨作品拒绝/旧版原文展示、无出处清晰为空、未保存稿与部分恢复导出明确、系统取消/覆盖/不可写/占用/中文长路径；读回内容逐字断言，不含线程草稿。Markdown可读导出与完整备份术语分开。回退 M5。

### M7：官方 DeepSeek BYOK 与异步生命周期（4–7 人日，依赖 M1/M5/M6）

先合成本机HTTP/SSE与假凭据注入验证，再单独请求作者对真实完整材料的明确许可。迁移 cloud gate、keyring service、完整消息预览、一次性发送、cancel/restart interrupted、持久候选、超时、窗口关闭/切章/切作品身份检查。沿用Rust官方端点，不把网络重写到Dart http。

出口：**合成层**拆包/断流/取消/超时/重复确认/迟到错误/重启不重发全部断言，费用提示与语言材料一致；**真实层**只有经作者确认后才能跑，并单独记录请求授权、受控范围、结果与取消限制。没有授权时保持真实C NOT_RUN/PARTIAL，不阻塞其他合成验证，也不伪称真实端到端通过。回退 M6；不自动重试付费请求。

### M8：净机安装、数据接管与发布（5–9 人日，依赖 M1–M7及前置授权）

完整bundle/依赖、独立标识与升级/卸载，单写者门槛、明确备份与回退演练。发布前当前范围所有原生出口必须通过；原端 A/B 未完成的IME/DPI等成为新端必须补测项，不继承旧 PARTIAL 为 PASS。

出口：净机无需开发PATH可启动；离线与非管理员、各DPI/多屏、中英/伪长文案/RTL、保存屏障、故障恢复、完整性/FTS/schema、作者数据接管前合成演练成功；装后实际工作流与产物SHA对应。真实模型未授权则明确发布能力/验收限制，不能宣称含真实模型闭环的客户端全部通过。回退到经验证旧安装/旧数据备份，先导出新写入，不强制旧程序读取更新schema。

### M9：历史功能保留与后续迁移（另估，不并入主线）

历史小说逐块patch/RPG/开放问题/摘要重建、旧想法/导入检索/记忆、角色包/托盘/quiet/桌宠、学习沙箱分别建模块工作单。各单列原入口/数据/测试/替代/可达性，未完成标 DEFERRED；“小说迁移完成”不能叫“全产品完全替代”。暂估历史小说补齐4–10人日、记忆/导入6–12、桌宠/壳6–12、学习隔离8–15，均需专项审计后重估。

M0–M8 合计约 **47–85 人日**；高风险/工具链返工和新增正式语言翻译另留20–35%储备。依赖主链为 M0→M1/M2→M3→M4→M5→M6→M7→M8。M1与M3两个闸门不过，不启动大规模逐文件搬迁。估算不把已有Rust代码行数等同于可免费复用。

## 10. 每模块通用质量门禁与可检查证据

每模块必须同时满足：范围/原功能清单清楚；source hash与目标版本可定位；静态检查；相关真实行为测试；对应模块可执行harness或Windows应用运行；失败/未测明确；回退点可用。不得删功能/断言、返回假成功、吞错、忽略检查或自动改基线换绿。

后续命令在目标目录逐条用pwsh运行，每条记退出码；以下仅为计划，本轮未运行：

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter gen-l10n
flutter analyze --fatal-infos
flutter test test
flutter test integration_test -d windows
flutter build windows --release
```

纯Dart包使用`dart analyze --fatal-infos`/`dart test`；Rust按实际受影响package运行`cargo test/check/clippy`，工具链用项目级明确target，不改全局default。未来pwsh统一检查入口依次覆盖format、ARB parity、analyzer、owned-source边界、Dart/widget/真实bridge集成、Rust、build、安装运行；NOT_RUN非0且不计PASS。技能中的Bash检查脚本本轮未执行，后续等价改为pwsh/纯Dart，不调用Bash。

合成网络允许127.0.0.1测试服务、假Key且外网发送默认拒绝；memory-core数据库测试必须真实引擎/合成fixture，不能用mock DAO代替。UI repository fake只证明UI状态，不证明磁盘、FFI、IME或发布。凭据往返使用专用测试服务名且只有专项测试触发；禁止全workspace无筛选触发真实凭据/paid examples。

每阶段`docs/evidence/Mxx-YYYYMMDD.md`（未来新工程内）至少记录：源码与产物hash、SDK/toolchain/OS/DPI/窗口和locale、合成数据hash、实际命令/退出码/测试总数与skip/filter、断言点、截图或短录制、导出UTF-8读回、依赖清单、性能原始记录、失败/未测及回退演练。截图无私人正文；日志无Key/外发材料。golden更新必须有几何/行为解释，不能盲目rebaseline。

## 11. 风险、未决项与停止条件

- **最高：编辑器能力等价。** block线程、virtualization、IME/撤销/选择、Unicode混排可能不被候选直接支持；M3失败即停止该路线，不能把原位讨论改常驻侧栏当完成。
- **最高：DLL与工具链。** 原GNU历史导出上限、MSVC环境不明、SQLite C编译、FRB版本组合都需M1实证；不承诺现有Flutter SDK“已装”就能构建。
- **最高：数据接管。** 新锁不能约束旧无锁写者；备份/WAL/单写者未证明不碰作者库。迁移失败保留原库和诊断，不尝试清库“修复”。
- **高：TS协调器移植。** editSequence/generation/线程作者快照与操作分离等细节容易丢；使用原测试场景和新增跨语言契约回归，不能靠UI看似正常。
- **高：多语言错误与模型材料。** 现有中文字符串判错/硬编码prompt需解耦；历史数据与正文不翻译，输出语言改变须重新预览；最终支持语言清单和译文质量是发布前未决项。
- **高：地图/关系和旧功能缺口。** Preview和Native不等价、lore其他类型/旧逐块审阅/RPG不可自动消失。每项需明确范围与后续门槛，不静默删入口或数据。
- **高：真实模型未授权。** 本轮零请求；后续真实材料确认和费用许可为必要闸门，自动模型列表拉取也属于网络动作不可随启动发生。
- **中高：多语言字体/RTL/计数/检索。** 先本地字形与混排实测，再扩正式语言；多语言支持不能用任意UTF-8字符串能存库替代。
- **中高：净机分发。** 原安装失败提醒须查完整依赖树，新方案亦会有Flutter/VC/Rust/plugin DLL风险，不把无WebView误认为无运行时依赖。

完成本轮文档后停止。下一实施起点是 **M0 Text/Locale Contract**，通过后做M1桥接与M3编辑器两个关键验证；当前没有获得本轮实施迁移的授权，不执行flutter create或改原项目。

## 12. 技能实际使用与公开技术依据

初始在`C:\Users\HP\.codex\skills`、`.agents\skills`、Codex插件缓存、项目隐藏技能目录，以及后续`.claude/.cursor`技能目录发现未安装目标Flutter/Dart技能。用户随后明确授权安装，使用预装skill-installer官方脚本固定commit下载：Flutter官方10、Dart官方15、社区40，共65；Flutter仓库重复Dart技能只从dart-lang安装，未覆盖已有目录。安装技能文件不等于配置Dart MCP/安装Flutter插件所有运行能力，未自动安装编译器或额外服务。

实际用于本计划：官方`flutter-apply-architecture-best-practices`（层次/Repository/MVVM）、`flutter-build-responsive-layout`（按窗口约束）、`dart-run-static-analysis`/`dart-add-unit-test`（未来门禁）、`dart-setup-ffi-assets`（边界与分发的C资产指导，不冒充Rust自动桥接）、`flutter-setup-localization`（ARB工作流，过时示例按当前文档修正）；社区`async-safety`、`service-boundary-and-native`、`testing-strategy`、`i18n-rtl-l10n`作补充。

只采用与本任务相符部分：不执行技能中的迁移/安装/生成步骤，不引入Drift接管Rust库，不因社区模板强制Riverpod，不把Windows任务改成Bash，不按社区epoch建议重写既有RFC3339，不剥除作者正文bidi字符。技能不能代替原生输入、真实FFI或模型授权。

公开资料核查于2026-10-15，版本锁定须在未来M1重新确认；Context7 Flutter查询成功、FRB library resolver网络失败，FRB改用维护者文档核查。以下支持方案能力而非本项目已通过：

- [Flutter Windows 环境要求](https://docs.flutter.dev/platform-integration/windows/setup)：Windows runner工具链前提。
- [Flutter Windows 集成与分发](https://docs.flutter.dev/platform-integration/windows/building)：平台集成和运行依赖需独立验证。
- [Flutter 绑定原生代码](https://docs.flutter.dev/platform-integration/bind-native-code)：C ABI/Code Assets路径。
- [FRB async Rust](https://cjycode.com/flutter_rust_bridge/guides/concurrency/async-rust)、[FRB Stream](https://cjycode.com/flutter_rust_bridge/guides/types/translatable/stream)：生成异步与流绑定的依据，不是自动业务取消保证。
- [EditableText API](https://api.flutter.dev/flutter/widgets/EditableText-class.html)：输入/选择/快捷键是独立可控风险面，不能由TextField名字推断等价。
- [Flutter 国际化](https://docs.flutter.dev/ui/internationalization)：当前gen-l10n与locale/delegate基础；示例需按选定SDK验证。
- [file_selector 维护包](https://pub.dev/packages/file_selector)：未来系统文件选择候选，仍需Windows覆盖/取消实测。
- 技能源：[flutter/agent-plugins](https://github.com/flutter/agent-plugins)、[dart-lang/skills](https://github.com/dart-lang/skills)、[zakariaf/Flutter-Skills](https://github.com/zakariaf/Flutter-Skills)。

## 13. 自定义标题栏与窗口控制（2026-10-18 新增）

状态：**PLANNED / NOT_IMPLEMENTED**。用户所说的窗口最上方叫“标题栏”，Windows 任务栏是屏幕边缘显示应用图标的系统区域。目标是把标题栏纳入幻月可设计的 UI，与浅灰外框和现有工具栏协调，提供应用标题、最小化、最大化／还原、关闭；作品标题仅作本地展示。保留暖白正文与既有业务工具，不因加窗口按钮挤掉窄窗操作。

### 13.1 范围与技术路线

- 编号 **M2-W 窗口外壳补充**，与 M4 关闭生命周期联合验收；不列入历史功能 M9，也不必等到发布 M8 才首次验证。先解决 M4 原生持久化阻断项并稳定关闭合同，再做独立窗口探针、接入工作台；进入 M5 前明确本项结果。与未验收的 M3 生产编辑器改动分别记录。
- 首选评估 `window_manager`：维护者文档提供 `TitleBarStyle.hidden`、窗口事件、最大化／还原和关闭拦截。实施前核对当前 Flutter/Dart/Windows 兼容版本、许可证、传递依赖并锁入项目 lockfile；本轮未加依赖。隐藏原生标题栏的方案需实测系统边框、阴影、八向缩放和 Snap；不预先宣称 Windows 11 最大化悬停菜单可用。
- 用可注入的窗口服务封装拖动、最小化、最大化／还原、窗口状态及最终关闭，Widget 不直接散落调用平台插件。空白标题区启动系统拖动；按钮、菜单、文本选择等交互区排除拖动；双击空白区切换最大化／还原。是否保留系统按钮或需要补 Win32 hit-test，在探针后决定。
- 拟定文件归属：`apps/desktop/lib/window/` 放窗口服务及关闭协调，`workspace/presentation/` 放标题栏 Widget，必要的宿主消息适配限定在 `apps/desktop/windows/runner/`。不改 Rust 数据权威和原 Tauri 工程。原生接口不可满足时再评估小型 Win32 adapter，并以功能矩阵决定，不叠加多个争抢窗口消息的插件。

### 13.2 关闭合同与界面合同

关闭按钮、系统 X、Alt+F4、系统菜单关闭必须归入**同一个共享关闭请求**。先完成输入法组合输入的明确提交／取消策略，等待正文和偏好保存，失败保留窗口与稿件，允许重试或恢复导出。导出取消／失败不能退出；成功导出仍须作者选择退出。禁止按钮直接 `destroy()` 绕过保存屏障。

接入插件时核实其原生 close 拦截与现有 `AppLifecycleListener` 的消息顺序，选定唯一关闭决策所有者，避免双重对话框、递归 close 和重复释放。最终平台销毁只在共享决策批准后执行一次；启动失败且无稿件时允许正常退出，异步初始化晚到资源仍须释放。最小化不当作关闭，不释放当前编辑会话。

窗口状态由真实系统事件同步，最大化图标及时切换为还原；应用失焦、最大化后的边距也需验证。按钮具备键盘焦点、Tooltip、Semantics、本地化标签与清晰悬停／按压反馈。按可用宽高安排标题截断和工具栏布局，验证中英长标签、RTL harness、高对比度及 100/125/150/200% DPI、多屏移动；不向作者正文插入任何展示字符。

### 13.3 验收、证据与回退

1. 窗口探针：真实 Windows 启动、拖动、双击、最小化／恢复、最大化／还原、八向缩放、贴边、Win+方向键、Alt+Space、Alt+F4。Windows 11 Snap Layout 悬停单列实测，失败记录并处理，不把普通最大化通过当作该项通过。
2. 关闭故障矩阵：正常保存后关闭；持续输入／IME 组合中关闭；重复关闭共享一次决策；保存失败留窗／重试；系统保存对话框取消、失败、成功读回后继续编辑／明确退出；启动失败／初始化未完成时关闭。真实原生事件和系统对话框证据独立于 widget 信号测试。
3. 接入回归：编辑器选区／焦点／快捷键、切章切作品、宽稿／专注／窄窗、窗口布局及既有 M2/M4 行为。运行相关 format/analyze/行为测试、Release 构建及独立 bundle 启动；新增插件的 DLL 和运行依赖纳入分发检查。禁止自动更新 golden 掩盖布局差异。
4. 保存命令、退出码、源码与产物版本、OS/DPI、合成材料、截图和故障结果至 `docs/evidence/m2-window/`。所有强制出口通过才标完成，未测仍为 NOT_RUN。

初估 **2–4 有效人日**，含探针、接线与原生回归；若 Windows 11 Snap／非客户区需定制 Win32 消息，另估 **1–3 人日**，不包含现存 M4 存储缺陷和 M3 生产化。回退为已验证的系统标题栏与原关闭守卫，保留合成稿及导出，不以无边框失去窗口控制的版本作为可交付产物。

依据：2026-10-18 通过 Context7 查询维护者 [`window_manager` README](https://github.com/leanflutter/window_manager/blob/main/README.md) 与[事件／关闭拦截文档](https://github.com/leanflutter/window_manager/blob/main/docs/en/quick-start.md)。文档证明候选 API 存在，不代表本项目兼容性和关闭语义已通过。
