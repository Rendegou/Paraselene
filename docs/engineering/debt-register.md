# 长度/复杂度债务登记册（T05A 基线）

更新：2026-10-03 · 负责人：kimi/t05a-quality-20261003
2026-10-12：旧 App 已移至 LegacyApp 懒加载；两项历史例外只迁移路径，未扩大基线。新增 studio 组件、hook 与模块无超标。
口径：`scripts/quality/code-metrics.mjs`（TypeScript AST，typescript 5.9.3）与
`tools/code-metrics`（Rust AST，syn 2.0.119）。有效行排除空行与整行注释；
函数/组件经 AST 识别。阈值见 [代码规范](code-standards.md) §2。

- 机器可读基线（当前违规全集）：[code-metrics-baseline.json](code-metrics-baseline.json)、
  [rust-metrics-baseline.json](rust-metrics-baseline.json)。
- 门禁语义：`check-quality.ps1` 的 ts-metrics / rust-metrics 要求**当前违规 ⊆ 基线**；
  新增违规即 FAIL，从基线消失计 resolved。不允许通过扩大基线消化新代码。
- 历史基线快照（拆分前）：TS 9 项 / Rust 38 项，记录于
  [T05A 证据](../evidence/T05A-20261003.md)；拆分后 TS 7 项 / Rust 36 项。
  本看板只登记拆分后的存量债务；新代码超标必须先拆分，不得以"历史文件"名义入册。

清理条件符号：A=T05B 编辑器/目录改造时拆分；B=T05C patch 流程改造时拆分；
C=对应模块下次功能触碰时拆分；D=随 T06 恢复或对应 Phase 验收时拆分。

## TypeScript（7 项）

| 路径 | 符号 | 有效行 | 原因 | 负责人 | 清理条件 |
|---|---|---|---|---|---|
| src/LegacyApp.tsx | `<module>` | 415 | 桌宠/卡片/路由集中，超出本轮范围 | codex/phase2-quality-20260926 | C |
| src/LegacyApp.tsx | Card | 242 | 卡片页集中组件，同上 | codex/phase2-quality-20260926 | C |
| src/lib/ipc.ts | `<module>` | 401 | 全部 IPC 封装的唯一合法位置，T05B 随窗口路由/新命令拆分 | kimi/t05a-quality-20261003 | A |
| src/IdeaPage.tsx | IdeaPage | 163 | 旧想法页集中组件，非本轮 | codex/phase3-ideas-20260927 | C |
| src/MemoryPage.tsx | MemoryPage | 142 | 记忆页集中组件，非本轮 | codex/phase3-import-20260927 | C |
| src/ImportSection.tsx | ImportSection | 93 | 导入区组件，非本轮 | codex/phase3-import-20260927 | C |
| src/TargetPage.tsx | TargetPage | 73 | 目标详情组件，非本轮 | codex/phase3-ideas-20260927 | C |

小说工作台拆分后无 TS 违规：`NovelEditor.tsx` 491 行集中组件已拆为
`src/features/novel/`（组合根 + 8 个面板/状态模块 + 4 个纯函数模块）。

## Rust（36 项）

测试代码（`#[cfg(test)]`）计入文件行数的口径已标注；测试文件建议 ≤600 行。

