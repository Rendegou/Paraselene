# Flutter 写作工作台操作整改与文件清理执行方案

日期：2026-10-20（Asia/Shanghai）。状态：**方案已交付；整改实现、运行验收和实际清理均未执行**。

本轮用户要求是“目前先只加一个文档”。本次只新增本文件，不修改应用、测试、旧计划或进度看板，不删除或移动任何文件。后续获得实施指示的 Agent 按本文分批执行；本文的目标和验收标准不能当作已完成结果。

## 1. 接手范围与证据口径

### 1.1 工作目录

| 代号 | 精确根目录 | 用途和边界 |
|---|---|---|
| F | `D:\MyAgent\paraselene-flutter` | 唯一整改目标。工程路径总根目录；应用内短路径按表后约定解析 |
| O | `D:\MyAgent\paraselene-work` | 原 React/Tauri 工程，只读对照，禁止清理、改源码、改数据或同步覆盖 |
| P | `D:\MyAgent\paraselene-flutter-migration` | 既有迁移计划、映射和原工程快照，继续保留 |

操作环境固定为 Windows、PowerShell 7 `pwsh`；禁止 Bash、`powershell.exe`、Docker。本文代码块只是后续执行入口，本次没有运行应用构建、应用测试或清理命令。

路径约定：`apps/desktop/`、`rust/`、`packages/`、`scripts/`、`spikes/`、`build/`、`docs/` 和 `.superpowers/` 从 F 解析；短路径 `lib/`、`test/`、`integration_test/`、`bin/`、`windows/` 从 `F/apps/desktop/` 解析。源码短路径 `editor/`、`cowrite/`、`lore/`、`workspace/` 从 `F/apps/desktop/lib/` 解析；只写文件名的入口见 10.1。`O/`、`P/` 分别替换为上表根目录。清理台账中的精确相对路径一律从 F 解析，不能套用应用内短路径规则。

### 1.2 审计对象

- 原版基准是 `StudioApp → NativeStudioApp → writing/NotebookApp` 的暖白工作台；不是更早的 `features/novel` 常驻三栏界面。
- 原生版和浏览器预览共用一部分界面，但数据源、模型和地图能力不同。预览里的可点击示例不直接构成原生能力证据。
- Flutter 基准为 **2026-10-20 当前未提交工作树**。HEAD 为 `cb2271778163a0fb98d1ebf4737ade0a0790b619`；只检出该提交不能复现本次审计状态。
- 对照工程 HEAD 为 `c64e88afd4787272952ef917f54f8e7e610621c2`，也有既存修改。
- 已查看用户附图。图中短正文与固定章末之间存在大块留白，搜索框写“搜索作品”，顶栏承载许多同级动作。这是界面观察；保存、滚动、焦点和 IME 结论另依源码或后续实测。
- 本轮完成源码只读核对、历史证据核对、指定目录元数据统计。没有控制用户桌面，没有打开作者数据库、正文文件或凭据，没有发模型请求。
- `docs/evidence/UI-PARITY-20261020.md` 记录的是既有视觉改动及历史测试。其 `IMPLEMENTED` 不代表本文操作整改已完成；该记录本身说明真实窗口视觉复看尚未完成。
- `docs/evidence/CLICK-TEST-20261020.md` 是另一轮真实合成操作的历史记录。其 SendKeys 快捷键未生效不能直接认定产品快捷键损坏；未覆盖项不能转写 PASS。

本文使用三种证据标签：

| 标签 | 含义 | 实施 Agent 的责任 |
|---|---|---|
| 静态确认 | 当前源码可直接确认的布局、状态或调用链问题 | 改前建立能失败的行为断言，改后验证 |
| 待运行核实 | 源码存在风险，但尚无本轮运行复现 | 先复现；未复现就保留风险说明，不虚构根因 |
| 目标设计 | 为恢复原版工作流程规定的行为 | 按目标实现，不伪称原版所有运行状态均已通过 |

## 2. 为什么新版本操作起来更别扭

原版的核心顺序是：**选作品 → 选章节 → 写正文 → 选段就地讨论 → 按需查资料 → 审阅并明确采纳 → 返回写作**。正文一直是工作中心，临时界面围绕当前动作出现。

Flutter 版已经迁移了许多底层能力，也统一了颜色、字体和工具入口；当前问题集中在视图组合与业务接线。仅调整配色、圆角或按钮图标，不能恢复下面这些行为。

| 操作 | 原版依据与行为 | Flutter 当前情况 | 实际影响 / 对应整改 |
|---|---|---|---|
| 阅读一章 | O 的 `NotebookManuscript`、`ParagraphEditor` 与纸面布局组织连续阅读 | `manuscript_editor.dart` 将标题区、正文视口、章末区分开，章末固定在正文视口外 | 短章出现大洞，长章未读完也显示“本章结束”；R05 |
| 段下讨论 | O 的 `useNotebook.ts:31` 只为当前有效线程计算一个段末槽位 | `_syncHosts:237` 为所有非整章线程分配固定 260 逻辑像素 | 讨论越多正文越碎；没有收起状态；R06 |
| 关闭后重开讨论 | O 的 `useThreadStore` 将 activeId 与持久线程分开；`DiscussionIndex` 可列失效记录 | 面板没有明确收起/关闭；窄窗更多菜单没有讨论索引回退 | 记录存在却不易找回，失效线程不能依赖旧坐标定位；R06、R07 |
| 从选区开始讨论 | O 的 `ParagraphEditor.tsx:115` 保留原选区；关闭后回到目标末尾 | 当前创建只调用 registry，重开主要只选择锚点 | 卡片露出和输入焦点需实测，缺少明确的动作完成反馈；R08 |
| 自动保存 | O 的 `nativeSession` 与保存条持续显示编辑稿状态及恢复操作 | 新顶栏读取 EditingSession，但父级主要监听 WorkspaceController | 后台保存通知可能不刷新状态；R01 |
| 保存失败 | 原版保持当前工作区，提供重试和内存稿导出 | 窄窗 `_SaveStatusInline` 提前只返回 Tooltip(dot) | 重试/导出在最需要时不可达；R02 |
| 宽稿偏好 | O 的 `useNotebookLayout` 接 native UI session | `WorkbenchScreen._wide` 为局部 bool，绕过 `controller.setWide` | 切作品/重启后不按持久偏好显示；R03 |
| 阅读位置 | O 的 `useSurfaceReturn` 保存阅读位置，显式跳转优先 | 外层滚动控制器未接滚动组件；实际视口独立持有 scroll；pending 恢复无 UI 消费 | 看过的长章回到开头，恢复接口看似存在但未接通；R05 |
| 资料目录 | 原版可轻量预览指定资料，再决定是否带入讨论或展开编辑 | 点击不同资料行均无参调用 `_openLore()` | 还要从资料库重新找一次，阅读与编辑被合并；R09 |
| 切作品加载资料 | 原版状态绑定作品/会话身份 | `_loreLoading` 阻止新作品请求，旧响应因作品不符提前返回却不清 loading | 特定异步顺序可一直加载；R04 |
| 出处读取失败 | 失败应与没有出处区分 | source controller 有 failed，但正文仅按 marks 非空展示入口 | 错误被呈现为空结果；R11 |
| 搜索与重命名 | 操作名称对应当前对象 | 章节筛选框写“搜索作品”；重命名按钮固定“创建”，初值未全选 | 对象与动作不一致，改名容易追加文本；R12 |
| 快捷键与返回 | 原版有焦点恢复、临时卡片与逐层退出逻辑 | 全局 HardwareKeyboard handler 只检查正文 composing，未检查当前 route/焦点归属 | 对话框快捷键穿透、Escape 层次和其他输入框 IME 需核实；R10 |
| 能力说明 | 预览、真实数据和可用模型能力需明确区分 | 整章线程 target/anchor 为 null，valid=false，生成按钮禁用 | 整章讨论不能声称已有整章模型对话；R14 |

上表引用的 `manuscript_editor.dart`、`workbench_chrome.dart`、`workbench_sidebar.dart` 均位于 `apps/desktop/lib/workspace/presentation/`。行号是审计时定位提示，执行前用符号名重新搜索，不能机械套用旧行号。

## 3. 必须保持的合同

1. **作者原文不变形。** 不做 NFC/NFKC、换行、全半角、标点或大小写归一化；不 trim 正文。标题允许沿用原有校验规则，不能把标题规则应用于正文。
2. **坐标分清单位。** Dart 编辑器及线程 from/to 是 UTF-16 code units；Rust SourceAnchor 使用 Unicode 标量；bytes 和用户可见字符另算。禁止在 surrogate 中间切割。
3. **正文、线程与 UI 分离。** 讨论卡、标题、章末、标记和占位高度不能进入正文字符串、复制、导出、hash 或 undo 内容。
4. **target 与 anchor 分离。** target 冻结原始选段及 baseBody，anchor 只经真实事务映射。目标改掉即失效；不能用相似搜索或同文引文重绑。全文撤销恢复必须依赖已知快照与映射。
5. **编辑稿与正式版本分离。** 自动保存、Ctrl+S、关闭屏障都不自动确认正稿。确认/回退必须继续通过 controller 与 Rust 的 revision/head 校验。
6. **候选不自动采纳。** 生成/查看候选不改正文；明确采纳才写 working copy，正文与候选状态同事务 CAS。一次采纳对应一次正文撤销；撤销不能重发请求或把已结束 operation 改回 pending。
7. **保存失败保留内存稿。** 不先导航后报错，不更新 expected revision 掩盖冲突。正文、线程、偏好与资料各自的脏状态都要进入退出屏障。
8. **历史快照不可改写。** 当前资料变化不改写过去请求中的资料/引文版本；服务端 operation 投影不重复写入作者线程快照。
9. **数据边界不扩大。** 仅合成库或明确授权的脱敏副本；不读 Key、env、认证或作者库。不发模型/付费请求。未来模型仅官方 DeepSeek BYOK，外发材料预览与一次性明确确认继续有效。
10. **保留现有功能和数据。** legacy 名称、untracked 状态、功能退出默认入口或测试未覆盖，都不能单独成为删除依据。小说工作台优先，不借本任务扩展桌宠、学习、RPG 或数据库 schema。

