# 任务看板（progress-checkpoint）

更新：2026-10-14 · 当前唯一目标：小说创作客户端交互修复及原生保存验收。工作仅在 `D:\MyAgent\paraselene-work`。

## 当前排期（三步）

- **CLIENT-MVP-C：IN_PROGRESS / PARTIAL**；负责人 01a13583。先完成候选正文与状态原子提交，5 项故障/竞争测试通过；memory-core 全量 125、novel-core 34、Tauri check 与 Rust 指标通过。当前继续 working copy 预览与线程请求接线，尚无真实模型调用或安装验收。见[C证据](evidence/CLIENT-MVP-C-20261014.md)。

- **CLIENT-MVP 交互修复：IMPLEMENTED / NATIVE_ACCEPTANCE_IN_PROGRESS**；负责人 01a13583（本轮唯一源码/构建/原生窗口负责人）。修正同行标记重叠、CSP nonce 样式失效、失效讨论入口、全文撤销恢复、临时选区遮挡、版本回退映射及 inert 解除焦点恢复。87 行为测试与类型/构建通过；原生标记重开、草稿、切章/重启、撤销、版本回退、Escape 和失败恢复导出读回已有证据；IME/DPI/完整安装验收待补，继续 C/D。指标检查仍有三处既有 hook 超基线，未改基线。见[交互证据](evidence/CLIENT-MVP-INTERACTION-20261014.md)。

- **CLIENT-MVP-B：IMPLEMENTED / NATIVE_ACCEPTANCE_IN_PROGRESS**；负责人 codex/client-mvp-20261012，接手 Kimi 领域适配。正式作品、新建/按章加载、保存屏障、资料/线程持久化、查找、归档/全集重排、系统备份、原子正稿确认/回退已接线。前端 81 行为测试、类型/IPC/TS及Rust AST、领域 Clippy、memory-core 119 测试通过；原生隔离合成库流程正在验证。证据 [B接线](evidence/CLIENT-MVP-B-20261013.md)与[存储](evidence/CLIENT-MVP-B-STORAGE-20261013.md)。C真实生成/取消/采纳、D安装版尚未实施；客户端仍 PARTIAL。

- **CLIENT-MVP-A 原生继续验收**：系统导出取消/写入/UTF-8读回、普通标题Enter/Escape已验证；真实IME组成事件仅部分验证，完整IME、资料焦点/撤销、覆盖失败与DPI矩阵仍待测。证据 [A原生](evidence/CLIENT-MVP-A-NATIVE-20261012.md)。下方2026-10-12状态为历史快照。

- **CLIENT-MVP：A_IMPLEMENTED_PARTIAL / NATIVE_ACCEPTANCE_INTERRUPTED；负责人 codex/client-mvp-20261012**。四视角审查已合并，B最小数据合同已建立；A已实施展示标题/主动重命名、键盘菜单/IME过滤、资料往返保留编辑器/焦点/滚动、限定chrome选择、原生系统导出及格式重试。类型、Vite、32行为、TS/Rust AST、IPC边界和3项导出Rust测试通过；隔离Tauri窗口实际打开，标题Unicode提交/单层菜单/系统保存对话框有部分证据。用户实体Escape停止电脑控制；最终构建IME/DPI/光标/资料往返及导出取消/写入原生出口未完成。B/C/D未接线，不标CLIENT_MVP_PASS。证据 [CLIENT-MVP-A](evidence/CLIENT-MVP-A-20261012.md)，[合并清单](novel/client-mvp-review-20261012.md)，[B合同](novel/client-mvp-data-contract-20261012.md)。下一步：完成最终A原生出口→B保存合同。

- **UI-01C 安静写作与段落共写：FRONTEND_PASS / NATIVE_INPUT_NOT_RUN**；负责人 codex/paragraph-studio-20261012。三个独立可操作场景经视觉复核后已迁移默认前端；暖白正文、浅色外框、离线中文字体、独立段落线程、候选/版本和临时资料卡。类型、构建、30 项行为测试、复杂度与 IPC 边界通过。证据 [PARAGRAPH-UI-20261012](evidence/PARAGRAPH-UI-20261012.md)。原生 Windows IME 与真实模型/SQLite 本轮未验收。

