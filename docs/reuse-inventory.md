# 可复用源码清单（reuse-inventory）

更新：2026-09-26 · 用途：开工前先查本表，不要从零重写已有轮子。

图例：**[移植]** 可直接拷贝改造 · **[参考]** 设计/模式复用，代码需重写 · **[仅产品参考]** 只看不抄

---

## 1. Cumulonimbus（mycli）—— 自研 agent 底座，MIT

- 本地：`D:\mycli` · 远端：`git@gitee.com:rendegou/Mycli.git`（在 **Gitee**，不在 GitHub）· npm：`@rendegou/cumulonimbus`
- 形态：TypeScript / Node 的 coding agent CLI，"把打断当一等公民"。这就是用户说的"之前做的 agent 底座，调度可以留着"。
- 注意：幻月是 Tauri/Rust + React/TS，mycli 是 Node。**TS 侧代码可移植到 Tauri 前端；Node 耦合件（better-sqlite3 等）只能参考、由 Rust 侧重写。**

### 1.1 调度/架构模式 [参考] —— 本项目最核心的复用

| mycli 模块 | 内容 | 幻月用在哪 |
|---|---|---|
| `src/core/events/` | 事件总线：一切状态由事件推导（用户输入/LLM chunk/工具结果/打断） | 桌宠的状态管理骨架：宠物行为、卡片状态、记忆写入都由事件推导，可测试 |
| `src/core/cancel/` | 取消信号树：父 abort 单向广播，子操作自己收尾 | 用户随时打断宠物的回答/练习讲解/小说续写 |
| `src/core/loop/machine.ts` | 状态机 IDLE → RUNNING → INTERRUPTING，事件是唯一事实来源 | 宠物"安静/干活/被打断"三态 |
| `src/core/steer/` + `src/core/aside/` + `src/core/threads/` | 说话即打断转向、旁路并行问答、线程归属 | 宠物回答时用户插话；主任务与旁路问题并行 |
| `src/core/context/` | 上下文修复：打断留下的悬挂 tool_use 自动补 cancelled，历史永远合法 | 直接决定幻月对话历史能否不 400 |
| `src/core/fuzz/` | cancel-fuzzer：200 轮随机打断 + 不变量（I1–I4，含"无野进程"） | 借鉴其测试法：把"随时可打断/无残留"变成可证明属性 |
| `src/core/session/` + `src/core/snapshot/` | 会话持久化 + git 快照/undo | 练习记录、小说版本回滚的设计参考 |

### 1.2 可直接移植的 TS 代码 [移植]

- `src/llm/openai-compat.ts` — OpenAI 兼容端点流式 + 工具调用收集。**DeepSeek 直接可用**，省掉幻月模型层最脏的活。
- `src/llm/provider.ts` / `models.ts` / `tokens.ts` — 供应商配置（预设 OpenAI/DeepSeek/Kimi/Qwen/智谱）、模型列表拉取、token 计数。
- `src/proxy/sse-parser.ts` — SSE 状态机 + 工具调用跨 chunk 累积，无状态抗脏数据。
- `src/proxy/wal.ts` — checkpoint_pre/post 原子写 + wal.jsonl 追加 + 恢复重放。

### 1.3 Node 耦合，Rust 侧重写 [参考]

- `src/memory/store.ts` + `src/mcp/` — 跨工具记忆系统（memory_search/add/list/remove，MCP server 可被任何 agent 调用）。**幻月记忆层的蓝本**：API 形状直接参考，存储由 Rust rusqlite 实现（better-sqlite3 进不了 Tauri webview）。
- `src/store/` — SQLite 存储模式。
- `src/tools/builtin/` — zod schema + 副作用分级 + 取消/超时/升级杀：工具设计规范参考。

---

## 2. local-ai-chat-manager（harnessremotedesktop）—— 会话导入与检索，MIT

- 本地：`D:\harnessremotedesktop` · GitHub：`Rendegou/local-ai-chat-manager` v0.4.2 Beta
- 形态：Tauri 2 + Rust workspace（`aichat-core` 纯 Rust + `src-tauri` 薄外壳）+ React/TS + SQLite FTS5。
- 注意：其路线图明确**排除 LLM 长期记忆与在线聊天**，与本项目互补不冲突。

### 2.1 高价值移植件 [移植]