这些边界延续 `P/MIGRATION_PLAN.md` 第 6 节、原版当前方向及 F 的 `AGENTS.md`。本轮不重新从 M0 开始迁移，也不以旧计划中某轮“未授权”文字否定后来已存在的实现；**本文当前授权仍是只交付文档**。

## 4. 目标工作台与状态归属

### 4.1 布局和入口

- 窗口标题栏继续负责拖动、系统菜单与窗口控制；本轮不重写 runner。
- 工作台顶栏优先显示当前章节、编辑稿保存状态、正文查找、讨论记录与版式/专注；选段存在时提供“讨论这段”。
- “章节与版本”收纳确认和版本回退；“更多”保留模型、备份、导入、历史功能等已有入口。不能把常用功能折叠后漏掉窄窗回退。
- 左侧目录提供章节/资料页签，搜索只作用于当前页签对象。宽窗可常驻；窄窗以抽屉进入，选中章节后关闭抽屉并返回正文。
- 纸面内部按 `标题 → 元信息 → 正文（当前段下讨论）→ 实际章末` 排列，共用一套文档纵向位置。标题和章末不占独立固定视口。
- 正常写作不常驻空讨论栏；有效选段讨论一次展开一处。失效或整章线程从显式临时面板打开。资料轻量预览按需打开。
- 不规定必须改用某个 Flutter 容器名称；R05 的单视口几何、增量布局与输入合同是验收对象。

### 4.2 状态所有权

| 状态 | 权威来源 | UI 可做什么 |
|---|---|---|
| 正文、selection、composing、undo | EditingSession + 现有 EditorDocument/InputClient/Adapter | 发输入意图；布局或保存状态更新不能重新 hydrate |
| 保存中/失败/冲突、恢复基线 | EditingSession 的 SaveState；工作区错误另读 controller | 订阅变化并呈现；不能用本地 bool 推断已保存 |
| 持久线程、草稿、引用、operation | DiscussionRegistry / repository / Rust | 以 thread ID 打开；不复制出第二份持久状态 |
| 当前展开线程、临时资料卡、焦点返回点 | 当前工作区展示状态 | 允许独立管理；收起不删除持久线程 |
| 宽稿、当前章与滚动偏好 | controller 的 per-work UI session | 调用现有 setWide/noteScrollTop；不再保留另一份 _wide |
| 异步资料/出处结果 | 带 work/document/epoch 身份的请求状态 | 只接纳当前身份结果，旧请求不得污染新作品 |
| 外发票据与候选有效性 | 既有生成/采纳业务层 | 展示与调用；不能为让按钮可点而跳过校验 |

## 5. 可逐项实施的整改任务

以下 R01–R14 初始实现状态全部为 `TODO`，运行验收全部为 `NOT_RUN`。P1 表示优先修复会误导保存、阻断恢复或丢失操作入口的问题；P2 表示工作流和交互问题。顺序见第 6 节。

### R01 / P1：接通保存状态订阅

**证据：静态确认。** `workbench_screen.dart:57` 主要监听 controller；`workbench_chrome.dart:611` 的 _SaveStatusInline 是普通 StatelessWidget。`editing_session.dart:114` 的保存通知只发给 EditingSession，controller 的编辑监听在 `workspace_cowrite.dart:_mapDiscussionBody` 中不转发通知。EditorSessionAdapter 的通知也不能代替完整保存状态订阅。

**修改入口：** `workbench_chrome.dart`、`editing_session.dart`、`editor_status.dart`。检查 `workbench_dialogs.dart:ConfirmChapterDialog._watchEdits` 等其他依赖编辑变化的消费者，避免相同订阅断点；确认对话框失效行为先运行复现。

**执行：**

1. 保存展示直接订阅 EditingSession；屏障错误继续订阅 WorkspaceController。采用项目现有 Listenable 方式，复用真实 SaveState。
2. 将展示计算抽出小组件；仅保存区域重建，不让每次保存状态变化重建/重置正文文档、input client 或 undo。
3. 切章/换 controller 时解绑旧监听，dispose 后不 setState。
4. 保留 dirty/saving/saved/conflict/error 区分；线程失败和偏好失败不能被一个正文绿点遮住。

**验收：** 使用可控写入 Future，在不导航、不改宽度、不触发额外页面 rebuild 的情况下观察 dirty → saving → saved；注入 error/conflict 后下一次渲染立即显示对应状态。正文、选区、composing 与 undo 不变。测试放 `test/operation_parity/save_status_test.dart`，复用 `test/support/m2_harness.dart`。

### R02 / P1：所有宽度都能恢复保存失败

**证据：静态确认。** `_SaveStatusInline.build:648` 的 compact 分支提前返回状态点，后面的 retry/export 菜单不可达。旧 `editor_status.dart` 另有 draftRestoredBase、稳定错误码、durable_save_failed 解释和 liveRegion，新展示缺失这些信息。

**执行：**

1. 保存失败用可聚焦按钮/状态区域表示，必须有文字或图标加语义；Tooltip 不能是唯一解释或入口。
2. 宽窗可显示就地文字操作，窄窗可打开恢复面板；两者均提供 `controller.retrySave()` 和现有 `RecoveryExportFlow`。
3. 展示“编辑稿已保存”而非暗示已经确认正稿。恢复稿基线不同于当前 head 时说明差异。
4. 失败保留当前页、正文与草稿。导出取当前内存稿；系统取消不报成功，写入失败继续保留恢复入口。
5. 不能把“重试”变成刷新 revision 后强行覆盖；不能把“导出草稿”误接到普通磁盘版本导出。

**验收：** 360×720 逻辑像素、200% 文字缩放，鼠标与 Tab/Enter 都能发现错误、重试和导出；错误无需 hover 即可理解。故障期间切章和关闭被屏障阻止；恢复后正文含 await 期间新增编辑。UI fake 只证明呈现，真实 Rust 故障和系统写入另按第 7 节验收。

### R03 / P1：宽稿设置使用唯一持久状态

**证据：静态确认。** `WorkbenchScreen._wide=false` 与 onWide 局部 setState 绕过 `workspace_state.dart:wide/setWide`。

**执行：** 删除重复的界面 _wide；顶栏勾选与纸面宽度均读 controller.wide，切换调用 controller.setWide。不得因版式变化重建 Adapter 或改变 contentEpoch。使用现有偏好写入节流，不新建数据库或另一套设置文件。

**验收：** 合成作品 A 设宽稿、B 设舒适，来回切换及真实持久化重启后各自恢复；正文、光标和 undo 不变。现有 `test/m4_controller_test.dart` 的控制器恢复测试保留，再增加真实工作台入口断言，不能只测 setWide 本身。

### R04 / P1：资料加载绑定作品与请求代次

**证据：静态确认。** `workbench_sidebar.dart:_loadLore:82` 中 loading 阻止 B 请求；A 返回时因作品变化提前 return，可能一直保留 loading。

**执行：**

1. 以 workId + request epoch 管理 loading/data/error；切作品立即使旧请求失效，并调度当前作品读取。
2. 旧请求的 success/catch/finally 都不能修改新请求状态；不能简单在旧 finally 清掉全局 loading。
3. 没有作品时清状态；当前请求失败显示明确重试；旧作品内容不能冒充当前作品。
4. 无需在每个 controller 通知上重复请求同一作品；保留显式 force 重试语义。

**验收：** 用 Completer 暂停 A → 切 B → 完成 A，最终必须得到 B 数据。另测 A 失败晚于 B 成功、A→B→A、dispose 后返回。不得卡加载、串资料、setState after dispose 或请求风暴。新增 `test/operation_parity/lore_scope_test.dart`。

### R05 / P2：连续纸面、实际滚动与恢复统一

**证据：静态确认。** `manuscript_editor.dart:412/513/543` 分别承载标题、Expanded 正文和固定章末。外层 _scroll 从未挂到滚动组件；真实 scroll 在 `editor/editor_viewport.dart:116`，其 _scroll 只 setState。生产 UI 未消费 pendingScrollTop/applyScrollPending/markScrollApplied。

**执行：**

1. 保留现有虚拟化编辑器。先定义 paper 文档坐标：标题/元信息高度 + 正文布局及活动槽位高度 + 章末高度；全文只有一个权威 ScrollPosition。
2. 在 EditorViewport/布局接缝支持纸面头尾或等价的共享纵向布局。禁止在外面包一层无限高 SingleChildScrollView 并关闭虚拟化；也不能让标题和正文各滚各的。
3. 绘制、hit test、caret、选区、线程槽、出处、滚动露出和 IME geometry 使用同一坐标转换。纸面附加高度不进入正文 UTF-16 offset。
4. 实际 scroll 变化调用 controller.noteScrollTop；删除未连接控制器。监听只由实际滚动触发，不因每次 build 写偏好。
5. 恢复以 work/document/session 身份为作用域。等 ScrollPosition 已连接且内容尺寸可用，再将 offset 钳制到当前合法范围；仅在成功应用后 markScrollApplied。
6. 虚拟布局若 extent 尚在估算，先准备目标区域；不能把远处旧 offset 钳到临时短 extent 后立即当恢复完成。
7. 恢复优先级：作者当前显式查找/出处/讨论跳转 > 待应用会话恢复 > 默认位置。普通阅读恢复不能被初始化 caret 自动滚动拉回顶部，也不能晚到覆盖显式跳转。
8. 现有 schema 只存每作品最近章节和一个 scrollTop：本次保证最近章节恢复；同进程章节可按章保存位置。**不能未经版本化就宣称所有章节跨进程独立记忆**。切到没有记录的章节应使用约定默认值，绝不串用上章 offset。
9. 缩放、宽稿、长标题或展开讨论改变布局时，保持阅读锚点稳定；同一操作结束后再上报最终偏好，避免恢复反馈循环。

