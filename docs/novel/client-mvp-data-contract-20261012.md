# CLIENT-MVP：数据闭环审查与 B 阶段适配合同

日期：2026-10-12。负责人：codex/data_audit。状态：**只读审查完成 / 合同待实施 / 原生验收 NOT_RUN**。

依据 [客户端最低可用计划](client-mvp-plan-20261012.md) 第 6 节数据闭环审查任务。已读 AGENTS.md、README、当前方向、进度看板、DESIGN.md、项目地图、代码规范、小说模块入口及 [段落 UI 证据](../evidence/PARAGRAPH-UI-20261012.md)，核查活动 Notebook 与旧正式内核。此次仅编写本合同，不改产品代码、不读取作者作品库、不使用 Key、不调用模型。

所有发现均为**代码确认**；下面的复现步骤是可执行验收脚本，不表示已经运行。P0/P1 均保持**待实施**。历史 PASS、浏览器预览和代码存在不能替代本轮原生验收。**A 阶段尚未完成原生交互验收，不能标记 B 通过；本合同完成也不表示 B 已实施或离线写作已通过。**

路径均相对工作副本 `D:\MyAgent\paraselene-work`。行号对应审查时源文件；后续修改可能移动。

## P0：已有保存实现的缺陷

### MVP-D01：删空正文被当成丢弃，删除没有 revision 校验

- 编号：MVP-D01
- 范围：保存
- 证据级别：代码确认
- 优先级：P0
- 对应阶段：B
- 位置：旧正文工作台；`src/features/novel/state/useAutosaveScheduler.ts:37`、`workingCopySync.ts:32`、`crates/memory-core/src/novel/working_copies.rs:109`。
- 复现：合成章已有确认稿与编辑稿，删空正文后等待自动保存，再重开。删空分支删除 working copy，恢复时回退旧确认稿；删除失败仍更新 baseline 并显示 idle。删除接口无 expectedRevision，旧窗口也可删除另一窗口刚保存的稿。
- 预期：空正文是可恢复的有效编辑稿；只有作者显式丢弃才回到确认稿；丢弃须核对 revision。
- 影响：正文删除不能可靠持久化，跨窗口存在丢稿风险；这是旧实现缺陷，不能直接继承。
- 建议：working copy 允许空正文并沿用 CAS 保存；显式丢弃补 revision CAS，失败保留 dirty 状态。保持确认稿/试写的既有正文校验边界。
- 验收：原生客户端，确认稿非空 → 删空 → 保存 → 重开仍为空；两窗口旧 revision 丢弃被拒绝；故障时不得显示已保存。补对应纯 Rust/保存协调器行为断言。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D02：切章缺少保存屏障，迟到保存回调无归属检查

- 编号：MVP-D02
- 范围：保存
- 证据级别：代码确认
- 优先级：P0
- 对应阶段：B
- 位置：旧切章/自动保存；`src/features/novel/NovelWorkbench.tsx:111`、`state/useAutosaveScheduler.ts:44`、`:71`。
- 复现：700ms 防抖内修改后切章，选章直接 setSelectedId，effect cleanup 取消 timer，没有 flush。发出保存后切章，旧回调仍更新共享 revision/baseline/state，没有 document/generation 归属检查。
- 预期：切换先等待具体文档最新待保存快照完成；失败可取消切换；旧请求不能更改新章保存状态。
- 影响：快速切章丢未提交文字；迟到回调可能污染新章保存状态。保存提交未完成时的实际恢复边界仍需原生验证。
- 建议：复用 Rust CAS 与 `autosaveWorkingCopy`，新增按文档隔离的保存协调器；flush 返回 Promise，串行合并最新快照；切章、切作品、关闭统一守卫；回调核对文档与 generation。
- 验收：原生输入后立即切章/作品/退出；慢写入时继续输入或切换；注入写失败与冲突；原章恢复正确，新章 revision 不受旧请求影响。异常结束只承诺最近成功提交的版本，并实测未提交字符边界。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

## P1：接线缺项与已有读取缺陷