- **UI-01B 正文与共写联动：FRONTEND_PASS**；负责人 codex/document-cowrite-20261012。按认可草图替换活动前端：章级讨论/草稿/候选、固定选段与资料快照、资料旁看、原位候选采纳撤销、失效保护、窄窗口上下协作及固定审阅按钮。证据 [NOVEL-COWRITE-20261012](evidence/NOVEL-COWRITE-20261012.md)。本轮未接模型或 SQLite。

- **UI-01 前端体验：FRONTEND_PASS**；负责人 codex/novel-client-20261012。默认创作入口、暖白正文/深灰侧栏、章节编辑新建、预览自动保存、人物/世界观、可编辑位置的地图、引用原文跳转、候选示例采纳拒绝撤销、专注/折叠/导出、界面内项目框架。证据 [NOVEL-UI-20261012](evidence/NOVEL-UI-20261012.md)。
- **UI-02 真实业务接线：PLANNED**。新界面接已有作品入口、SQLite working copy、确认版本、DeepSeek 外发预览与 patch。下一项；先用小作品跑通完整路径。
- **UI-03 引用与 Agent 深入：PLANNED**。人物、世界规则、地点绑定版本原文与反向引用；上下文由作者选择，失效可见。

最新 UI-01C 检查：TypeScript、Vite生产构建、30项前端行为测试、IPC边界与TS复杂度基线；浏览器验证独立段落线程、草稿隔离、候选安全与资料卡，三个尺寸视觉检查。Tauri编译与部分原生历史证据不沿用为本轮新界面的原生验收；最低可用状态需按CLIENT-MVP计划重新核对。

预览使用虚构素材，localStorage 与正式 SQLite 分离。修改示例为 SIMULATED，固定示例回复已退出活动入口；共写草稿/请求/候选只在当前会话内保留。真实模型、旧 SQLite 作品接线及本轮 Windows 原生完整操作为 NOT_RUN。没有宣称长篇稳定或全产品验收。桌宠默认隐藏，常驻通知轮询停用；旧代码和资料保留。

桌宠、T06 学习、主动提醒、多线开发与复杂自动推演为 DEFERRED。2026-10-03 文档头部和分项存在互相矛盾的完成状态，以下只作历史记录；不能据其首段认定尚未开发，也不能据历史 PASS 认定当前端到端通过。

## 历史记录（2026-10-03 及以前）

## 2026-10-03 优先级与接手入口

- 用户要求先做长篇小说工作台，T05A→B→C→D→E→F→G→H；T06改DEFERRED，保留已有成果与PARTIAL验收。
- 本轮完成：四项目公开版本/许可证与关键源码研究、工作台/设定/引用规格、上下文/存储/恢复设计、工程地图/规范、实施合同、KIMI提示词。仅文档交付，未新增长篇功能或运行产品回归。
- 下一步：KIMI读 [完整提示词](handoff/20261003-novel-first-kimi.md)，认领T05A，先复核旧行为与建立质量基线。实现状态以本看板更新为准。
- 文档验证证据：[本轮规划检查](evidence/T05-plan-20261003.md)。产品G09–G11保持PARTIAL；新的N01–N12为NOT_RUN。

### 小说子任务看板（PLANNED）

- T05A 模块与质量基线：PASS（2026-10-03 验收）；负责人 kimi/t05a-quality-20261003；验收见实施计划§2。证据 `docs/evidence/T05A-20261003.md`：拆分前后 88 项 Rust 测试一致通过、typecheck/build/前端行为测试 11 项/clippy/双语言 AST 基线校验通过；统一入口 `scripts/check-quality.ps1` 9/10（唯一 FAIL 为历史 cargo-fmt 债务）；债务例外登记 `docs/engineering/debt-register.md`。
- T05B 长文本工作台/恢复稿：PASS（2026-10-03 验收，证据 `docs/evidence/T05B-20261003.md`）；负责人 kimi/t05b-workbench-20261003；依赖T05A（已满足）。V7 迁移+编辑稿自动保存/恢复+摘要目录+重命名重排；编辑器 spike 锁 CodeMirror 6（ADR-0003）。N01–N03 进入可验收状态，原生最终验收归 T05H。
- T05C 安全diff/逐块应用：PASS（2026-10-03 验收，证据 `docs/evidence/T05C-20261003.md`）；负责人 kimi/t05c-patch-20261003；依赖T05B（已满足）。novel-core patch 纯逻辑 + V8 novel_patches 存储/状态机 + 三命令 + 前端候选块审阅 UI（逐块/全部/拒绝，歧义剔除）。
- T05D 设定集/出处版本：IN_PROGRESS；负责人 kimi/t05d-lore-20261003（2026-10-03 认领）；依赖T05C（已满足）。第一片：V9 迁移（lore_entries/lore_versions/source_anchors）与存储契约。
- T05E 分层上下文/重建：IN_PROGRESS；负责人 kimi/t05e-context-20261003（2026-10-03 认领）；依赖T05D（已满足）。第一片：novel-core context 分层装配（硬约束/选段/检索/摘要层 + 预算 + manifest）。
- T05F 伏笔/动机/连续性：NOT_RUN；负责人待认领；依赖T05D/T05E。
- T05G 取消/故障恢复：NOT_RUN；负责人待认领；依赖T05C/T05E。
- T05H 原生/规模/最终review：NOT_RUN；负责人待认领；依赖T05A–T05G。

