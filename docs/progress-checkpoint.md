# 任务看板（progress-checkpoint）

更新：2026-09-26 · 状态：规划完成，无任务开工

## 判定规则

1. 开始任务先认领（填负责人、状态改 IN_PROGRESS）；同一任务只能有一个负责人（用分支或会话标识区分）。
2. 完成时记录**实际命令、退出码、关键结果、证据路径**，才能把 `[ ]` 改 `[x]`、状态改 PASS。
3. `PARTIAL / FAIL / NOT_RUN / BLOCKED / IN_PROGRESS` 一律不勾选；"文档或代码存在"不算通过。
4. 历史 PASS 不自动有效：关键验收必须在当前代码上复跑。
5. 详细命令输出写入 `docs/evidence/Txx-YYYYMMDD.md`。

## 当前事实

- **T00、T01、T02、T07 已 PASS（2026-09-26）**：脚手架 + 记忆底座 + 四空间/出处 API + LLM 核心层建成；索引瘦身 1.51GB→805MB；DeepSeek Key 已入 Windows 凭据管理器，真实 API 链路冒烟通过；G04、G05、G06、G15、G16 已 PASS。证据 docs/evidence/T00/T01/T02/T07-20260926.md。
- **技术基线已锁定**：ADR-0001（windows-gnu 工具链 + 便携 MinGW @ `C:\tools\paraselene-build\mingw64`，构建前加 PATH；lib 仅 rlib）；ADR-0002（Python 沙箱 = Pyodide，WebView2 禁 Node 集成）。
- **已知风险（G19 前必须再评）**：805MB 索引对"轻量常驻"仍是重资产；候选手段：按来源选择性索引（G18 授权天然支持）、会话级索引、VACUUM 常规化。详见 T02 证据。
- 仓库：`D:\paraselene`（Git main，远端 https://github.com/Rendegou/Paraselene.git）。项目定名**幻月 / Paraselene**。
- 仓库卫生规则生效：只提交代码与说明文档；语料、密钥、本地数据永不提交（AGENTS.md §4）；题集与事实清单在 `data/`（已 gitignore）。
- DeepSeek Key 已验证有效（2026-09-26 实测 HTTP 200），存于 `secrets/deepseek.key`（已 gitignore）；当前可用模型 `deepseek-flash` / `deepseek-v4-pro`，模型名运行时不写死。
- 产品方向已定稿：`windows-companion-agent-brief.md` v0.1。
- 测试素材就位（均在仓库外 `D:\MyAgent\`，永不提交）：`D:\MyAgent\chatgpt-export-markdown-part-01-of-03.zip`；`D:\MyAgent\codex\ChatGPT-MyStroy.md`。
- 可复用代码已盘点：`docs/reuse-inventory.md`。核心资产：Cumulonimbus agent 底座（`D:\mycli`，Gitee，MIT）、local-ai-chat-manager（`D:\harnessremotedesktop`，MIT，T01 已大规模移植）。
- 下一步：T03（桌宠外壳完善，依赖已满足）或 T04（旧想法花园，依赖 T02 已满足）。

## 任务看板（T00–T08）

- [x] T00 仓库脚手架与技术 spike
  - 状态: PASS
  - 依赖: 无
  - 负责人: kimi/paraselene-t00
  - 验证: `cargo check/test/build --workspace` 退出码 0；`pnpm typecheck`/`pnpm build` 退出码 0；`pnpm tauri dev` 冒烟启动成功（paraselene.exe 运行，空闲内存 ≈35MB，截图 docs/evidence/T00-20260926-pet.png）；Pyodide vs 本地进程 spike 数据落 ADR-0002（结论：Pyodide，WebView2 禁 Node 集成）；技术基线锁定 ADR-0001（windows-gnu + 便携 MinGW @ C:\tools\paraselene-build）
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
  - 验证: 48 测试全绿；隔离测试通过（跨空间默认不互通，隔离下沉 DDL CHECK，G06 PASS）；出处检索 API 有集成测试；索引瘦身 1.51GB→805MB（-47%）recall 96% 不回退；v2→v3→v4 真实库迁移零丢失
  - 退出码: 0
  - 证据: docs/evidence/T02-20260926.md
- [ ] T03 桌宠外壳：透明窗口/托盘/小卡片/形象包
  - 状态: NOT_RUN
  - 依赖: T00（可与 T01–T02 并行认领，负责人需不同）
  - 负责人: 待认领
  - 验证: G01–G03 实测记录（含空闲零请求计数）
  - 退出码: -
  - 证据: docs/evidence/T03-YYYYMMDD.md
- [ ] T04 旧想法花园闭环
  - 状态: NOT_RUN
  - 依赖: T02, T03
  - 负责人: 待认领
  - 验证: G07、G08 测试与演示记录
  - 退出码: -
  - 证据: docs/evidence/T04-YYYYMMDD.md
- [ ] T05 小说共写闭环
  - 状态: NOT_RUN
  - 依赖: T02, T03
  - 负责人: 待认领
  - 验证: G09–G11 测试记录（试写/正稿隔离、差异对比回滚、一致性提示）
  - 退出码: -
  - 证据: docs/evidence/T05-YYYYMMDD.md
- [ ] T06 Python 练习闭环
  - 状态: NOT_RUN
  - 依赖: T02, T03, T00（沙箱决策）
  - 负责人: 待认领
  - 验证: G12–G14 测试记录（口令协议、沙箱隔离测试、学习轨迹演示）
  - 退出码: -
  - 证据: docs/evidence/T06-YYYYMMDD.md
- [x] T07 模型接入与隐私设置
  - 状态: PASS
  - 依赖: T02
  - 负责人: kimi/paraselene-t07（2026-09-26 认领；LLM 核心不依赖 T03 外壳，先行）
  - 验证: 83 测试全绿；llm-core（SSE 状态机移植+CloudGate+预览/发送分离）；Key 存 Windows 凭据管理器且全仓库无明文；kill switch 组装期拒绝；真实 API 冒烟通过（fetch_models 2 模型 + max_tokens=1 流式）；G15、G16 PASS，G18 代码面 PASS（UI 面待 T03）
  - 退出码: 0
  - 证据: docs/evidence/T07-20260926.md
- [ ] T08 性能实测与打包
  - 状态: NOT_RUN
  - 依赖: T04, T05, T06, T07
  - 负责人: 待认领
  - 验证: G19 门槛数字锁定并达标；G20 安装包产出
  - 退出码: -
  - 证据: docs/evidence/T08-YYYYMMDD.md

## Goal 验收项重评

每次验收后更新，不能沿用过期数字。

- PASS（有当期证据）：G04（ChatGPT 导出适配器 100 篇 0 失败，T01 证据）、G05（Codex/Kimi 适配器真实入库 + 24 题题集 recall@5 96%，T01 证据）、G06（四空间隔离自动化测试，T02 证据）、G15（Key 凭据管理器 + kill switch + 全仓库无明文，T07 证据）、G16（外发前预览同源结构，T07 证据）。
- PARTIAL：G18（无采集代码面 PASS；数据源授权 UI 待 T03）。
- NEEDS_RECHECK：G01–G03、G07–G14、G17、G19、G20（尚无证据）。
- PARTIAL：无。
- BLOCKED：无。
