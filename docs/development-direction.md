# 当前执行方向（development-direction）

更新：2026-09-26 · 状态：Phase 0 未开工

## 1. 我们在做什么

「幻月」：一只常驻 Windows 桌面的轻量宠物，同一入口串起三个闭环——旧想法花园、小说共写、Python 5 分钟练习。需求细节见 `windows-companion-agent-brief.md`，验收合同见 `幻月-Agent执行Goal.md`。

## 2. 当前阶段与下一步

**当前阶段：Phase 0/1（T00、T01）已 PASS（2026-09-26）。** 脚手架与记忆底座建成：ChatGPT 导出 100 篇、Codex 273、Kimi 152 真实会话入库（104K 消息），中文检索 trigram 方案定案（recall@5 96%）。

下一步（看板 T02，依赖已满足）：

1. 四空间 schema（个人/旧想法/小说/学习）与隔离测试（G06）；
2. 出处检索 API（每条结果可回溯到原文位置，G08 的底座）；
3. **索引瘦身**（T01 遗留风险：104K 消息 trigram 索引 1.4GB，需 cap 工具输出/工具消息不进 FTS/contentless 等手段，影响 G19）；
4. 旧想法状态机（G07）可接续（T04）。

## 3. 里程碑顺序与理由

| 顺序 | 里程碑 | 理由 |
|---|---|---|
| 1 | Phase 0 脚手架 + spike | 技术选型（Python 沙箱、透明窗口）决定后续所有架构，必须先验证 |
| 2 | Phase 1 记忆底座 | 核心价值"找得回、有出处"依赖导入与检索；优先移植 local-ai-chat-manager 成熟件 |
| 3 | Phase 2 桌宠外壳 | 形象与常驻体验是产品形态，但依赖记忆底座才有内容可展示 |
| 4 | Phase 3 旧想法花园 | 第一价值闭环：用户第一次找回旧想法即感到价值 |
| 5 | Phase 4 小说共写 | 客单价最高的闭环，但依赖四空间隔离与试写/正稿隔离先落地 |
| 6 | Phase 5 Python 练习 | 依赖 Phase 0 的沙箱决策 |
| 7 | Phase 6 接入/打磨/打包 | BYOK、隐私设置、性能门槛、安装包 |

说明：Phase 2 与 Phase 1 可部分并行（窗口原型不依赖存储），但看板任务仍按依赖顺序认领。

## 4. 当前验收口径

- 一切按 `幻月-Agent执行Goal.md` §9 的 G01–G20；每个 Phase 的完成以证据落 `docs/evidence/` 为准。
- 中文检索是已知风险：local-ai-chat-manager 的 FTS5 unicode61 不做中文分词（其 docs/LIMITATIONS.md 明确记录），Phase 1 必须用真实中文导出做题集验证（字符 n-gram / 关键词 / 语义召回对比），结果决定索引方案。

## 5. 风险与开放问题

- **Python 沙箱**：Pyodide 隔离性好但内存/启动成本高；受限进程轻但隔离证明难。等 T00 实测。
- **中文检索召回**：题集未建前不承诺召回率数字。
- **跨语言移植**：agent 底座 Cumulonimbus（`D:\mycli`，Gitee）是 TypeScript/Node，幻月是 Tauri/Rust。LLM 抽象/SSE 解析可移植到前端；事件总线、取消信号树、状态机等调度模式以 Rust 重写（见复用清单 §1）。
- **MyStroy 素材已就位**：`D:\MyAgent\codex\ChatGPT-MyStroy.md`（本仓库外素材，永不提交）（58 回合共创记录）已完成分析，小说模块需求（跑团模式、人物卡硬约束、待决议题看板）已落入 brief §3 与 Goal §4.3/G09；该文件同时作为种子内容与导入测试语料。
- **性能门槛未定**：G19 的具体数字待 T00 基线后锁定。

## 6. 边界提醒

- 不碰公司业务项目；公司资料默认不导入。
- 不使用网页版 ChatGPT 反代；模型只走 DeepSeek 官方 API BYOK。
- 每次会话结束必须更新 `docs/progress-checkpoint.md`（当前事实 + 任务状态）。