**验收：**

- 两字短章的章末紧接正文，保留正常段距；不能固定在窗口底部。长章中部看不到章末，滚到底才出现在最后正文之后。
- 向下滚动时标题随纸面离开视口，不能拥有另一条独立纵向滚动。
- 长章滚到非零位置，正常关闭/重开恢复；内容缩短安全钳制。A/B 作品与章节无位置串用。
- 在标题高度变化和 200% 缩放下点击同一句、选中、复制、中文组字，caret/候选窗/讨论/出处命中仍正确。
- 20 万字多段和无换行材料继续执行现有 profile 场景。保留历史已接受的冷跳/全幅滚动限制说明，不把历史数字冒充本轮新测。

新增 `test/operation_parity/paper_flow_test.dart`、`scroll_restore_test.dart`；扩展 `test/editor/editor_scene_viewport_test.dart`。断言几何与真实 scroll position，不能仅 find.text('本章结束')。

### R06 / P2：线程存在、展开和焦点分离

**证据：静态确认。** `ManuscriptEditor._syncHosts` 对全部非整章线程给定 height=260；`DiscussionPanel` 没有线程标题、引文摘要和明确收起动作；`editor_discussion_overlay.dart` 按全部 slots 挂载。

**执行：**

1. 建立当前展开 thread ID（可为空），与 Registry 持久线程列表分开；同章默认只展开一个有效段下线程。
2. 点击“收起”只改变展示状态，保留 thread ID、草稿、引用、候选和标记。切另一线程前将当前输入同步到 Registry，不能依赖 Widget dispose 才保存。
3. 所有有效线程保留可达标记；未展开线程不占正文卡片高度。同一逻辑行多标记各有独立 hit target，不堆叠成一个不可点区域。
4. 活动槽位落在目标所在段落末尾。卡片随内容测量，取消“每条记录固定 260”规则；超长历史可在卡片内有明确有界滚动，但普通草稿不留空洞。
5. 测量结果通过布局接口反馈，避免 build→测量→反复 setState 的循环；收起保持附近正文阅读位置。
6. 使用 work/document/thread 身份稳定 key。复用草稿编辑控件时不能让上条 selection/composing/输出语言污染下一条；不要在无正文变化的 rebuild 反复设置 TextEditingController.text。
7. 模型操作状态由业务层持有。收起面板不等于取消 operation；显式“取消生成”才走取消接口。卸载不能让真实 operation 状态消失。

**验收：** 建三条线程，只有活动一条占段下空间；收起后空洞消失但三条标记/索引仍在。分别输入不同草稿，切换、滚动、重排和重开均不串稿；同段两标记可分别打开。草稿和 UI 卡片文字不进入正文复制/导出。扩展 `test/editor/editor_thread_layout_test.dart` 与 `test/cowrite/discussion_registry_test.dart`，新增 `test/operation_parity/thread_host_test.dart`。

### R07 / P1：完整讨论索引与线程保存错误可达

**证据：静态确认。** 顶栏只在 !narrow 时显示索引，窄窗更多没有索引项。`_openThread` 主要通过旧 anchor 选择正文；失效线程不应依赖该路径。Registry 已设置 discussion_save_failed，但面板没有对应呈现。

**执行：**

1. 所有窗口宽度提供同一索引，列出本章全部线程，包括失效、未发草稿和整章线程。
2. 每项显示可辨认引文/整章标题、状态、未发草稿提示；按真实 ID 重开，不能创建一个“看似相同”的新线程。
3. 有效线程展开并露出卡片；失效线程在临时面板展示冻结引文和历史，明确“原目标已变化”，禁用需要有效选段的生成/采纳动作，不跳旧坐标或搜索同文句。
4. 每个临时面板有标题、可见关闭按钮、Escape 关闭及合理焦点返回；不能只能点遮罩关闭。
5. 线程保存失败明确显示、保留脏草稿、提供重新保存。索引/顶栏不能在正文已保存时掩盖讨论未保存；导航与退出屏障继续等待 threads.flush。

**验收：** 360×720 下分别重开两条旧选段线程及一条失效线程，ID、草稿、引用和请求历史不变；没有隐式新增记录。注入 saveThread 失败，面板立即出现失败及重试，切章留在当前工作区；成功后冷启动读回原草稿。新增 `test/operation_parity/discussion_index_test.dart`。

### R08 / P2：选段操作完成后有清楚的落点

**证据：待运行核实 + 目标设计。** 当前 _discussSelection 不消费新线程返回值，_openThread 只 select，ensureCaret 主要照顾选区末端，不能直接证明卡片与草稿输入可见。

**执行：**

1. 鼠标或键盘激活“讨论这段”时冻结触发时的合法选区；菜单拿焦点不能先把目标折叠。
2. 创建后选中并展开该 thread，滚动露出引文和输入区，焦点进入讨论草稿。视口底部选段也不能让卡片藏到屏幕外。
3. 选区操作也提供就近的轻量入口，继续保留顶栏入口；无需常驻一整条空工具栏。取消临时选区折叠到原选区末尾。
4. 收起讨论后将焦点返回正文目标末尾；目标已经失效时只恢复安全焦点，不猜测位置。打开资料再关闭，先返回发起它的讨论输入框。
5. 工作区 busy、只读、composing 或选区为空时禁用创建；点击动作时再校验，不能只信菜单构建时的状态。

**验收：** 鼠标拖选、Shift 选择、视口底部选段各测一次；冻结引文完全等于原 UTF-16 区间，打开后可直接输入。关闭后直接续写，不用额外点正文。创建不改正文、不消费 undo、不触发模型。

### R09 / P2：资料查阅、带入讨论、完整编辑分开

**证据：静态确认 + 目标设计。** `workbench_sidebar.dart:_resourceRow` 取得 row 却无参 _openLore；`lore/lore_library.dart` 已有 initialEntry。O 的 `ReferenceCard` 明确区分查阅、“带入这次讨论”和“展开编辑资料”。

**执行：**

1. 先修条目定位：行点击传 entry ID，资料库总入口仍打开列表；缺失条目给错误/返回，不改选其他条目冒充成功。
2. 默认单击给当前条目轻量只读预览，显示名称、类型、内容、版本/状态，提供明确关闭、带入讨论、展开编辑动作。宽窗临时卡、窄窗临时面板可以复用同一内容。
3. 只预览不加入模型上下文；明确“带入”后调用现有引用接口，可移除。没有活动线程时只在作者点击带入后按既有规则创建/选择整章讨论，并清楚显示当前能力边界。
4. 过去请求展示提交当时快照，另提供查看当前资料；不能以最新内容覆盖历史依据。
5. 完整编辑继续复用 LoreLibrary/现有编辑与确认链；保留正文 EditorDocument、选区、滚动和 undo，不能重建工作台来返回。

**验收：** 点击人物甲立即看甲，点击地点乙看乙；预览后 attached 数量不变；点带入仅加入指定条目，可移除。A/B 线程引用独立，改资料后旧请求快照不变。长章中部查阅/编辑返回后位置、选择和一次 undo 都延续。

### R10 / P1：快捷键按焦点与层级工作

**证据：待运行核实。** `ManuscriptEditor._globalKey:254` 注册全局 HardwareKeyboard handler，只检查正文 client.composing，没有 route/primaryFocus 门控。不能据此直接宣称已复现穿透；旧 SendKeys 未触发也不算产品缺陷。

**执行：**

1. 先复现重命名、资料输入、讨论草稿、模型设置中 Ctrl+F/Ctrl+S 的实际路由。
2. 优先通过现有 Focus/Shortcuts/Actions 作用域路由正文动作；若保留全局 handler，必须验证当前可见 route、焦点所属及目标仍挂载。
3. 不要一律 return handled，也不要只用“正文没 composing”判断所有输入法安全。当前焦点输入框正在组字时，Enter/Escape/快捷键交还输入法。
4. Escape 每次只退出最内层：输入法组合 → 当前菜单/临时对话框/资料卡 → 查找 → 已展开讨论 → 专注模式。没有对应层时保持原生行为；关闭失败恢复对话框必须按其明确决定处理。
5. Ctrl+F 在正文范围打开/聚焦查找，Ctrl+S 调用现有保存意图，Ctrl+Z/Y 保持当前编辑控件自己的 undo。取消查找回到正文，不重置原文。
6. 更多菜单启用态从打开时最新 actions/capabilities 计算，修正提前缓存 tools 导致的潜在过期选区状态。

**验收：** 正文快捷键正常；模态输入中快捷键不操纵背后正文；多层 Escape 按一次只关一层。微软拼音候选确认、取消、选区替换、焦点切换真实物理输入通过后才标原生 PASS。新增 `test/operation_parity/focus_shortcuts_test.dart`；widget 按键注入只证明 Dart 路由。

### R11 / P2：出处展示 loading/empty/error/content