[实施与验收细节](novel/implementation-plan.md)。不把文档完成状态用于勾选功能任务。

## 判定规则

1. 开始任务先认领（填负责人、状态改 IN_PROGRESS）；同一任务只能有一个负责人（用分支或会话标识区分）。
2. 完成时记录**实际命令、退出码、关键结果、证据路径**，才能把 `[ ]` 改 `[x]`、状态改 PASS。
3. `PARTIAL / FAIL / NOT_RUN / BLOCKED / IN_PROGRESS / DEFERRED / PLANNED` 一律不勾选；"文档或代码存在"不算通过。
4. 历史 PASS 不自动有效：关键验收必须在当前代码上复跑。
5. 详细命令输出写入 `docs/evidence/Txx-YYYYMMDD.md`。

## 当前事实

- 2026-10-03 T05D 完成（kimi/t05d-lore-20261003）：设定集与出处锚点全链路——V9 迁移；lore 条目/不可变版本链（作者确认与 AI 候选分离、乐观锁、同名异人不合并、别名检索、scope 全程/回溯/自某章起）；出处锚点后端算 hash 绑定版本，头移动 stale 可见、删章级联。memory-core 85+6、novel-core 25 测试通过；统一门 9/10。reference_edges（引用链）按计划在 T05F。证据 docs/evidence/T05D-20261003.md。

- 2026-10-03 T05C 完成（kimi/t05c-patch-20261003）：安全 patch 全链路——novel-core patch 纯逻辑（行分块/字级 op/绑定校验/统一偏移应用/唯一匹配重定锚）；V8 novel_patches 存储与幂等状态机；三命令（生成/应用/拒绝，CAS 落编辑稿后翻动状态）；前端候选块审阅面板（逐块/全部/拒绝/稍后，切章过滤）。novel-core 25 项、memory-core 85 项测试通过；统一门 9/10（历史 fmt 唯一 FAIL）。未做真实模型端到端与原生点击演示（归 T05H）。证据 docs/evidence/T05C-20261003.md。

- 2026-10-03 T05B 完成（kimi/t05b-workbench-20261003）：V7 迁移（显式章序 + working_copies 编辑稿，存量回填保序）；目录摘要不携带正文、按章读取；编辑稿 700ms 自动保存 + revision 乐观锁 + 重启恢复（文件库重开测试）；目录重命名/重排；CodeMirror 6 经真实 WebView2 spike 锁定（100 万字装入 42.1ms、JS 堆 29MB、撤销/重做/UTF-16 坐标 PASS、中文 IME 组合事件实测，证据 docs/evidence/T05B-spike-webview2-*.png 与 ADR-0003）。memory-core 83 项、novel-core 14 项测试通过；统一门 9/10（历史 fmt 债务唯一 FAIL）。N01–N03 进入可验收状态，原生整体验收与 IME 长尾归 T05H。证据 docs/evidence/T05B-20261003.md。

- 2026-10-03 T05A 完成（kimi/t05a-quality-20261003）：小说 UI 拆为 `src/features/novel/`（薄入口 8 行 + 16 模块）；novel-core 拆 edit/generation/rpg/stream；memory-core novel.rs 拆 novel/{mod,drafts,versions}（公开 API 与数据不变）；新增 check-quality 统一入口、TS/Rust AST 度量基线（TS 7 项 / Rust 36 项存量债务）、前端行为测试 11 项。前后 88 项 Rust 测试、typecheck、build、clippy 均退出 0；cargo-fmt 历史 FAIL 记债务。证据见 docs/evidence/T05A-20261003.md。未做原生 WebView2 验收（归 T05B/T05H）。