- `crates/aichat-core/src/parser/jsonl.rs` — 流式 JSONL 解析（容错、BOM/CRLF、时间戳规范化、content 块拼接）。零耦合，最干净。
- `crates/aichat-core/src/scanner/fingerprint.rs` + `watcher.rs` — size+mtime→BLAKE3 三级增量判定、notify+debounce 文件监听。监听"新对话出现"正好对口旧想法花园。
- `crates/aichat-core/src/storage/migrations.rs` + `search.rs` — FTS5 external-content schema、触发器、安全查询构造、bm25/snippet。
- `crates/aichat-core/src/imports.rs` — 6 格式导入自动探测（含 Markdown）；ChatGPT 导出适配器在其基础上新增 `#### You:` / `#### ChatGPT:` 分段规则。
- `crates/aichat-core/src/adapters/`（codex/kimi/claude 等）— 逆向工程成果，直接复用价值最高。
- `src-tauri/` 外壳 + 前端 `lib/ipc.ts` 单一 IPC 封装层 — 新项目骨架模板。

### 2.2 已知坑（原项目注释/LIMITATIONS 已记录，移植必须处理）

- FTS5 + `INSERT OR REPLACE` 必须开 `PRAGMA recursive_triggers = ON`。
- bm25 排序必须 `ORDER BY rank`（写 `bm25()` 慢一倍）。
- **unicode61 不做中文分词**（docs/LIMITATIONS.md:31）：中文检索须先做题集验证（字符 n-gram / 关键词 / 语义召回对比），见 G05。

---

## 3. AgentCraft —— 教学交互规则，本地

- 本地：`D:\AgentCraft`（Java/Spring，游戏化 Agent 开发环境，同时是"可玩教材"）。Java 程序结构不进幻月。
- [参考] `CLAUDE.md:32-41` 教学模式 + `docs/YOUR-TURN.md:50-53` 口令协议：**考我一下 / 先只要接口 / 这段带我写 / 审阅我的答案**——幻月 Python 练习的口令词表直接照搬。
- [参考] 练习法：可运行空架子 + `TODO(Lx)` / `raise NotImplementedError` 占位锚点；每级绑定自测题；"面试怎么说"叙事模板。
- [参考] 双端规则同步约定（CLAUDE.md ↔ `.cursor/rules/` 镜像）。

## 4. dataCompare —— 调度模式，本地

- 本地：`D:\dataCompare`（Java/Spring Boot，数仓链路监控）。
- [参考] 任务表 + 轮询调度（`SCHEDULER_POLL_MS`）+ 任务立即执行 + 连续失败阈值 + Webhook 告警。幻月若做"定时低频提醒/后台扫描"，用 Rust tokio 定时任务重写这套模式。

## 5. 其他仓库与项目

| 项目 | 位置 | 复用方式 |
|---|---|---|
| pulse | GitHub `Rendegou/pulse`，本地 `D:\VenerableP\pulse` | [参考] Go/WebSocket 权威状态同步模式（如需实时状态推送）；前端是 Vue 3，不移植 |
| bytespace | GitHub `Rendegou/bytespace` | [仅产品参考] 本地优先、无网络请求的立场一致 |
| prime-agent | 本地 `D:\prime-agent`（PrimeIntellect 上游克隆） | [参考] RLM/子代理/持久 REPL 思想；**非自研，不拷代码** |
| DeepTutor | 本地 `D:\my-deeptutor\DeepTutor`（上游克隆） | [参考] 学习路径/题库设计；非自研 |
| MyStroy | 无源码；共创记录 `D:\MyAgent\codex\ChatGPT-MyStroy.md`（本仓库外素材，永不提交）（58 回合，已分析） | [参考] 写作工作流（跑团模式、试写/正稿、人物卡硬约束、待决议题看板）；[素材] 小说模块的种子内容与导入测试语料 |
| Clawd on Desk | 本地 `D:\clawdpets`（第三方 Electron 安装包） | [仅产品参考] 桌宠形态参考 |
| 毕业设计 | 本地 `D:\毕业设计` | [参考] 本文档体系（Goal/看板/证据/门禁）的工作流模板来源 |

## 6. 平台事实更正

- 用户 GitHub 公开仓库实际只有 3 个（local-ai-chat-manager、pulse、bytespace）；**agent 底座在 Gitee**（`rendegou/Mycli`）。用户记忆中的"~8 个仓库"其余为私有或纯本地项目。
- 若还有其他私有仓库需要纳入复用（如用户提到的其他 agent 项目），请补充，本表随之更新。
