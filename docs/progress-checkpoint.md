# 任务看板（progress-checkpoint）

更新：2026-09-26 · 状态：规划完成，无任务开工

## 判定规则

1. 开始任务先认领（填负责人、状态改 IN_PROGRESS）；同一任务只能有一个负责人（用分支或会话标识区分）。
2. 完成时记录**实际命令、退出码、关键结果、证据路径**，才能把 `[ ]` 改 `[x]`、状态改 PASS。
3. `PARTIAL / FAIL / NOT_RUN / BLOCKED / IN_PROGRESS` 一律不勾选；"文档或代码存在"不算通过。
4. 历史 PASS 不自动有效：关键验收必须在当前代码上复跑。
5. 详细命令输出写入 `docs/evidence/Txx-YYYYMMDD.md`。

## 当前事实

- 仓库已初始化：`D:\paraselene`（Git main）。项目定名**幻月 / Paraselene**（"幻月"= paraselene，大气光学中的伴月现象；用户拍板，备选月晕/望舒已弃用）。
- 仓库卫生规则生效：只提交代码与说明文档；语料、密钥、本地数据永不提交（AGENTS.md §4）。
- DeepSeek Key 已验证有效（2026-09-26 实测 HTTP 200），存于 `secrets/deepseek.key`（已 gitignore，`git check-ignore` 验证过）；当前可用模型 `deepseek-flash` / `deepseek-v4-pro`，模型名运行时不写死。
- GitHub 远端尚未创建：本机无 gh CLI 且未认证，需用户创建空仓库后添加 remote，或安装 gh 并登录。
- 仓库尚未脚手架化：无 Cargo workspace、无 Tauri 工程，只有规划文档（AGENTS.md / Goal / brief / 本看板 / 复用清单）。
- 产品方向已定稿：`windows-companion-agent-brief.md` v0.1。
- 技术选型未锁定：Python 执行方案（Pyodide vs 受限进程）待 T00 spike 后 ADR 锁定。
- 测试素材就位（均在仓库外 `D:\MyAgent\`，永不提交）：`D:\MyAgent\chatgpt-export-markdown-part-01-of-03.zip`（100 篇真实导出，可用于 G04/G05 题集；注意缺第 2、3 部分，覆盖有限）；`D:\MyAgent\codex\ChatGPT-MyStroy.md`（58 回合小说共创记录，小说模块需求来源 + 种子内容 + 导入测试语料）。
- 可复用代码已盘点：`docs/reuse-inventory.md`。核心资产：Cumulonimbus agent 底座（`D:\mycli`，Gitee，MIT——LLM 抽象可移植、调度模式 Rust 重写）、local-ai-chat-manager 会话导入与 FTS 检索（`D:\harnessremotedesktop`，MIT）。

## 任务看板（T00–T08）

- [ ] T00 仓库脚手架与技术 spike
  - 状态: NOT_RUN
  - 依赖: 无
  - 负责人: 待认领
  - 验证: 原型可启动；spike 对比数据；ADR-0001（技术基线）、ADR-0002（Python 沙箱）落 docs/adr/
  - 退出码: -
  - 证据: docs/evidence/T00-YYYYMMDD.md
- [ ] T01 记忆底座：移植 parser/scanner/storage + ChatGPT 导出适配器
  - 状态: NOT_RUN
  - 依赖: T00
  - 负责人: 待认领
  - 验证: cargo test 通过；真实导出包导入实测；中文检索题集（≥20 条）结果记录
  - 退出码: -
  - 证据: docs/evidence/T01-YYYYMMDD.md
- [ ] T02 四空间 schema 与出处检索 API
  - 状态: NOT_RUN
  - 依赖: T01
  - 负责人: 待认领
  - 验证: 隔离测试通过（跨空间默认不互通）；出处检索 API 有集成测试
  - 退出码: -
  - 证据: docs/evidence/T02-YYYYMMDD.md
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
- [ ] T07 模型接入与隐私设置
  - 状态: NOT_RUN
  - 依赖: T02, T03
  - 负责人: 待认领
  - 验证: G15、G16、G18 证据（Key 存储检查、外发预览演示、默认不采集检查）
  - 退出码: -
  - 证据: docs/evidence/T07-YYYYMMDD.md
- [ ] T08 性能实测与打包
  - 状态: NOT_RUN
  - 依赖: T04, T05, T06, T07
  - 负责人: 待认领
  - 验证: G19 门槛数字锁定并达标；G20 安装包产出
  - 退出码: -
  - 证据: docs/evidence/T08-YYYYMMDD.md

## Goal 验收项重评

每次验收后更新，不能沿用过期数字。

- NEEDS_RECHECK：G01–G20 全部（尚无证据）。
- PARTIAL：无。
- BLOCKED：无。