- 2026-10-01 T06 质量接续：修复安全探针漏调用、Worker 同步 compile/exec 丢失异步求值，以及探针窗口创建阶段未受超时保护；新增真实产品 Worker 的网络/文件/IPC 反例、缺失与错误 token、提示恢复、Python 异常、无限循环与超时后重跑。原生 LEARNING_SECURITY_ASSERT:PASS / LEARNING_ASSERT:PASS；独立复核指出的超时假阳性已修正并验证拒绝。当前工作区 138 项通过、1 项凭据库环境用例过滤；未过滤运行仍因 NoStorageAccess(1312) 失败。TypeScript/Vite 构建通过。G12/G13/G14 保持 PARTIAL，更多网络 API/文件打开反例、轨迹接线及完整教学流程待完成。见 docs/evidence/T06-20261001.md。

- 2026-09-28 T07/G17 工作副本：卡片新增按空间记忆列表、精确出处原文、带版本条件的纠正与软删除，以及本地可复制 JSON。旧想法转换出的小说目标纠正保持作品名同步。工作区 135 项测试通过、1 项凭据库环境用例过滤；TypeScript、Vite runner 和 Tauri check 通过。原生操作与文件保存导出未验收，G17 保持 PARTIAL。见 `docs/evidence/T07-memory-20260928.md`。
- 2026-09-28 T03 用户反馈续接：工作副本移除顶部抓手，宠物本体以 6px 位移区分拖动和短点击；三外观各新增透明眨眼帧与待机呼吸。TypeScript、Vite runner 构建通过，三张新图尺寸/透明角检查通过。Windows 原生窗口尚未手动确认，G01 保持 PARTIAL。见 `docs/evidence/T03-direct-drag-blink-20260928.md`。
- 2026-09-28 T06/G13 早期原生探针：普通模块 Worker 的外网 no-cors fetch 实际返回 opaque，原方案不安全；探针专用 Blob Worker + CSP + 固定资源协议下，Pyodide 314.0.7 加载并通过外网、文件、IPC 反例，`PROBE_ASSERT:PASS`。主页面即使 CSP 记录 IPC 违规仍能执行 Tauri 命令，故用户代码只能放在 Worker。当时产品入口尚未接入；后续进展见下一条。见 `docs/evidence/T06-20260928.md`。
- 2026-09-28 T06/G13 学习窗口专属策略：用户授权仅学习窗口放宽 Blob Worker/WASM；自定义协议按窗口 label、host、固定资源白名单服务并下发专属 CSP，产品全局 CSP 未放宽。无配置覆盖的原生隔离探针 `SCOPED_ASSERT:PASS`。卡片新增固定 `double(x)` 练习入口；产品路径原生测试 `LEARNING_ASSERT:PASS`（伪造结果拒绝、错误/正确答案 1/3→3/3）。仍需更多产品路径安全回归和学习轨迹接线，G13 保持 PARTIAL。见 `docs/evidence/T06-20260928.md`。
- 2026-09-28 T06 第一片：工作副本新增 V6 学习轨迹表、纯 Rust 记录/查询接口及五种教学口令协议。合成测试证明按学习目标隔离、重开后持久化、已通过主题不再作为薄弱点，以及没有可信测试结果时不假装审阅；当时工作区 132 项测试通过（Windows 凭据库环境用例过滤 1 项），Tauri check 通过。该阶段尚未开放用户代码执行；后续已开放固定练习。软删目标后底层轨迹仍保留；永久删除提案被自动审批拒绝，详见 `docs/evidence/T06-20260928.md`。
- 2026-09-28 T05/G09 续接：工作副本新增两阶段跑团共写，临时场景给 2–3 个走向选项，玩家短回复被视为主角内心/行动；场景与未确认互动不进下一章上下文，完整互动只进待确认试写。合成测试、TypeScript、Vite 8.3.1 与 Tauri check 通过，工作区 126 项测试通过（Windows 凭据库环境用例过滤 1 项）。没有真实 API 或原生点击验收。见 `docs/evidence/T05-20260928.md`。
- 2026-09-27 T05/G11 续接：工作副本新增确认稿待决议题看板、生成提示、明确人物禁令的出处候选提示与逐条覆盖。未定行不会作为硬约束注入；后端采纳时重新核对冲突及作品版本。合成测试通过；复杂语义冲突和原生界面未验收。见 `docs/evidence/T05-20260927.md`。
- 2026-09-27 T05/G10 续接：工作副本加入正稿选段的三种局部试写、外发预览、差异审阅与版本回退入口。纯 Rust 校验选段位置与当前版本；“只改对白”检查对白外文字不变；生成期间确认设定变化时同事务拒绝保存。动作逻辑语义未自动证明，原生 UI 未演示，G10 保持 PARTIAL。详见 `docs/evidence/T05-20260927.md`。
- 2026-09-27 T05 续接：工作副本新增纯 Rust `novel-core`、小说专用外发预览与 AI 试写入口。上下文只含本作品已确认版本，人物卡/禁忌作为生成约束；完整模型回复只存为待确认试写。合成测试与前端构建通过，工作区 115 项测试通过（Windows 凭据库环境用例 1 项过滤），Tauri check 通过。未调用真实 API，未做原生点击验收；G09–G11 保持 PARTIAL。用户选择保留工作副本，正式仓库未同步。详见 `docs/evidence/T05-20260927.md`。
- 2026-09-27 恢复 T05：修复了小说编辑器切换文档／查看试写／回滚时丢失未保存输入的路径，保存中禁止并发切换并恢复输入框键盘焦点。工作副本 `pnpm typecheck` 与 `pnpm exec vite build --configLoader runner` 退出 0；小说核心 66 项测试通过、Tauri check 通过。全工作区测试的 Windows 凭据库用例因 `NoStorageAccess(1312)` 失败，跳过该环境依赖用例后其余 109 项通过。`pnpm build` 因工作副本 junction 指向的 `.vite-temp` 写入 EPERM 失败，runner 构建可用。正式仓库写入范围外，14 文件白名单同步被自动审批拒绝，本轮没有写入正式仓库；详见 `docs/evidence/T05-20260927.md`。
- 2026-09-27 交接暂停：用户要求停止开发并提交 `docs/handoff/20260927-pet-novel.md`。T05 的 schema V5、纯 Rust 小说文档/试写/版本树、薄 IPC 与独立编辑器目前**只在** `D:\MyAgent\paraselene-work`，尚未同步到正式仓库。隔离副本 `cargo test --workspace --target-dir 'D:\paraselene\target' --offline --quiet` 退出 0，110 项通过；`cargo check -p paraselene --target-dir 'D:\paraselene\target' --offline --quiet` 与 `pnpm typecheck` 退出 0；新小说 UI 的 `pnpm build` 未执行，原生操作未验收。T05/G09–G11 保持未完成，详情与保留清单见交接文档。
- **T00、T01、T02 有 PASS 证据；T03、T04、T07 进行中。** 当前正式仓库 Rust 工作区 105 项测试通过，Tauri 编译检查、TypeScript 检查与 Vite 构建通过。未重新导入真实私有语料、未重复调用真实 DeepSeek API。G05 已在正式搜索 API 上重跑 24 题，G16 已重新验收；G15 仍待完整原生操作。见 T02/T03/T04/T07 证据。
- **技术基线**：ADR-0001（Windows GNU 工具链）；ADR-0002 已改为条件接受：Pyodide 是执行引擎候选，隔离方案必须在 T06 证明。
- **已知风险（G19 前必须再评）**：805MB 索引对"轻量常驻"仍是重资产；候选手段：按来源选择性索引（G18 授权天然支持）、会话级索引、VACUUM 常规化。详见 T02 证据。
- 仓库：`D:\paraselene`（Git main，远端 https://github.com/Rendegou/Paraselene.git）。项目定名**幻月 / Paraselene**。
- 仓库卫生规则生效：只提交代码与说明文档；语料、密钥、本地数据永不提交（AGENTS.md“隐私、复用与数据”）；题集与事实清单在 `data/`（已 gitignore）。
- Kimi 曾验证 DeepSeek API HTTP 200，并记录本地 `secrets/` 引导文件；本次未读取或删除凭据。运行时 Key 在 Windows 凭据管理器；默认模型仍为代码常量 `deepseek-flash`，设置页可主动拉取模型名单。
- 产品方向已定稿：`windows-companion-agent-brief.md` v0.1。
- 测试素材就位（均在仓库外 `D:\MyAgent\`，永不提交）：`D:\MyAgent\chatgpt-export-markdown-part-01-of-03.zip`；`D:\MyAgent\codex\ChatGPT-MyStroy.md`。
- 可复用代码已盘点：`docs/reuse-inventory.md`。核心资产：Cumulonimbus agent 底座（`D:\mycli`，Gitee，MIT）、local-ai-chat-manager（`D:\harnessremotedesktop`，MIT，T01 已大规模移植）。
- 下一步：待 Windows 通知状态退出 BUSY 后完成 T03 的托盘、专注状态与三外观在正式 120px 窗口中的原生验收；历史顶部抓手人工拖动已验证，新本体拖动需复验。T07 继续完成 G15；T04 完成原生页面演示，并把已创建目标的基础详情发展为小说与学习的专业编辑器。
- 2026-09-27 前端进度：夜空手帐卡片的对话、形象、设置排版已同步至正式仓库，类型检查、Vite 8 构建和 Windows 开发版原生链接通过。用户认可月相小兽主轮廓后，月/星/云同骨架三外观各制作待机、点击、睡眠透明图，并在隔离副本接入姿态切换；这批新增内容的正式仓库同步和构建结果见 T03 证据。新卡片与三姿态尚未完成原生视觉验收。T03 不因此改为 PASS，详见 `docs/evidence/T03-20260926.md`。
- 2026-09-27 检索复核：历史 24 题评测的 trigram 查询未接入正式 `Database::search()`，中文句中检索在合成回归中确实返回 0。现已接入索引选择；正式仓库 93 项 Rust 测试通过，当前 API 在原 24 题上 recall@5 23/24、top-1 22/24，G05 重新验收为 PASS。top-1 短片段含标注出处关键词仅 4/24，T04/G08 必须提供原文跳转，不能把 snippet 当完整证据。详见 T02 证据。
- 2026-09-27 T04：原四个严格线索在真实索引前 4096 字内无匹配，导致候选一直为空。扩展到更自然的创作表达后，在先前授权的完整索引副本上能找到两条不同候选；查询前后 idea 记忆均为 0。候选只展示原文，用户按“确认保存”才连同精确出处入库；状态更改同样需确认。用户确认转换可原子创建目标、出处和跨空间链接；提醒偏好可明确设为不再主动提起。原生页面尚未演示，目标空间编辑器未实现，因此 T04/G07/G08 不标 PASS。详见 `docs/evidence/T04-20260927.md`。
- 2026-09-27 T07 / G18：用户逐次选来源和单个导出文件；预览仅只读解析，确认才写入应用数据目录并索引，一次性票据防重复确认。真实 ChatGPT ZIP 的只读解析得到 100 会话 / 772 消息 / 0 文件失败，来源哈希不变；未对真实语料执行本轮导入。原生 QA 启动后没有稳定可定位窗口，文件选择与确认 UI 尚未操作验收，G18 仍是 PARTIAL。详见 `docs/evidence/T07-import-20260927.md`。
- 2026-09-27 T03 复核：本地浏览器按 440 × 640 预览了四个卡片页面与三种形象，对话空态改为显示当前桌宠待机图。原生窗口消失的当下系统通知状态为 `BUSY=2`，符合现有自动收起逻辑；未强行在该状态下显示桌宠。浏览器预览不替代原生验收，G01 仍 PARTIAL。详见 T03 证据。
- 2026-09-27 T03 角色追加：月／星／云各新增一张原创“好奇”透明姿态，指针靠近或键盘聚焦触发约 1.1 秒；点击优先于好奇计时器，指针停留时不睡眠。三张 1402 × 1122 RGBA 图在检查点透明、角色中心不透明；TypeScript 与 Vite 构建通过。内置浏览器拒绝本地 `file://` 预览，原生 120px 窗口尚未验收，T03/G01 状态保持不变。见 `docs/evidence/T03-pet-curious-20260927.md`。
- 2026-09-27 T04 补充：旧想法转换后可进入并重开目标详情，编辑标题与起点笔记，小说作品名同步更新；过期编辑被拒绝。合成核心测试与浏览器 440 × 640 布局预览通过，正式原生操作仍待完成。详见 T04 证据。