### MVP-D03：新工作台没有正式作品入口

- 编号：MVP-D03
- 范围：保存
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B
- 位置：默认 Notebook；`src/features/studio/useStudio.ts:20`、`usePreviewPersistence.ts:9`、`src-tauri/src/commands/novel.rs:64`。
- 复现：启动 studio，只进入整体 StudioProject localStorage 预览；没有新建/列表/选择正式作品的 UI/IPC 合同。旧 open_novel_editor 创建或聚焦 novel 窗口，selected 仅在进程 Mutex 中。
- 预期：首次启动提供新建/打开/最近作品；选作品留在新工作台；按章读取 SQLite，空库不自动变示例。
- 影响：正式作品主流程不可达，目前仅可绕到旧入口。
- 建议：新增 create/list/select works 薄 IPC，复用 `Database::create_work/list_works`（`crates/memory-core/src/spaces.rs:214/:236`）；select 切 studio 工作区，不调用旧窗口构建；最近作品/章节放独立 UI 设置。
- 验收：原生空库新建两作品，切换后重开恢复最近章节；读取失败持续显示错误，不加载/写回示例；存量正式作品可打开。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D04：文档加载错误的 active 条件反向

- 编号：MVP-D04
- 范围：保存
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B
- 位置：`src/features/novel/state/useDocumentLoad.ts:68`。
- 复现：当前章 getDocument/getWorkingCopy/listDrafts/listVersions 任一 reject，catch 条件为 if (!active)；活动请求失败不解除 loading 或提示，失活请求失败反而写当前页面状态。
- 预期：活动请求失败显示持久错误与重试；过期请求不写状态。
- 影响：新适配若继承该 hook，会故障无限加载并误报其他章错误。
- 建议：修正 active 条件；新适配保留已编辑内容，读取失败不得解释为空章；复用四个 IPC，避免把失败降级成 null。
- 验收：对四项读取分别注入失败，切章后让旧请求失败，断言 loading、错误、正文归属；原生复核重试可继续工作。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D05：线程只有会话内存，没有持久保存合同

- 编号：MVP-D05
- 范围：保存
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B
- 位置：`src/features/studio/writing/useThreadStore.ts:8`、`writing/threadTypes.ts:23`；`crates/memory-core/src/storage/migrations.rs`。
- 复现：两段填写不同未发要求和引用，重开；线程仅 useState，无 SQLite/IPC 存储。DTO 只有 chapterId，无 workId、持久 revision、operation 状态。
- 预期：按作品/章/线程隔离恢复草稿、引用快照、记录、候选；线程与正文保存独立。
- 影响：讨论重启丢失；正文保存成功不能代表讨论已保存。
- 建议：最小新增 thread 表，按 workId/documentId/threadId 与 CAS revision 保存；受校验快照包含 schemaVersion、不可变目标、映射锚点、草稿、引用快照、请求状态/输出/候选绑定。重开 pending 请求标 interrupted，不自动重发；正式版本继续 novel_versions。
- 验收：合成两作品两章两线程分别填写 → 切换 → 重开；线程失败不堵正文，正文失败不混写线程；旧库升级、失败回滚、重开断言。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D06：地点及资料出处关联没有正式映射

- 编号：MVP-D06
- 范围：保存 / 引用
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B；出处交互与发送上下文在 C 继续验收
- 位置：`src/features/studio/types.ts:16`、`MapPosition.tsx:6`；`src/lib/ipc.ts:372`；`crates/memory-core/src/storage/migrations.rs:1097/:1122`。
- 复现：新 Entity 有 location、related、sources、position；正式 LoreKind 与 SQLite CHECK 没有 location；source_anchors 只有作品/文档/版本/range，没有关联 LoreEntry。无法按现合同完整保存地点和某人物的出处。
- 预期：人物/地点/世界规则均有正式身份、版本和准确出处关联；无出处明确为空。
- 影响：必需资料不能直接映射；把地点偷偷映射 world 或用 quote 猜位置均不能满足正式合同。
- 建议：复用 lore 条目/version CAS 与 SourceAnchor 校验；最小迁移增加 location 和 entry→source_anchor 关联；related 若保留可操作需持久关系，否则首轮撤下相关动作。自由地图坐标首轮只读并延后；subtitle 可为非权威显示文案。
- 验收：原生人物/地点/规则新建编辑重开；绑定 emoji 出处；旧版 stale 不错跳，跨作品关联拒绝；存量迁移原数据保持。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D07：章节子集重排不符旧合同，缺可恢复归档

