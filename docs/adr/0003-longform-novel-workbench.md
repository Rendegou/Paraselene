# ADR-0003：长篇小说工作台与上下文架构

日期：2026-10-03。状态：原则 ACCEPTED（依据用户明确需求）；编辑器库与数值预算 PROPOSED，T05B spike 后补结论。此ADR不是已实现声明。

## 问题

当前生成串接全作品确认稿，30,000字以上拒绝；文档列表含全文、textarea集中在单组件。用户要章节/设定目录、正文、Agent/diff/引用工作台，并能长期追踪伏笔和人物动机。

## 已确定原则

1. 保留Tauri2/Rust/React/SQLite底座和现有版本树，按小说领域渐进迁移。
2. 按章加载与视口编辑；本机自动保存编辑稿，用户确认后进入正史。
3. 分层/限预算上下文；设定、时间范围、出处和版本依赖可追溯。摘要/索引为可重建派生物。
4. AI修改必须先预览diff；版本变化拒绝覆盖，用户采纳、撤销及确认正稿分开。
5. 首版SQLite表达关系，本机FTS/trigram/别名检索；不引入外部数据库/后台服务，不照搬其它产品代码。

## 编辑器候选与决策门槛

推荐先验证 CodeMirror6：适合以纯文本小说为中心、交易式更新和视口渲染的适配层。Monaco作为编辑/diff对照，但不把代码IDE整套UI搬来；Tiptap/富文本会引入更复杂文档模型，目前没有强富文本需求。保留textarea作性能与行为基线。

T05B必须对真实WebView2中的中文IME、UTF-16坐标、长行换行、undo/redo、恢复、当前章节规模与内存出证据，才锁定库与版本。依赖无法满足时记录替代原因，不未经测量宣称某库必然快。

## 代价与后续

需要增加working copy、引用、派生任务与context manifest的存储/契约；复杂度按阶段控制。向量语义检索、图可视化、多Agent协调延期。详情在 [数据与上下文规格](../novel/context-and-storage.md)、[实施计划](../novel/implementation-plan.md)。

## 决策记录位置

T05B结束追加：实际候选版本、合成数据规模、运行环境、响应/内存结果、失败项、最终选择与证据链接。调整性能目标必须给实测依据与原因，不把未达标改成PASS。

## T05B spike 结论（2026-10-03，kimi/t05b-workbench-20261003）

**最终选择：CodeMirror 6 锁定为长篇小说工作台编辑器**（候选验证通过）。

- 实际候选版本：`@codemirror/state 6.7.6`、`@codemirror/view 6.43.13`、`@codemirror/commands 6.11.1`（pnpm 锁定；`@codemirror/history` 独立包已废弃、历史能力并入 commands，未采用）。
- 运行环境：本机 Windows + WebView2 运行时，`paraselene.exe` 调试构建（GNU 工具链），Tauri 窗口 `editor-spike`（1654×1187）。
- 合成数据规模：确定性 LCG 生成 100 万字（1,000,005 code point，含 emoji/CRLF 边界样本）；编辑内文档长度 999,992（CM6 文本模型口径，与 code point 计数不同属预期）。
- 实测结果（真实 WebView2，非浏览器模拟）：
  - 全量样本装入 42.1 ms（25.6–42.1 ms 三次波动）；JS 堆 29 MB；进程内存 71.7 MB。
  - 撤销回到写入前 PASS（999992→999997→999992）；重做恢复写入 PASS（999997）；emoji 后坐标为 UTF-16 偏移 PASS（head=999998，回读「😀坐标探针」精确命中）。
  - 中文 IME：真实键入（拼音 "ni"）触发 compositionstart/end，组合文本实时落在百万字文档光标处（工具栏计数 1 次 · 最近「ni」）。
- 机制发现（写进产品约束）：CM6 历史默认按 500 ms newGroupDelay 合并相邻事务，批量装入与随后写入会合并成一个撤销步；程序写入必须用 `isolateHistory` 注解切开（自检适配器已按此实现）。坐标契约统一 UTF-16 code unit，前后端换算只信 `sliceString` 回读。
- 失败项/限制：自动化只能证明单次组合事件；候选窗选字、组合中滚动/切章等长尾 IME 交互未覆盖，列入 T05H 人工补验。性能目标仍以实施计划 §11 锁定口径在 T05H 复测（本次为 spike 采样，非门槛验收）。
- 证据：`docs/evidence/T05B-spike-webview2-pass.png`、`docs/evidence/T05B-spike-webview2-ime.png`。spike 页面 `src/features/novel/editor/EditorSpike.tsx` 保留供 T05H 复验，产品化时以 CM6 替换工作台 textarea。