## 任务看板（T00–T08）

- [x] T00 仓库脚手架与技术 spike
  - 状态: PASS
  - 依赖: 无
  - 负责人: kimi/paraselene-t00
  - 验证: `cargo check/test/build --workspace` 退出码 0；`pnpm typecheck`/`pnpm build` 退出码 0；`pnpm tauri dev` 冒烟启动成功（paraselene.exe 运行，空闲内存 ≈35MB，截图 docs/evidence/T00-20260926-pet.png）；Pyodide vs 本地进程资源 spike 数据落 ADR-0002（隔离结论已更正，G13 待证明）；技术基线锁定 ADR-0001
  - 退出码: 0
  - 证据: docs/evidence/T00-20260926.md
- [x] T01 记忆底座：移植 parser/scanner/storage + ChatGPT 导出适配器
  - 状态: PASS
  - 依赖: T00
  - 负责人: kimi/paraselene-t01（2026-09-26 认领）
  - 验证: cargo test 38/38 退出码 0；真实导出包导入 100 篇/772 消息/0 失败/去重复验通过；中文检索题集 24 题 recall@5 96%（trigram 定案进 schema V2）；Codex 273 + Kimi 152 真实会话入库 0 失败（G04、G05 同步 PASS）
  - 退出码: 0
  - 证据: docs/evidence/T01-20260926.md
