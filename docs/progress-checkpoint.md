# 任务看板（progress-checkpoint）

更新：2026-09-27 · 状态：按用户要求暂停开发；T03、T04、T07 仍未验收，T05 仅隔离副本 WIP

## 判定规则

1. 开始任务先认领（填负责人、状态改 IN_PROGRESS）；同一任务只能有一个负责人（用分支或会话标识区分）。
2. 完成时记录**实际命令、退出码、关键结果、证据路径**，才能把 `[ ]` 改 `[x]`、状态改 PASS。
3. `PARTIAL / FAIL / NOT_RUN / BLOCKED / IN_PROGRESS` 一律不勾选；"文档或代码存在"不算通过。
4. 历史 PASS 不自动有效：关键验收必须在当前代码上复跑。
5. 详细命令输出写入 `docs/evidence/Txx-YYYYMMDD.md`。

## 当前事实

- 2026-09-27 交接暂停：用户要求停止开发并提交 `docs/handoff/20260927-pet-novel.md`。T05 的 schema V5、纯 Rust 小说文档/试写/版本树、薄 IPC 与独立编辑器目前**只在** `D:\MyAgent\paraselene-work`，尚未同步到正式仓库。隔离副本 `cargo test --workspace --target-dir 'D:\paraselene\target' --offline --quiet` 退出 0，110 项通过；`cargo check -p paraselene --target-dir 'D:\paraselene\target' --offline --quiet` 与 `pnpm typecheck` 退出 0；新小说 UI 的 `pnpm build` 未执行，原生操作未验收。T05/G09–G11 保持未完成，详情与保留清单见交接文档。
- **T00、T01、T02 有 PASS 证据；T03、T04、T07 进行中。** 当前正式仓库 Rust 工作区 105 项测试通过，Tauri 编译检查、TypeScript 检查与 Vite 构建通过。未重新导入真实私有语料、未重复调用真实 DeepSeek API。G05 已在正式搜索 API 上重跑 24 题，G16 已重新验收；G15 仍待完整原生操作。见 T02/T03/T04/T07 证据。
- **技术基线**：ADR-0001（Windows GNU 工具链）；ADR-0002 已改为条件接受：Pyodide 是执行引擎候选，隔离方案必须在 T06 证明。
- **已知风险（G19 前必须再评）**：805MB 索引对"轻量常驻"仍是重资产；候选手段：按来源选择性索引（G18 授权天然支持）、会话级索引、VACUUM 常规化。详见 T02 证据。
- 仓库：`D:\paraselene`（Git main，远端 https://github.com/Rendegou/Paraselene.git）。项目定名**幻月 / Paraselene**。
- 仓库卫生规则生效：只提交代码与说明文档；语料、密钥、本地数据永不提交（AGENTS.md §4）；题集与事实清单在 `data/`（已 gitignore）。
- Kimi 曾验证 DeepSeek API HTTP 200，并记录本地 `secrets/` 引导文件；本次未读取或删除凭据。运行时 Key 在 Windows 凭据管理器；默认模型仍为代码常量 `deepseek-flash`，设置页可主动拉取模型名单。
- 产品方向已定稿：`windows-companion-agent-brief.md` v0.1。
- 测试素材就位（均在仓库外 `D:\MyAgent\`，永不提交）：`D:\MyAgent\chatgpt-export-markdown-part-01-of-03.zip`；`D:\MyAgent\codex\ChatGPT-MyStroy.md`。
- 可复用代码已盘点：`docs/reuse-inventory.md`。核心资产：Cumulonimbus agent 底座（`D:\mycli`，Gitee，MIT）、local-ai-chat-manager（`D:\harnessremotedesktop`，MIT，T01 已大规模移植）。
- 下一步：待 Windows 通知状态退出 BUSY 后完成 T03 的托盘、专注状态与三外观在正式 120px 窗口中的原生验收；桌宠顶部抓手的人工拖动已验证。T07 继续完成 G15；T04 完成原生页面演示，并把已创建目标的基础详情发展为小说与学习的专业编辑器。
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
  - 验证: 原生 QA 验证宠物/卡片启动、角色更换与安全导入/导出；空闲 602 秒计数保持 0/0，121 次资源采样完整（G02、G03 PASS）。Windows 全屏通知状态会自动收起；用户亲自抓住顶部横条拖动桌宠，窗口位置变化。托盘及专注状态切换仍待验收（G01 PARTIAL）
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
  - 状态: IN_PROGRESS（按用户要求暂停；核心隔离只在工作副本，T03 原生验收仍待完成）
  - 依赖: T02, T03
  - 负责人: codex/phase4-novel-20260927
  - 验证: G09–G11 测试记录（试写/正稿隔离、差异对比回滚、一致性提示）
  - 退出码: -
  - 证据: docs/handoff/20260927-pet-novel.md（阶段记录；专项目标证据文件待建）
- [ ] T06 Python 练习闭环
  - 状态: NOT_RUN
  - 依赖: T02, T03, T00（沙箱决策）
  - 负责人: 待认领
  - 验证: G12–G14 测试记录（口令协议、沙箱隔离测试、学习轨迹演示）
  - 退出码: -
  - 证据: docs/evidence/T06-YYYYMMDD.md
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
- NEEDS_RECHECK：G04（真实导入为 Kimi 当日历史证据，当前未重跑）；G09–G14、G17、G19、G20。
- BLOCKED：无。