**证据：静态确认。** `lore/source_mark_controller.dart:87` 失败置 failed；ManuscriptEditor 仅 marks 非空时展示出处入口，未读 failed。

**执行：** 在出处接缝呈现可辨认的读取中、无出处、读取失败及结果；失败提供显式刷新，正文继续可写。保留 work/document/head/body/epoch 校验，旧响应不得发布装饰。历史出处打开对应不可变版本且只读，不能改成当前可写正文或相似句定位。打开资料失败也要可见，不能只 catch 后 setState。

**验收：** 注入 sourceMarks 异常必须看到失败和重试，不能显示“没有出处”；重试恢复标记；旧 head 或迟到响应不能错标当前正文；历史出处继续显示旧版本原文。扩展 `test/source_marks_test.dart`、`source_marks_real_ffi_test.dart`，新增 `test/operation_parity/source_state_test.dart`。

### R12 / P2：名称、搜索对象与重命名一致

**证据：静态确认。** sidebar 用 searchWorks 文案但过滤当前 chapters/lore；`workbench_dialogs.dart:48/93` 未全选初值，提交按钮固定 createAction。

**执行：** 章节页签写“搜索章节”，资料页签写“搜索资料”，作品选择器仍为“搜索作品”；切页签时明示筛选作用域并可一键清空。showTitlePrompt 支持按用途传提交文案；重命名显示“保存”，打开时选中原标题。新建仍用“创建”，空标题校验保持。

**验收：** 输入不存在章节词出现章节空态，清空恢复；资料搜索不改章节和作品。重命名直接输入新标题替换原值，Enter 保存、Escape 取消；目录/标题同步且正文不变。中英都测。更新 `test/writing_features_test.dart` 中当前点“创建”完成重命名的旧断言，不删除测试。

### R13 / P2：工具栏按空间折叠，核心入口不丢失

**证据：静态确认 + 目标设计。** 当前有 1120/760 与文字缩放分支，核心遗漏已由 R02/R07 确认；长英文标签、焦点和极窄约束仍需运行验证。

**执行：**

1. 按实际可用 constraints 与文字缩放决定文字/图标/更多层级；不按“Windows/移动设备”硬分布局，不通过强行缩小字体解决溢出。
2. 常用写作动作优先，低频工具进入分组菜单。保留章节/版本、导出、语言、模型、备份及全部已有功能；重复入口可以收敛，但要有明确新位置。
3. 保存失败允许占优先空间；可在内容外显示可操作错误条，不能被固定章末或工具栏覆盖。
4. 可聚焦控件保留可见焦点、语义名称、禁用原因及合理目标区域；错误不能仅用颜色，窄窗不能仅靠悬浮提示。
5. 专注模式仍有明确退出入口；目录折叠后可重新打开，drawer 操作完成后返回正文。
6. 主题和字体沿用既有暖白纸面，不为本次整改新增字体、网络资源、动画依赖或第二套主题系统。

**验收：** 第 7 节尺寸矩阵无 overflow/遮挡/丢入口；仅键盘可完成查找、重开讨论、资料预览、重命名、恢复导出及退出专注。中英、200% 缩放均有可读动作文字或可访问名称。

### R14 / P1：能力、保存与采纳提示真实

**证据：静态确认的能力边界 + 保持项。** `cowrite/discussion_thread.dart:createChapter` 令 target/anchor=null；valid=false，DiscussionPanel 禁用生成。当前已存在选段生成/候选业务接口和历史合成验证，不应因 UI 整改重造协议或绕过它们。

**执行：** 整章面板说明当前可保留草稿/查看历史，生成不可用时解释原因；不伪装整章模型可用，也不把整章偷偷转换为全选正文请求。明确保存的是编辑稿、确认是正式版本、采纳是候选写入编辑稿。候选过期或目标失效时展示原因和历史，禁止采纳；请求材料/输出语言变化使旧票据失效并重新预览。

**验收：** 保存不新增正式版本；生成预览不改正文；取消预览不发送；合成候选明确采纳后单步 undo，重复采纳不重复写。过期、迟到、切章、引用变化、revision 冲突拒绝写入。20 万字 × 4 操作后再编辑线程草稿并冷启动，作者快照没有重复持久化服务端请求/候选。真实外网仍为 NOT_RUN，不能为验收自行读取 Key 或发付费请求。


## 6. 执行顺序、交付单位与停止边界

### 6.1 分批顺序

| 批次 | 内容 | 依赖和出口 |
|---|---|---|
| A：先恢复可信反馈 | R01 保存订阅、R02 失败恢复、R04 资料请求竞态、R12 对象文案 | 先建立失败/竞态测试；保存与错误入口可靠后再大改纸面 |
| B：统一偏好和阅读位置 | R03 宽稿、R05 连续纸面与实际 scroll | A 通过；几何、输入和滚动恢复全部验证后进入讨论布局 |
| C：恢复就地协作 | R06 单活动槽、R07 完整索引、R08 选区落点 | B 通过；草稿/标记/失效讨论/焦点不丢，旧线程 ID 保持 |
| D：查阅与键盘收口 | R09 资料卡、R10 快捷键、R11 出处状态、R13 适配 | C 通过；资料往返、模态隔离及窄窗核心入口通过 |
| E：整体行为复验 | R14 全链路不变量、第 7 节矩阵 | 同一最终构建；合成真实 FFI 和 Windows 证据分开记录 |
| F：文档和产物收口 | R15 文档职责、R16 文件清理 | 先保留有效最终包、manifest 和失败证据，再逐项清理 |

普通实现选择由实施 Agent 自行推进。不要在每个任务完成后反复询问“是否继续”。本轮文档交付后不自行进入 A；以后用户要求按本文执行即可在已授权范围内开始。

每批次交付：实际改动清单、R 编号与状态、命令及退出码、测试断言和数量、同一构建证据、剩余未测项。不能把“代码有了”“analyze 通过”或按钮能打开作为整个批次完成。

### 6.2 实施前一次性记录

1. 阅读 F 的 AGENTS、本文、progress 及对应证据；只读读取 O 的当前方向和交互基准。按任务设置中文会话标题。
2. 记录两仓库 HEAD、git status、已有修改列表与主要编辑文件 hash；保留 dirty/untracked 树，不 reset/stash/clean 或覆盖其他 Agent。
3. 确认当前没有另一负责人修改同一批文件或占用相同 target；构建和真实桌面操作串行执行。
4. 核对已安装 SDK、Rust MSVC、编译工具和项目锁文件；不改 rustup 全局 default，不临时升级 Flutter/FRB/依赖。
5. 先读当前测试和接缝，最小复现对应问题。一个批次只改相关职责，不能把 UI 整改扩大为 Riverpod/路由/Drift 或编辑器框架替换。
6. 原有巨型文件是待收敛对象。增加职责时拆出有明确名称的小组件/控制器；普通函数目标 40 有效行、上限 60，生产模块目标不超 400 行；不能继续往 600 行界面文件堆逻辑。
7. 只创建合成测试材料，记录其生成方法与 hash；不从作者库抽样作为 fixture。

### 6.3 真正需要停止的情况

- 作者数据/凭据或真实付费请求缺少明确授权：完成不依赖它们的合成实现，记录对应真实验收 NOT_RUN，不读取或外发。
- R05 若无法在保留虚拟化、IME 和精确坐标的情况下达标：留下失败复现与两个具体方案/代价，不用退回普通 TextField、取消线程或改常驻侧栏换“通过”。
- 同路径出现他人同时写入、产物身份不明、唯一文件待删除或 junction 目标不明：仅停止受影响写入/清理，继续独立且已授权的工作。
- 实际工具审批拒绝时说明拒绝动作和原因；不能把本文设计规则说成工具已批准。

## 7. 验证计划与可执行入口

### 7.1 合成材料

| 编号 | 构造 | 用途 |
|---|---|---|
| S1 | 两作品 A/B，各三章；名字只使用“合成作品 A/合成章节一”等测试标识 | 作品、章节、偏好、异步身份隔离 |
| S2 | 两字短章、30 段中章、20 万字多段章、20 万字无换行章；固定 seed 生成 | 纸面几何、滚动恢复、虚拟化与性能 |
| S3 | 中文、Latin、emoji surrogate pair、组合字符、阿拉伯文混排；保留原 CRLF/LF/BOM 合同向量 | UTF-16/标量、复制导出、排版与 IME |
| S4 | 三个有效线程、一个失效线程、一个整章线程；同段放两个标记，各有不同草稿/引用 | 索引、展开、持久化、重开、标记独立可达 |
| S5 | 人物甲、地点乙、世界规则丙；当前/历史版本分别有不同正文与出处 | 条目定位、预览/附加、历史快照 |
| S6 | 可控 Future/Completer 与现有 test-support 故障接缝 | 保存迟到、线程失败、冲突、资料 A/B 竞态、出处读取失败 |

所有材料只在独立合成命名空间产生；测试文件可带合成文字，不带私人路径/正文或 Key。生成候选使用本地合成响应和假 Key/loopback，外网默认拒绝。

### 7.2 必须有断言的行为矩阵

下表初始均为 NOT_RUN。实施记录需要分别填单元/widget、真实 FFI、原生结果，不能只填一个总 PASS。