- [x] T02 四空间 schema 与出处检索 API
  - 状态: PASS
  - 依赖: T01
  - 负责人: kimi/paraselene-t02（2026-09-26 认领）
  - 验证: 当前 memory-core 49 测试全绿；隔离测试通过（跨空间默认不互通，隔离下沉 DDL CHECK，G06 PASS）；正式搜索 API 24 题 recall@5 23/24、top-1 22/24（G05 PASS）；索引瘦身 1.51GB→805MB（-47%）；v2→v3→v4 真实库迁移零丢失
  - 退出码: 0
  - 证据: docs/evidence/T02-20260926.md
- [ ] T03 桌宠外壳：透明窗口/托盘/小卡片/形象包
  - 状态: IN_PROGRESS
  - 依赖: T00（可与 T01–T02 并行认领，负责人需不同）
  - 负责人: codex/phase2-quality-20260926
  - 验证: 原生 QA 验证宠物/卡片启动、角色更换与安全导入/导出；空闲 602 秒计数保持 0/0，121 次资源采样完整（G02、G03 PASS）。Windows 全屏通知状态会自动收起；历史顶部横条拖动已由用户验证。工作副本现改为本体拖动并新增三外观眨眼帧，自动化检查通过但原生操作尚待复验；托盘及专注状态切换仍待验收（G01 PARTIAL）
  - 退出码: -
  - 证据: docs/evidence/T03-20260926.md