- 编号：MVP-D07
- 范围：保存
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B
- 位置：`src/lib/ipc.ts:294`、`crates/memory-core/src/novel/directory.rs:58`、`storage/migrations.rs:322`。
- 复现：旧内核支持创建/改名/重排，但重排必须提交作品全部文档全集，不能只给章节子集；未发现可恢复章节归档字段/接口。
- 预期：章节重排保持其他类型文档；归档可恢复，不删除版本、讨论、出处。
- 影响：直接提交新 UI chapters IDs 会被拒绝；归档是最低可用范围缺项。
- 建议：适配层保持完整摘要目录，章节重排合并完整 IDs；最小增加 archivedAt 与 archive/restore 接口，目录默认过滤而历史可查；当前章保存屏障通过后才归档。
- 验收：混合章节/人物/世界文档重排，重开顺序正确；归档恢复正文/版本/线程；重复归档幂等；保存失败不得继续归档。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

### MVP-D08：网页导出没有原生成功/取消/失败合同

- 编号：MVP-D08
- 范围：保存 / 发布
- 证据级别：代码确认
- 优先级：P1
- 对应阶段：B；系统交互在 A/D 验收
- 位置：`src/features/studio/useStudio.ts:48`、`projectActions.ts:60`。
- 复现：导出只用 Blob/link.download；flush 只写 localStorage；没有实际文件路径、取消和写入成功结果。
- 预期：系统保存对话框，取消不提示成功，写失败可重试；导出正文准确且不混讨论。
- 影响：缺正式客户端导出和故障备份路径。
- 建议：IPC 新增 export command，Rust 系统保存对话框与文件写入；返回 cancelled/saved，失败显式 error。从正式快照生成 Markdown，不恢复整体 StudioProject 权威库；失败恢复导出允许作者明确选择当前未保存稿。
- 验收：原生取消、覆盖、不可写目录、dirty/冲突时导出，打开文件逐章核对；JSON 若声称备份，必须定义恢复导入和版本范围，否则首轮仅交付 Markdown。
- 状态与负责人：待实施；实施负责人合并清单后认领，审查负责人 codex/data_audit。

## B 阶段最小可执行合同

### 1. 数据源与依赖

根入口显式确定 `source: native | preview`。正式读失败保持错误，不能回退示例。设计 fixture 与开发预览保持现有隔离；预览转正式只能作者主动一次性导入，不能自动覆盖旧库。正式权威为 SQLite；新 UI → 领域 adapter/hook → `src/lib/ipc.ts` → 薄 Tauri 命令 → Rust 核心。组件不得直接访问 Tauri。

### 2. WorkspaceAdapter

提供 create/list/select/recent。create/list 复用 spaces.rs；select 验证 novel space 后只改变新工作台工作区，不创建旧 novel 窗口。workId 是数据边界，不依赖作品标题匹配。列表不加载正文；最近作品和章状态持久保存到 settings。当前 selected Mutex 可以服务运行时，但不能单独承担重启恢复。

### 3. DocumentAdapter

目录只用 `novelDocumentSummaries` 返回摘要，正文按章使用 `novelGetDocument/novelGetWorkingCopy`。新建/改名复用 `novelCreateDocument/novelRenameDocument`；章节重排合并作品全量目录后调用 `novelReorderDocuments`。归档/恢复为最小新接口，不做永久删除。

编辑稿优先恢复，否则确认稿或空章；旧 baseHead 提示正稿已变化，不静默覆盖。待审候选应保持在审阅区，不因加载到 pending draft 自动替代正文编辑稿。读取有 generation，旧请求不可覆盖当前文档，失败不可伪装空章。