| ID | 关联 | 操作 | 通过断言 |
|---|---|---|---|
| V01 | R01 | 无额外导航地编辑、挂起保存、完成保存 | dirty/saving/saved 依次刷新；未重建正文、未丢 undo |
| V02 | R01/R02 | 保存 error、CAS conflict、恢复基线与 durable 失败 | 状态和原因可见；不刷新期望 revision 强行覆盖 |
| V03 | R02 | 窄窗失败后键盘重试、恢复导出并取消/写失败 | 操作可达；取消无成功；内存最新稿保留 |
| V04 | R02/R14 | 保存等待期间继续输入，再切章或退出 | drain 覆盖新增编辑；失败不离页；成功冷启动读回一致 |
| V05 | R03 | A 宽稿、B 舒适，切换并正常重启 | 各作品偏好恢复；layout 变化不清 undo |
| V06 | R04 | A 请求未完成切 B，再依不同顺序完成 A/B | 最终仅 B 数据，loading 能结束；旧请求不清新状态 |
| V07 | R05 | 短章、长章顶部/中部/底部滚动 | 标题和真实章末随纸面流动，无固定章末或空白视口 |
| V08 | R05 | 非零 scroll 重启、缩短正文、显式出处跳转 | 最近章节恢复且合法钳制；显式跳转不被迟到恢复覆盖 |
| V09 | R05 | 文字缩放/宽稿/长标题后点击、拖选、中文输入 | 绘制、hit test、caret、IME 候选窗同一位置，原文不变形 |
| V10 | R06 | 三线程交替展开、收起、滚出/滚回 | 单活动槽；收起不占空间；草稿引用和标记完整 |
| V11 | R06/R07 | 同段双标记、失效目标、索引重开 | 标记各可点击；失效历史可读，无旧坐标/相似句重绑 |
| V12 | R07 | 360 宽重开已有/整章讨论 | 索引可达；ID 不变、不隐式创建；有标题和关闭按钮 |
| V13 | R07 | saveThread 失败、重试、关闭重开 | 错误可见，草稿不丢，dirty 纳入屏障，持久读回一致 |
| V14 | R08 | 鼠标/Shift 选区，视口底部创建讨论 | 引文精确，卡片与输入框可见并可直接输入；正文不变 |
| V15 | R08/R09 | 正文→讨论→资料→关闭→收起→续写 | 返回发起控件，最后回目标末尾；滚动/selection/undo 延续 |
| V16 | R09 | 预览甲、带入甲、移除、改当前资料再看旧请求 | 预览不附加；只带指定资料；历史快照不变 |
| V17 | R10 | 正文、重命名、资料、讨论中 Ctrl+F/S/Z/Y | 只作用于当前范围；不穿透模态；菜单能力不取旧选区 |
| V18 | R10 | 菜单/查找/讨论/专注叠加，逐次 Escape | 每次只退最内层，焦点恢复；无强行取消 IME |
| V19 | R10 | 微软拼音组合、选候选、取消、选区替换、切焦点 | 不抢 Enter/Escape，无重复/丢字，候选窗位置正确 |
| V20 | R11 | 出处加载空、失败、重试、旧 head 迟到 | 四态可辨；错误可重试；不发布过期装饰 |
| V21 | R11 | 打开旧版本出处 | 精确历史原文只读；不伪装当前正文或相似搜索结果 |
| V22 | R12 | 中英搜索、直接输入替换标题、Enter/Escape | 搜索对象准确，保存/创建分场景，正文保持 |
| V23 | R13 | 目录收起/抽屉、所有核心菜单、保存失败状态 | 所有尺寸和缩放均可达，无 overflow、遮挡或键盘陷阱 |
| V24 | R14 | 合成生成预览/取消/采纳/拒绝/过期/重复采纳 | 无自动写正文/正稿；CAS 拒绝过期；单步 undo；无重复请求 |
| V25 | R14 | 20 万字四操作后编辑线程草稿并冷启动 | 作者快照不复制 operation，正文/草稿/hash 一致 |
| V26 | R02/R10 | X、Alt+F4、现有退出入口；失败/导出后继续/明确退出 | 共用关闭决策；失败留窗留稿；composing 不强丢 |
| V27 | R05/R06 | 复制/导出含讨论、标题、出处标记的章节 | 输出仅约定正文/资料，UI 占位、讨论和候选不混入原文 |
| V28 | R16 | 清理后从保留依赖重建、独立包运行与失败闭合 | 实际释放量可核对；无丢源码/数据；产物和验证身份对应 |

布局矩阵使用**逻辑像素**，固定测试 physicalSize 与 devicePixelRatio：360×720、600×800、900×700、1440×900、1920×1080；中英 UI 各测 100%/200% 文字缩放，长标题和无匹配空态进入矩阵。不要把物理分辨率直接填成逻辑尺寸。

真实 Windows 至少覆盖本机现有 DPI 与 100%/150% 两档可用条件；多屏/DPI 切换没有设备条件时记录 NOT_RUN。RTL/混排验证可使用现有 harness，但不能由此宣称正式发布阿拉伯文 UI。标题栏拖动、缩放、最大化/还原及模态隔离沿用现有窗口回归。

性能在 profile 构建、相同合成材料和同机条件下记录原始分位数/帧记录。旧 M3 可行性结果不能直接继承；新的连续纸面不得通过全量排版整章或关掉虚拟化掩盖几何问题。输入 P95 的既有 50ms 目标与已接受限制要同时报告。

### 7.3 测试文件落点

`test/operation_parity/` 是本文建议新增目录，当前不存在；实施后才运行它。优先复用现有 harness，不再复制整套启动/fixture。建议文件与 R 对应：

- `save_status_test.dart`：R01/R02；`lore_scope_test.dart`：R04。
- `paper_flow_test.dart`、`scroll_restore_test.dart`：R03/R05；包含真实布局和 offset 断言。
- `thread_host_test.dart`、`discussion_index_test.dart`：R06–R08；包含不同线程 ID、草稿和失效分支。
- `reference_flow_test.dart`：R09；`focus_shortcuts_test.dart`：R10；`source_state_test.dart`：R11。
- R12/R13 扩展既有 `test/writing_features_test.dart`、`m2_workbench_test.dart`、`m2_locale_test.dart`。
- 领域/增量布局回归继续放 `test/editor/`、`test/cowrite/`；持久化、关闭、真实 FFI 继续扩展现有 m4/source/reviewed 测试，不伪造 mock “原生通过”。

### 7.4 后续执行命令

下面是分阶段入口，**不是本轮已运行记录**。执行前确认目录、参数和当前脚本仍一致；依赖从现有锁文件恢复。一个命令失败即记录退出码并处理，不能靠管道只留下最后一条成功状态。

```powershell
$parityRoot = 'D:\MyAgent\paraselene-flutter'
$parityApp = Join-Path $parityRoot 'apps\desktop'
$parityFlutter = 'D:\flutter_sdk\flutter\bin\flutter.bat'
$parityDart = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe'
$ErrorActionPreference = 'Stop'

function Invoke-ParityCommand(
    [string]$Executable, [string[]]$Arguments, [string]$Directory
) {
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

# 记录实际环境；不要用文档日期推断版本。
Invoke-ParityCommand $parityFlutter @('--version') $parityApp
Invoke-ParityCommand $parityDart @('--version') $parityApp
Invoke-ParityCommand 'cargo' @('+stable-x86_64-pc-windows-msvc', '--version') $parityRoot

# 修改 ARB 后先生成；保持 en/zh/zh_Hans 的键和占位符一致。
Invoke-ParityCommand $parityFlutter @('gen-l10n') $parityApp
& (Join-Path $parityRoot 'scripts\check-m2-l10n.ps1')
if ($LASTEXITCODE -ne 0) { throw 'ARB parity check failed' }
Invoke-ParityCommand $parityDart @(
    'format', '--output=none', '--set-exit-if-changed',
    'lib', 'test', 'integration_test', 'bin'
) $parityApp
Invoke-ParityCommand $parityFlutter @('analyze', '--fatal-infos') $parityApp

# 新目录实施后使用；没有目录不能记作跳过后通过。
if (!(Test-Path -LiteralPath (Join-Path $parityApp 'test\operation_parity'))) {
    throw 'Operation parity tests have not been implemented'
}
Invoke-ParityCommand $parityFlutter @('test', 'test/operation_parity') $parityApp
Invoke-ParityCommand $parityFlutter @(
    'test', 'test/editor', 'test/cowrite', 'test/writing_features_test.dart',
    'test/m4_controller_test.dart', 'test/m4_lifecycle_test.dart'
) $parityApp
```

普通真实 FFI 回归使用生产能力 DLL，owned 专项使用独立 test-support DLL 和独立 runId。脚本应保存/恢复原环境变量，禁止把测试 DLL 复制为正式分发件。

```powershell
$parityManifest = Join-Path $parityRoot 'rust\Cargo.toml'
$parityProductionTarget = Join-Path $parityRoot 'build\rust-m1-msvc'
$parityTestTarget = Join-Path $parityRoot 'build\rust-m4-test-msvc'
$parityPreviousDll = $env:PARASELENE_M1_DLL
$parityPreviousRun = $env:PARASELENE_M4_RUN_ID
try {
    Invoke-ParityCommand 'cargo' @(
        '+stable-x86_64-pc-windows-msvc', 'build',
        '--manifest-path', $parityManifest, '-p', 'paraselene-bridge',
        '--target-dir', $parityProductionTarget, '--locked', '--offline'
    ) $parityRoot
    $env:PARASELENE_M1_DLL = Join-Path $parityProductionTarget 'debug\paraselene_bridge.dll'

    # 明确列出两个分开的门禁；普通回归不宣称包含 owned 或 golden。
    $parityOrdinaryFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $parityApp 'test') -Recurse -Filter '*_test.dart' |
        Where-Object { $_.Name -notin @('m4_owned_repository_test.dart', 'm2_golden_test.dart') } |
        ForEach-Object { $_.FullName }
    )
    if ($parityOrdinaryFiles.Count -eq 0) { throw 'No ordinary tests discovered' }
    Invoke-ParityCommand $parityFlutter (@('test') + $parityOrdinaryFiles) $parityApp

    Invoke-ParityCommand 'cargo' @(
        '+stable-x86_64-pc-windows-msvc', 'build',
        '--manifest-path', $parityManifest, '-p', 'paraselene-bridge',
        '--features', 'test-support', '--target-dir', $parityTestTarget,
        '--locked', '--offline'
    ) $parityRoot
    $env:PARASELENE_M1_DLL = Join-Path $parityTestTarget 'debug\paraselene_bridge.dll'
    $env:PARASELENE_M4_RUN_ID = [guid]::NewGuid().ToString('N')
    Invoke-ParityCommand $parityFlutter @(
        'test', 'test/m4_owned_repository_test.dart'
    ) $parityApp
} finally {
    $env:PARASELENE_M1_DLL = $parityPreviousDll
    $env:PARASELENE_M4_RUN_ID = $parityPreviousRun
}
```