- [ ] T04 旧想法花园闭环
  - 状态: IN_PROGRESS（离线核心先行；T07 产品验收仍是完整闭环依赖）
  - 依赖: T02, T07
  - 负责人: codex/phase3-ideas-20260927
  - 验证: 9 项 idea 核心测试、正式仓库完整 Rust 工作区 105 项测试、TypeScript/Vite/Tauri 检查和授权索引副本只计数冒烟通过；转目标、目标重开／基础编辑与提醒偏好自动化通过，G07/G08 原生演示仍待完成
  - 退出码: 0（自动化）；产品验收未完成
  - 证据: docs/evidence/T04-20260927.md
- [ ] T05 小说共写闭环
  - 状态: IN_PROGRESS（2026-10-03转长篇工作台计划；T05A–T05H待实施；正式仓库未同步）
  - 依赖: T02与现有小说独立窗口；T03原生验收留全产品门禁，不阻止T05A
  - 负责人: 规划 codex/novel-plan-20261003；实施子任务待认领（保留历史负责人记录）
  - 验证: 正稿隔离、过期拒绝、版本树、已确认上下文与选段修改的合成测试通过；G11 当前确认稿的待决议题看板和提示词、明确人物禁令的出处提示及逐条覆盖已接线；G09 两阶段跑团场景/选项/玩家短回复到待确认试写已接线且有隔离测试；AI 试写和 G10 差异/回退有界面入口。原生编辑器未验收
  - 退出码: 0（126 项工作区测试，凭据库环境用例 1 项过滤；工作副本 Vite 8.3.1 runner 构建、TypeScript 与 Tauri check）；未过滤的全量测试受 Windows 凭据库环境影响退出 1；产品验收未完成
  - 证据: docs/evidence/T05-20260927.md、docs/evidence/T05-20260928.md、docs/handoff/20260927-pet-novel.md