### 4. SaveCoordinator

每文档持有 `workId/documentId/generation/editSequence/savedSequence/expectedRevision/baseHead/body`。区分 dirty/saving/saved/conflict/error。保存提交固定 body 快照；成功只能推进对应快照的 savedSequence，提交后新增字符保持 dirty。单文档写入串行并合并最新待保存快照；不同文档独立，模型/线程错误不能阻断正文保存。

复用 `novelSaveWorkingCopy` 及 Rust revision CAS；空正文走保存，显式 discard 独立 CAS。`flushDocument/flushAll` 返回可等待 Promise。切章、切作品、归档、关闭前执行屏障；失败提供取消动作、重试、导出内存稿。正常关闭等待已提交写入及最新待保存快照成功；不能用 pagehide 异步调用宣称完成。窗口关闭监听只封装在 ipc.ts。

确认正稿继续使用 `novelCreateUserDraft → novelAcceptDraft`；保存不自动确认。正式历史与回退复用 `novelListVersions/novelRollbackDocument`；CM 撤销不承诺跨重启。discard/确认/回退和在途保存需统一序列化，避免清稿与保存交错。

### 5. LoreAdapter

复用 `novelCreateLore/novelUpdateLore/novelListLore/novelLoreVersions`；更新带 expectedVersion。人物/地点/世界规则使用正式 ID，新增 location 不偷映射 world。补 entry-anchor 关联；复用 `novelAddSourceAnchor/novelListSourceAnchors` 的版本归属、范围/hash 校验。JS UTF-16 与 Rust Unicode 字符坐标在边界转换并测试 emoji；来源版本不可变，stale 可读，不能相似匹配乱跳。地图位置首轮只读延后；相关资料若保留编辑动作必须明确存储合同。

### 6. ThreadAdapter

专用线程表绑定 workId/documentId/threadId，带 revision 与 schemaVersion；可以保存受校验的专用快照 JSON，不能保存整作品 JSON 冒充数据库。快照包含不可变生成目标、版本/revision、当前显示锚点、未发草稿、引用快照、请求 operationId/状态、模型输出、候选绑定与已采纳关联。正文和线程独立保存、独立错误。重开在途请求标 interrupted，禁止自动付费重发；C 再接真实生成。会话“版本”不代替 novel_versions。

### 7. UiSessionAdapter 与 ExportAdapter

最近章、版式、滚动位置存 settings；滚动恢复绑定作品/章，不能混入正文。导出合同区分 cancelled/saved/error，选文件路径与写入由 Rust 原生能力完成。正式导出按章取所需快照；恢复导出明确允许包含当前未保存稿。正文导出排除讨论与候选。

### 8. 最小迁移与升级边界

仅补经核实缺项：章节归档、地点类型、资料出处关联、专用线程持久存储；UI 状态复用 settings。迁移遵循现有 user_version/事务路径，不清库。用合成旧 schema 文件库验证升级前后正式稿、编辑稿 revision、版本、资料和出处完整；迁移中失败保持原版本与数据；重开可继续迁移；高版本库由旧程序明确拒绝，不能降级写入。新关联校验 work/document/entry 归属。

## 实施顺序与出口

1. 先修 D01/D02/D04，建立保存协调器、空正文和故障归属断言。
2. 新工作台作品入口、按章正式适配；保留开发预览隔离。
3. 章节归档/排序、人物/地点/规则及出处最小迁移。
4. 线程独立持久存储、最近章/版式/滚动设置。
5. 原生导出与关闭保存屏障。
6. 在 A 原生交互出口成立后完成 B 验收：立即切章、正常关闭、异常退出边界、冲突、故障、旧库升级、重开、导出内容断言；记录实际构建和命令到 docs/evidence，再更新看板。

本次无产品检查 PASS 声明。B 未通过前不标“离线写作通过”，也不开始大规模真实生成接线；缺原生操作、IME 或真实模型证据分别记录 NOT_RUN/PARTIAL，最终 CLIENT_MVP_PASS 仍按总计划 D 判定。