注意：全量 app 测试前再次核对新增测试清单，不能无筛选跑整个 Rust workspace 的 examples/凭据或付费专项。Rust 源码未变时无需虚增“本轮 Rust 单测通过”；若改业务/bridge，按实际受影响 package 执行 fmt、test、clippy（MSVC、locked/offline、`-D warnings`），FRB 变化用既有 `scripts/generate-m1-bridge.ps1` 重生，不手改 generated 文件。

最终门禁还有：

1. `flutter test test/m2_golden_test.dart`：单独报告。当前既有失败/旧基线需要解释；先通过非 golden 几何、行为与可访问性测试，再在固定字体/SDK/DPI 条件下审阅差异并有意重批。禁止自动 --update-goldens 抹掉失败。
2. `flutter build windows --release`：正式包构建，使用现有 CMake 构建生产 Release DLL。
3. Windows integration 按文件串行运行：`integration_test/m1_app_test.dart`、`m2_app_test.dart`，以及用独立 test-support DLL/runId 的 `m4_app_test.dart`。不能因多文件连接工具故障忽略后一个文件。
4. 独立包：`pwsh -File scripts/verify-m1-bundle.ps1 -EvidenceDirectory <本批独立证据目录>`。该脚本创建 GUID 副本并测试缺 DLL 失败闭合，指定新证据目录，避免覆盖旧 M1 最终记录。
5. 同一正式 Release 的真实 Windows 交互、IME、系统导出取消/写入/UTF-8 读回、关闭失败恢复和窗口矩阵。widget 的 native_close mock 不构成 WM_CLOSE 证据。
6. 净机/安装与作者数据接管没有条件时保持 NOT_RUN；独立复制包通过不能代替它们。

### 7.5 验收记录格式

实施时在 `docs/evidence/operation-parity-20261020/` 新增证据，批次目录可用 A/B 等明确命名。当前只交付本文，没有提前创建该目录。

每条记录至少包含：R/V 编号；源码提交或工作树快照 hash；产物 exe/DLL/manifest hash；实际 SDK/toolchain；构建时间和运行参数；synthetic runId；逻辑尺寸/DPI/文字缩放/locale；操作与断言；命令和退出码；PASS/FAIL/NOT_RUN；截图/日志/原始性能数据；失败原因和下一动作。

最后一轮才做完整设计/操作复看。修复一个已确认行为后跑相关定向测试，最终统一跑必要回归；无新改动或未决问题时不无限重复整套门禁。

## 8. R15：整理文档入口，不删除工程记忆

本节仅规定后续实施阶段的维护方式；本轮没有改这些文档。目标是减少“新 Agent 看到互相矛盾状态”的认知负担，不靠删掉证据提高整洁度。

| 现有材料 | 当前问题或职责 | 后续处理 |
|---|---|---|
| `README.md`、`apps/desktop/README.md` | 根 README 仍主要介绍 M0–M2/只读正文，落后于已存在实现 | A–E 实际验收后更新当前入口和能力，链接本文与最新证据；逐项区分已实现/未测 |
| `docs/progress.md` | 多轮接续、旧状态和最新状态并存 | 在顶部维护一张当前状态表与证据指针；历史追加记录保留，不把旧 PASS 直接搬到新构建 |
| `docs/M3-PRODUCTION-EDITOR-PLAN.md` | 文档头仍是旧草案，部分实现已出现 | 建立“原条目→已实现/仍有效/被替代→代码/证据”映射，再改为历史方案或归档；不能重新按旧授权状态推翻后来事实 |
| `docs/ADR-003-editor-spike.md`、`ADR-004-m4-synthetic-persistence.md` | 记录编辑器路线与合成持久化边界 | 继续保留；新的选择另记决策及原因，不重写历史 |
| `docs/evidence/UI-PARITY-20261020.md` | 视觉对齐证据，不能承载本次行为通过声明 | 保留历史，在当前入口链接操作整改结果，说明两者验收范围 |
| `docs/evidence/CLICK-TEST-20261020.md` | 特定构建、特定真实点击范围和未测项 | 保留，重新测试另存新证据；不改写当时 NOT_RUN |
| `P/MIGRATION_PLAN.md` 及映射/快照 | AGENTS/README 仍指定的合同与迁移来源 | 继续保留，不删除整个 migration 目录，也不由本次 UI 整改重新发起迁移 |
| BRIEF/REPORT/HANDOFF、spike 说明 | 有重叠叙述，但可能是唯一失败/决策依据 | 先归属、去重映射和链接修复，再考虑单个归档；不按文件名/日期批量删 |

最终维持：README 负责启动与当前能力；progress 负责当前状态；本方案负责整改目标；evidence 负责实际结果；ADR/旧方案负责历史原因。新记录的责任不能反复复制到许多“最终报告”。


## 9. R16：文件清理的精确范围与操作规则

### 9.1 结论与统计方法

磁盘大头是编译缓存和重复分发副本。优先清理这些产物，收益远大于删工程文档；`legacy` 和许多 untracked 文件仍是正式功能，不能“看着旧”就删除。

下表为 **2026-10-20 16:02:01 +08:00** 对 F 下指定白名单目录重新统计的元数据：1 MiB=1,048,576 bytes，1 GiB=1,024 MiB；读取文件长度，不读取文件正文；遇 reparse/junction 只计跳过数、不递归目标。存在硬链接/压缩/稀疏文件时，逻辑长度不等于实际可释放磁盘簇，清理后另测磁盘变化。

前七项逻辑长度合计 **11,000.39 MiB，约 10.74 GiB**。这是可再生分类总量，**不是立即可删量或承诺释放量**：其中有要保留的最终包、运行中依赖，以及含 28 个 reparse 的测试树。

### 9.2 指定路径台账

下列路径均从 F 根目录解析；任何未列出的目录默认不在本轮清理白名单。

| ID | 精确相对路径 | 文件数 / MiB / 跳过链接 | 分类 | 执行条件、重建依据 |
|---|---|---|---|---|
| C01 | `build/rust-m1-msvc/` | 14087 / 8216.80 / 0 | 可再生，条件清理 | 保留当前有效完整 Release 后；关闭相关 EXE/DLL/构建占用；按 `windows/rust_bridge.cmake` 的 MSVC locked/offline 命令重建 |
| C02 | `build/rust-m4-test-msvc/` | 3012 / 1769.15 / 0 | 可再生，条件清理 | test-support 单独 target；保留对应专项证据；用 `scripts/check-m4.ps1` 的独立目标参数重建，不混入生产包 |
| C03 | `rust/target/` | 1538 / 383.61 / 0 | 可再生，条件清理 | 检查是否仍有默认 target 使用者；不改 Cargo.lock；以后构建显式指定目标目录 |
| C04 | `apps/desktop/build/` | 413 / 314.01 / 0 | 可再生，条件清理 | 先在候选目录外保存一份当前完整、可验证的正式包与 manifest；不能只留 exe；flutter build windows --release 重建 |
| C05 | `build/learning-native/` | 6143 / 247.73 / 28 | 含链接，暂不按普通缓存删 | 由原生隔离专项产生 junction 夹具；先审查链接本体与目标边界、拆除链接本身并复核，不能对整树直接递归删除 |
| C06 | `apps/desktop/.dart_tool/` | 27 / 41.77 / 0 | 可再生，条件清理 | Pub 缓存/SDK 可用；`flutter pub get --offline` 恢复；不要连带删 pubspec.lock |
| C07 | `packages/text_contract/.dart_tool/` | 4 / 27.32 / 0 | 可再生，条件清理 | 纯 Dart 包内 `dart pub get --offline`；源代码和 lock 保留 |
| C08 | `build/vendor/` | 91 / 51.44 / 0 | 当前必须保留 | WebView2 SDK 等构建硬依赖；不因位于 build 判废；下载缓存与固定 hash 是离线重建条件 |
| C09 | `spikes/editor_comparison/` | 111 / 275.73 / 4 | 混合目录，整体保留 | 实验源码、缓存、字体 staging 混在一起；仅单独核实 build/.dart_tool 等子项后处理；保留性能/IME基线 |
| C10 | `spikes/codemirror_baseline/` | 236 / 25.90 / 0 | 源码保留，产物可核实清理 | `dist/`、`browser-profile/`、`.vite-cache/` 可再生；build.mjs/run.mjs/summarize.mjs 和说明保留 |
| C11 | `apps/desktop/test/failures/` | 8 / 0.48 / 0 | 当前保留 | tracked 且已有修改；先解释 golden 差异并完成新视觉验收，再决定单个 failure artifact 去向 |
| C12 | `apps/desktop/test/goldens/` | 2 / 0.11 / 0 | 必须保留 | m2_golden_test.dart 直接使用；不能用 failures 文件覆盖 |
| C13 | `docs/evidence/` | 891 / 8.72 / 0 | 证据条件归档 | 保留最终结果、首次/唯一失败与 IME/FFI/持久化/关闭证据；按来源映射归档，不按数量批量清空 |