| 路径 | 符号 | 有效行 | 原因 | 负责人 | 清理条件 |
|---|---|---|---|---|---|
| src-tauri/src/commands/novel.rs | `<module>` | 503 | 小说 IPC 命令集中，T05B 按命令域拆分 | kimi/t05a-quality-20261003 | A |
| src-tauri/src/commands/novel.rs | generate_fragment | 82 | 流式生成编排，随 T05G 取消/恢复重构 | kimi/t05a-quality-20261003 | B |
| src-tauri/src/lib.rs | run | 83 | 应用装配入口 | codex/phase2-quality-20260926 | C |
| src-tauri/src/commands/import.rs | select_import_file | 79 | 导入命令，非本轮 | codex/phase3-import-20260927 | C |
| src-tauri/src/commands/llm.rs | llm_chat_send | 78 | LLM 命令，非本轮 | kimi/paraselene-t07 | C |
| crates/novel-core/src/generation.rs | prepare_with_request | 75 | 从旧 lib.rs 原样迁移的拼接装配；T05E 分层预算重写时消失 | kimi/t05a-quality-20261003 | B |
| crates/llm-core/src/sse.rs | `<module>` | 436 | SSE 解析集中 | kimi/paraselene-t05 | C |
| crates/llm-core/src/client.rs | send | 62 | LLM 客户端发送路径 | kimi/paraselene-t05 | C |
| crates/memory-core/src/adapters/codex.rs | `<module>` | 983 | Codex 适配器集中（含测试行） | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/codex.rs | on_item_completed | 194 | 适配器解析大函数 | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/codex.rs | on_response_item | 106 | 同上 | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/codex.rs | on_event_msg | 62 | 同上 | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/kimi.rs | `<module>` | 878 | Kimi 适配器集中（含测试行） | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/kimi.rs | parse_streaming | 112 | 适配器解析大函数 | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/kimi.rs | on_loop_event | 91 | 同上 | kimi/paraselene-t01 | C |
| crates/memory-core/src/adapters/kimi.rs | handle_line | 85 | 同上 | kimi/paraselene-t01 | C |
| crates/memory-core/src/spaces.rs | `<module>` | 973 | 四空间层集中（含测试行） | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/spaces.rs | idea_状态机_合法与非法迁移 | 96 | 状态机表驱动测试数据 | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/spaces.rs | create_memory | 79 | 空间写入路径 | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/spaces.rs | 用户纠正与删除要求空间和当前版本且保留出处 | 76 | 出处链测试 | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/imports.rs | `<module>` | 910 | 导入编排集中（含测试行） | kimi/paraselene-t01 | C |
| crates/memory-core/src/imports.rs | scan_one | 86 | 导入扫描 | kimi/paraselene-t01 | C |
| crates/memory-core/src/imports.rs | parse_chatgpt_markdown | 71 | Markdown 解析 | kimi/paraselene-t01 | C |
| crates/memory-core/src/imports.rs | parse_markdown | 61 | 同上 | kimi/paraselene-t01 | C |
| crates/memory-core/src/import_file.rs | read_chatgpt_zip | 104 | ZIP 只读解析 | codex/phase3-import-20260927 | C |
| crates/memory-core/src/storage/migrations.rs | `<module>` | 774 | 迁移集中（含大量迁移测试） | kimi/paraselene-t01/t02 | C |
| crates/memory-core/src/storage/migrations.rs | v2_库升级后_四空间表就绪且数据不丢 | 87 | 迁移测试 | kimi/paraselene-t01 | C |
| crates/memory-core/src/storage/migrations.rs | v3_库升级后_trigram_瘦身重建 | 72 | 迁移测试 | kimi/paraselene-t02 | C |
| crates/memory-core/src/storage/migrations.rs | trigram_瘦身规则_tool不进索引且文本截断 | 62 | 迁移测试 | kimi/paraselene-t02 | C |
| crates/memory-core/src/storage/sessions.rs | `<module>` | 535 | 会话存储集中（含测试行） | kimi/paraselene-t01 | C |
| crates/memory-core/src/storage/search.rs | search | 103 | 检索 API | kimi/paraselene-t02 | C |
| crates/memory-core/src/ideas.rs | `<module>` | 733 | 旧想法域集中（含测试行） | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/ideas.rs | confirm_idea | 69 | 状态确认路径 | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/ideas.rs | convert_idea | 66 | 转换路径 | codex/phase3-ideas-20260927 | C |
| crates/memory-core/src/scanner/mod.rs | scan_one | 82 | 扫描编排 | kimi/paraselene-t01 | C |
| crates/memory-core/src/parser/jsonl.rs | stream_jsonl | 67 | JSONL 流解析 | kimi/paraselene-t01 | C |

## 本轮已消除

- `src/NovelEditor.tsx`（模块 462 行 / NovelEditor 组件 409 行·复杂度 63）→ 拆分完成，无超标。
- `crates/novel-core/src/lib.rs`（模块 719 行）→ 拆为 edit/generation/rpg/stream 四模块。
- `crates/memory-core/src/novel.rs`（模块 713 行）→ 拆为 novel/{mod,drafts,versions}.rs。