- [ ] T06 Python 练习闭环
  - 状态: DEFERRED（2026-10-03按用户优先级延期；更多G13反例、轨迹接线和教学流程未验收）
  - 依赖: T02, T03, T00（沙箱决策）
  - 负责人: codex/learning-quality-20261001（历史负责人；本轮延期不继续实施）
  - 验证: V6 学习轨迹与跨空间拒绝、重开持久化、薄弱点消除的合成测试通过；G12 五口令纯 Rust 协议通过、固定补全题有三档提示与可重跑测试；G13 本轮真实产品 Worker 的 fetch/文件存在性/IPC 反例、评分防伪与超时恢复通过；更多网络 API 和文件打开反例未覆盖；G14 轨迹接线与用户演示未完成
  - 退出码: 0（当前 138 项工作区测试、1 项凭据库环境用例过滤；TypeScript、Vite build、加强后的原生产品回归）；未过滤测试因凭据库环境失败退出 1，完整 T06 未验收
  - 证据: docs/evidence/T06-20260928.md、docs/evidence/T06-20261001.md
- [ ] T07 模型接入与隐私设置
  - 状态: IN_PROGRESS（接手 G18 的主动授权导入入口；G15/G16 历史证据保留）
  - 依赖: T02
  - 负责人: codex/phase3-import-20260927（从 kimi/paraselene-t07 的历史实现接手）
  - 验证: Kimi 历史记录为 83 测试及真实 API 冒烟；本次修复真实账号测试误删、Space IPC 大小写、提前 EOF 伪成功、预览/发送分离与设置读库失效后放行。G16 已有原生预览与一次性票据验证；本轮新增 G18 文件选择、只读预览、确认导入入口及真实 ZIP 只读冒烟，最终自动化命令和退出码见新证据。模型设置、导入入口完整原生操作以及明文引导文件处置仍待验证
  - 退出码: 0（自动化）；产品验收未完成
  - 证据: docs/evidence/T07-20260926.md、docs/evidence/T07-import-20260927.md、docs/evidence/T03-20260926.md
- [ ] T08 性能实测与打包
  - 状态: NOT_RUN
  - 依赖: T04, T05, T06, T07
  - 负责人: 待认领
  - 验证: G19 门槛数字锁定并达标；G20 安装包产出
  - 退出码: -
  - 证据: docs/evidence/T08-YYYYMMDD.md

## Goal 验收项重评

每次验收后更新，不能沿用过期数字。

- PASS：G02（原生 QA 更换名称/形象/语气，角色包导出白名单与非法字段拒绝）；G03（空闲 602 秒、121 次采样，模型与扫描计数均为 0）；G05（正式搜索 API 24 题 recall@5 23/24、top-1 22/24，出处 anchor 数字见 T02）；G06（四空间隔离自动化测试本次复跑）；G16（原生 UI 显示上下文与测试原文，发送命令只能消费后端一次性预览票据）。
- PARTIAL：G01（原生窗口与小卡片、全屏通知状态收起、用户人工拖动已验证；托盘与专注切换待验证）；G15（Keyring 与设置 UI 已接线，明文引导文件尚未处置，原生操作待验）；G18（来源逐项选择、单文件只读预览和确认导入已接线；原生操作及目录授权仍待验收）。
- PARTIAL：G07（五状态确认与提醒偏好有自动化测试，未原生演示）；G08（真实索引副本候选、精确出处与确认转目标 API 通过，未原生演示）。
- PARTIAL：G11（来源明确的人物禁令候选提示与逐条覆盖、确认稿未决议题看板及生成提示已接线；目前仅字面规则与固定措辞，原生演示和复杂语义冲突未验收）。
- PARTIAL：G09（跑团两阶段界面和隔离测试已接线；原生点击及真实请求未验收）。
- PARTIAL：G12（五口令纯 Rust 协议通过；固定题有三档提示与可重跑测试，完整教学流程未接入）；G13（当前产品 Worker 的 fetch/文件存在性/IPC、评分防伪与超时恢复通过，更多网络 API/文件打开反例未覆盖）；G14（本地学习轨迹与薄弱点选择的合成测试通过，产品窗口尚未保存轨迹和演示）。
- PARTIAL：G17（记忆管理工作副本已接线并通过合成测试，原生操作与文件导出未验收）。
- NEEDS_RECHECK：G04（真实导入为 Kimi 当日历史证据，当前未重跑）；G10、G19、G20。
- BLOCKED：无。