C09 的 `apps/` 是实验 Flutter 字体 staging 的历史目录名，不代表第二套正式应用；实际处理前读其 .gitignore 与 prepare-fonts.ps1，不能按名字类推删除正式 apps。C10 生成基线还依赖 O 的只读源码/已安装依赖和字体，不能为重建清理 O。

### 9.3 分发副本：逐个核对后收敛

目前以下 11 个目录均为 65 文件、未发现 reparse；合计 **1,241,497,842 bytes / 1183.98 MiB / 约 1.16 GiB**。名字和尺寸相近不足以证明完全相同，不能称“11 份字节重复”。

| ID | F 下精确目录 | MiB |
|---|---|---|
| D01 | `build/m1-distribution-0601b9ecf9714e4bbace6fea49b253f0` | 107.70 |
| D02 | `build/m1-distribution-0f14da37d8d24792a954f620ebd14bb6` | 107.62 |
| D03 | `build/m1-distribution-11cc63a18d03451cb0aa2b3642525810` | 107.62 |
| D04 | `build/m1-distribution-393029de294444c5b2c35c2c20979c2f` | 107.63 |
| D05 | `build/m1-distribution-4a552174e0c44c7d80b23e76416b7d6e` | 107.62 |
| D06 | `build/m1-distribution-539908b16847424699f0bfe82145b672` | 107.62 |
| D07 | `build/m1-distribution-703462be59544eb79a51538de1f79859` | 107.70 |
| D08 | `build/m1-distribution-80451878655546a6bc66c2ef566aec04` | 107.56 |
| D09 | `build/m1-distribution-8c5c1da0f2eb4453b851d337b55258bd` | 107.62 |
| D10 | `build/m1-distribution-952d79ba895f471e84c1a95a6b956fef` | 107.62 |
| D11 | `build/m1-distribution-d1093976dc7f4e1fbfa2e630b64e733c` | 107.70 |

来源为 `scripts/verify-m1-bundle.ps1:9`：每次验证创建新 GUID 副本，没有把先前副本自动收敛。

处理步骤：

1. 对 D01–D11 各自产生相对文件路径/长度/SHA256 manifest，关联其已有 copied-bundle-status/report 与验证日期，确认测试 DLL 没有混入。
2. 选择**实际通过验证的最新正式包**保留；若旧版本是唯一可用回退包，再保留该明确版本。不得按修改时间或目录排序猜哪个通过。
3. 将保留包放在不属于 C01–C07 的明确 release/archive 路径，保留完整 DLL/Flutter data/字体/许可证与 manifest；本轮文档阶段不创建该目录。
4. 其余目录只有在“被何包取代、证据已保留、没有唯一文件”三项明确时才进入删除白名单。至少一个有效包的容量不计入预计释放量。
5. 后续修订验证脚本的产物生命周期：证据目录/runId 与包 manifest 对应；失败包保留至诊断完成，成功包按明确保留集收敛。不能每次都留下不可追溯的 100MiB 目录，也不能验证后立刻删掉唯一失败现场。

### 9.4 仍被生产引用，必须保留

| 路径 | 已确认的依赖或用途 | 后续规则 |
|---|---|---|
| `apps/desktop/lib/legacy/` | RealWorkspaceRepository 导入并暴露 LegacyRepository；editor_tools 使用历史/记忆/角色/导入/想法/审阅；workbench 与 native gateway 引用 companion/learning | 不是死代码。若以后改名为 capabilities/adapters，先迁移引用和测试再删旧路径；本次保留 |
| `apps/desktop/lib/editor/`、`cowrite/`、`lore/`、`window/` | 正式编辑、讨论、资料、窗口实现 | untracked 也不能删除 |
| `rust/application/`、`rust/bridge/`、`rust/core/`、`packages/text_contract/` | 正式业务、桥接、核心与跨语言文本合同 | 保留源码、schema、锁文件；不要把 Cargo 源目录当 target |
| `apps/desktop/assets/companions/`、`apps/desktop/assets/learning/`、字体/许可证 | pubspec.yaml 直接引用并打包 | 不因当前默认写作入口不用就移除；先有明确产品范围调整及完整依赖迁移才处置 |
| `tests/learning_native/` | check-learning-native.ps1 的 CMake 源目录 | 测试源码，不能与 build/learning-native 混淆 |
| `apps/desktop/lib/probe/`、`bin/m1_probe.dart` | main 与 M1 验收脚本使用 | 保留至替代入口有真实同等验收 |
| `apps/desktop/bin/m4_scope_probe.dart`、`integration_test/m4_native_probe.dart`、`integration_test/support/window_probe_trace.dart` | DLL 身份、失败闭合、原生关闭诊断 | 保留；没有常规调用不代表无用 |
| `apps/desktop/bin/m2_runtime_retry_probe.dart` | 常规调用关系尚未完整证明 | 暂保留；先列目的、被哪份证据使用、有无替代 |
| `.superpowers/sdd/progress.md`、AGENTS、配置/生成入口 | 既存流程记录与工具入口 | 不以隐藏目录为由清理；不能改写已有负责人记录 |
| `docs/evidence/`、goldens、锁文件 | 回归与重建依据 | 小而关键；失败并不是可删除理由 |

尤其禁止 `git clean -fdx`、`reset --hard`、整体清空 build、批量删除 untracked 或依据名称含 legacy/temp/test/synthetic 判废。旧实现退出默认菜单和删除它的数据/代码是不同决定。

### 9.5 未证明归属，排除在清理之外

- F 的 `build/m4-owned-synthetic-v1/`、`build/m4-owned-test-v1/`：只确认目录存在，没有扫描其内容。即使含 synthetic/test 名称，也不能自动删除持久化库。
- F 的 `build/comment-work/`：归属和唯一性未证明，保留。
- F 的 `build/full-suite-after-restyle.log`、`lifecycle-one.log`、`lifecycle-t1.log`：先提取对应结果/失败诊断并纳入证据映射，再考虑单项清理，不提前删除失败日志。
- O、P、`D:\MyAgent\paraselene-installed-acceptance`：只读对照/迁移依据/旧安装验收，不在此清理范围，不运行卸载器。
- `D:\MyAgent\toolchain-downloads`：FRB codegen 等有默认引用；本方案不删。
- MyAgent 顶层的 `build-tools`、`codex`、`docs`、`.font-source`、`.font-tools`、`.pnpm-store`、浏览器 profile、`.computer-use-probe`、临时探针目录、同步脚本、聊天导出、旧进度文件：归属未完整确认，全部排除。
- 任何 .git、数据库/WAL/SHM、作者作品/导出、.env、Key、token、认证或未提交正式实现：不读取内容、不归档复制、不删除。本节磁盘统计也不延伸到它们。

### 9.6 实际清理流程

以后用户要求执行清理时，按以下顺序直接完成已证明的候选；普通可再生文件不需要逐项重复询问。归属不明项保留并说明，不能把保留项偷偷纳入批量命令。

1. **冻结当前状态。** 记录 git status、文件 hash 和允许范围；确认没有其他构建正在写入。只检查精确相关进程及 DLL，不粗暴结束所有同名应用，不关闭用户其他窗口。
2. **保留可运行交付。** 按 9.3 选定有效完整正式包与必要回退包，保存对应报告/manifest；若不存在有效包，先构建/验证，不能先删全部产物。
3. **逐项证明可再生。** 记录 SDK、离线 Pub/Cargo/原生依赖、源锁文件、重建命令。缺 WebView2/工具链时保留依赖；不能先删后以“需要联网”收场。
4. **验证绝对路径。** 使用 GetFullPath/Resolve-Path 和“根目录 + 分隔符”的 OrdinalIgnoreCase 包含判断；拒绝根目录本身、父目录、空值和前缀碰撞。验证目标为白名单中的精确路径。
5. **验证整棵候选树。** 不跟随 reparse 枚举所有下级；任意层发现 junction/symlink 就停止该树普通递归清理。C05/C09 先进入链接专项，不只验证顶层就递归。
6. **核对 Git 身份。** 用 git ls-files 与 git check-ignore 检查候选内是否混有 tracked 或唯一 untracked 源码。ignored 只是信号，不是删除许可；全局 ignore 读取失败要记录限制。
7. **生成 review 台账和 dry-run。** 每项写：ID、解析后绝对路径、bytes/file count、链接数、git 分类、引用/重建证据、保留包 ID、保留证据、计划动作。只对核验过的明确路径先运行原生 Remove-Item/Move-Item 的 -LiteralPath + -WhatIf。
8. **按台账逐项执行。** 使用同一个 pwsh 进程与原生 cmdlet；禁止拼 cmd /c、rd、另一个 shell 或把 rg 输出拼成删除命令。失败就记录该项并停它，不换粗暴删除方式。未知内容需保留，不能用强制删除解决权限/归属问题。
9. **重建与复验。** 执行必要重建入口和 V28，记录真实释放量、保留路径、失败项及离线重建结果；再次核对源码和原工程状态未变。
10. **收敛新产物。** 验证生成的新 GUID 包也进入同一台账，保留集明确后再处置多余副本，避免清理工作自身制造更多垃圾。

含链接的 C05/C09 需要先确认每个链接的夹具创建来源、目标和安全移除方法，只移除链接本体且不遍历目标；没有完成专项证明时就保留该树，其余无链接候选仍可推进。不提供一条对整个 build 目录的递归删除命令。

### 9.7 主要重建入口

以下仅供后续清理与恢复使用，执行前先确认依赖已在本机。完整检查可能产生新缓存；清理前后都要记录这一点。

```powershell
# Flutter 产物和包缓存
Push-Location -LiteralPath 'D:\MyAgent\paraselene-flutter\apps\desktop'
try {
    & 'D:\flutter_sdk\flutter\bin\flutter.bat' pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency restore failed' }
    & 'D:\flutter_sdk\flutter\bin\flutter.bat' build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows rebuild failed' }
} finally {
    Pop-Location
}

# 纯 Dart 包的 .dart_tool
Push-Location -LiteralPath 'D:\MyAgent\paraselene-flutter\packages\text_contract'
try {
    & 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe' pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Dart dependency restore failed' }
} finally {
    Pop-Location
}
```

生产 Rust：`cargo +stable-x86_64-pc-windows-msvc build --manifest-path <F/rust/Cargo.toml> --package paraselene-bridge --target-dir <F/build/rust-m1-msvc> --release --locked --offline`。尖括号是路径占位，实际执行使用 7.4 的变量/参数数组，不能原样复制。test-support 用 7.4 的独立目标目录。

- `scripts/check-learning-native.ps1` 从 `tests/learning_native` 重建原生探针；需要现有 desktop Release/CMakeCache，且会再创建 junction 攻击夹具。
- `scripts/prepare-learning-sdk.ps1` 记录固定 WebView2 版本与 SHA256；网络或已保留 sdk.zip 是前置条件，故 vendor 当前保留。
- `spikes/editor_comparison/prepare-fonts.ps1` 从正式资产复制字体/许可证并核 hash；这不授权删正式字体。
- CodeMirror 基线使用该目录的 `node .\build.mjs`、`node .\run.mjs`、`node .\summarize.mjs`；保留源码与依赖，禁止为了基线去改 O。
- FRB 由 `scripts/generate-m1-bridge.ps1` 与 toolchain-downloads 中固定版本工具再生；不顺带升级协议或清理下载工具链。

## 10. 技术依据与工程定位

本次使用 `redesign-existing-projects` 审查已有界面和操作流程，使用 `context7-mcp` 核对 Flutter 接缝。用户“只新增一份文档”约束优先于技能默认直接修改 UI 的流程；本次未实施修复。

R05 的滚动方案遵守 Flutter ScrollController 约束：读取 offset 要有明确 position，连接不代表尺寸已计算，恢复前需确认内容尺寸就绪，窗口尺寸变化也需要处理。本文据此规定单一权威滚动状态与恢复时机，不把“外面再包一层滚动”当作解决方案。[Flutter ScrollController API](https://api.flutter.dev/flutter/widgets/ScrollController-class.html)

R10 的键盘方案依据 Flutter focus/shortcut 的焦点传播和作用域；按键处理先于文字输入，错误地截获按键会阻断输入。本项目还需在真实 Windows 输入法上证明 composing 和焦点转换行为，不能由文档推定通过。[Flutter focus system](https://docs.flutter.dev/ui/interactivity/focus)、[Actions and shortcuts](https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts)

### 10.1 重点源码定位

下列文件除 O 标记外均相对 F；是当前审计入口，不是本轮修改清单。

| 文件 / 符号 | 审计定位 |
|---|---|
| `apps/desktop/lib/workspace/presentation/manuscript_editor.dart` | _scroll:53、_onScroll:136、_syncHosts:237、_globalKey:254、_openThreadDialog:318、_openThread:342、_discussSelection:355、标题:412、正文:513、章末:543 |
| `apps/desktop/lib/editor/editor_viewport.dart` | 真实 scroll:116、_scroll:182、ensureCaret:186；同文件的 geometry/hit/gesture 都需适配 paper 坐标 |
| `apps/desktop/lib/editor/editor_discussion_overlay.dart` | 按 layout.threadSlots 全部挂载；与槽位/测量和稳定草稿 key 一起改 |
| `apps/desktop/lib/editor/editor_thread_slot.dart` | offset 为 UTF-16、height 为逻辑像素；不引入正文占位字符 |
| `apps/desktop/lib/workspace/presentation/workbench_screen.dart` | _wide:38、父监听:57、onWide:140 |
| `apps/desktop/lib/workspace/presentation/workbench_chrome.dart` | narrow 索引条件:199、更多 tools 缓存:362、窄窗菜单:412、保存展示:611、compact 返回:648 |
| `apps/desktop/lib/workspace/presentation/workbench_sidebar.dart` | _loadLore:82、_openLore:147、搜索文案:331、_resourceRow:650 |
| `apps/desktop/lib/workspace/workspace_state.dart` | wide/setWide、noteScrollTop、pendingScrollTop/markScrollApplied、偏好串行写入和 drain |
| `apps/desktop/lib/workspace/editing_session.dart` | 编辑/保存状态通知、contentEpoch、输入锁、flush；不可为 UI 改动绕过 |
| `apps/desktop/lib/cowrite/discussion_registry.dart` | 线程列表/草稿、事务映射、flush、discussion_save_failed、operation 投影 |
| `apps/desktop/lib/cowrite/discussion_panel.dart`、`discussion_thread.dart` | 面板输入/生成/采纳；持久线程 target/anchor 与整章能力边界 |
| `apps/desktop/lib/lore/source_mark_controller.dart`、`lore_library.dart` | 出处身份与 failed、initialEntry 定位、历史版本详情 |
| `O/src/features/studio/writing/useNotebook.ts` | 活动线程段末槽与关闭后 resume |
| `O/src/features/studio/writing/ParagraphEditor.tsx` | 保留选区、轻量选区操作、仅按章重建编辑器 |
| `O/src/features/studio/writing/NotebookSurface.tsx`、`useSurfaceReturn.ts` | 查资料时保留编辑器状态和阅读位置 |
| `O/src/features/studio/writing/ReferenceCard.tsx`、`DiscussionIndex.tsx` | 预览/带入/编辑分离、全部讨论记录 |
| `O/src/features/studio/native/nativeSession.ts` | 保存屏障、正式版本与不可变出处 |
| `scripts/verify-m1-bundle.ps1`、`apps/desktop/windows/rust_bridge.cmake` | GUID 分发副本来源、生产 DLL 重建与打包 |

### 10.2 当前工作树指纹

2026-10-20 16:02:01 +08:00 的重点文件 SHA256：

| F 相对路径 | SHA256 |
|---|---|
| `apps/desktop/lib/workspace/presentation/manuscript_editor.dart` | `93AC33B8E78AF3F540B03EA1D6AA0C9D150D127F9995D1D2D5307E0B613F3180` |
| `apps/desktop/lib/editor/editor_viewport.dart` | `A7B3986C7D974228F9B352A804F84B1E92177DFB6D84707AAADE821188D59EBF` |
| `apps/desktop/lib/workspace/presentation/workbench_screen.dart` | `E1908BDA2454571B2B85259C10E31254E8460C28B58F01E56B68C21FED69DF4F` |
| `apps/desktop/lib/workspace/presentation/workbench_chrome.dart` | `3ED4C75EBC1087EE34851A4513B5B2E1D6B88C7CD2D1B14953C93DE6DBF5C7BC` |
| `apps/desktop/lib/workspace/presentation/workbench_sidebar.dart` | `24D671DF60932C8BBFA34B642D1FC3ABC072409CD914A86D446BC171FAAA5B66` |
| `apps/desktop/lib/workspace/workspace_state.dart` | `7192DCCA3356AF51417733180115B1693C0AE4615018239D8A9397D45F48E7D5` |
| `apps/desktop/lib/cowrite/discussion_panel.dart` | `E42A1B9513144E05E9572E133600904443553C1E8D540BD2E18263723CE50A83` |
| `apps/desktop/lib/cowrite/discussion_registry.dart` | `14BD8B9A743F8261256E26B98B7E5D7D91662A48A0F79837ED1766BD71735F13` |
| `apps/desktop/lib/workspace/editing_session.dart` | `EFF42305A2A1A65921394FBA88F4D32416A1A803C9B06CDB77262B82E39B471E` |

完整 git status 使用 `--porcelain=v1 --untracked-files=all`，F 排除本文后 939 项、O 482 项；目录折叠模式会得出不同数量，不能据 939 推断新增了 939 份无用代码。全局 git ignore 路径存在读取权限限制，后续删除核查必须显式记录该限制，不能声称扫描过所有全局忽略规则。

## 11. 本轮交付与后续起点

本轮产物只有 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md`。已完成差异整理、R01–R16 任务定义、V01–V28 验收矩阵、目录占用复核、清理保留边界与重建入口。

文档交付核验：16 个任务定义、28 条验收行齐全；3 段 PowerShell 示例通过 PowerShell 7 语法解析（未执行示例）；28 个显式引用的现有工程文件路径存在，9 个重点源码 SHA256 与审计快照一致；Markdown 代码围栏成对，无异常控制字符。排除本文后，两仓库的完整 git status 与 tracked diff 摘要均与审计基线一致，确认本轮没有改动既有源码、测试或其他已记录文件状态。

**应用修复、测试、构建、真实窗口操作、数据库接管、模型请求和文件清理均未执行。** 不据本文更新 M3/M4/M9 为完成，不把历史 PASS 继承为当前验收。

后续实施第一批为 **R01 + R02 + R04 + R12**：先修可信保存反馈、失败恢复和作品资料竞态，再做连续纸面与讨论布局；清理按 R16 在保留有效交付后逐项执行。


