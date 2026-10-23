# 开源小说工具：上下文与长篇可靠性研究

研究快照：2026-10-02；整理：2026-10-03。范围是公开仓库的 README、设计文档、选定源码与许可证元数据；没有安装运行这些产品，也没有测它们的百万字性能。下列“文档声明”和“源码核对”分开记录，不能据此声称它们绝不会崩溃。

## 1. LunaRime/novelforge：编辑工作台与按需记忆

[仓库](https://github.com/LunaRime/novelforge)，master 快照 `3e860f8b08ba2083787c695182ae4ae0dcbd862a`，GPL-3.0。

文档描述章节/正文/提示/AI记忆的工作台和可审阅写入。源码 `memory-layers.ts` 将记忆分为常驻、自动、手动引用；正文与目录分配不同预算。`context-builder.ts` 会过滤 stale 条目并报告超限。常驻或显式引用超限时可整段退出，而非保证关键约束一直存在。

借鉴：小型常驻设定、记忆目录、显式引用、预算可见性。幻月应在必需设定装不下时阻止发送并说明原因，不允许悄悄遗漏。diff 展示也需要后端版本检查。

源码依据：[记忆分层](https://github.com/LunaRime/novelforge/blob/3e860f8b08ba2083787c695182ae4ae0dcbd862a/src/services/agent/memory-layers.ts)、[上下文装配](https://github.com/LunaRime/novelforge/blob/3e860f8b08ba2083787c695182ae4ae0dcbd862a/src/services/agent/context-builder.ts)、[DiffViewer](https://github.com/LunaRime/novelforge/blob/3e860f8b08ba2083787c695182ae4ae0dcbd862a/src/components/editor/DiffViewer.tsx)（路径确认，未完整审计 diff 实现）。

## 2. qnbs/WorldScript-Studio：写作语境与正史

[仓库](https://github.com/qnbs/WorldScript-Studio)，main 快照 `4f33d7786076c1d00e73d5db9c527fbd1ea31693`，MIT。

README 描述本机优先、作品模型作为权威、结构化实体与RAG/Story Bible关联。核对 `copilotContextService.ts` 可确认它用当前页面、作品统计、当前章与有限选段构建轻量提示；这只是 Copilot 入口，不代表全部正文生成路径。本快照未确认自动排除未来章节的实现。

借鉴：当前章明确的写作范围、设定与来源联动。幻月把“早于当前章节/场景”和“人物此时知道什么”做成可测试契约。可选图数据库不引入本项目。

源码依据：[轻量 Copilot 上下文](https://github.com/qnbs/WorldScript-Studio/blob/4f33d7786076c1d00e73d5db9c527fbd1ea31693/services/copilot/copilotContextService.ts)、[README 快照](https://github.com/qnbs/WorldScript-Studio/blob/4f33d7786076c1d00e73d5db9c527fbd1ea31693/README.md)。

## 3. YILING0013/AI_NovelGenerator：章节生成与连续性状态

[仓库](https://github.com/YILING0013/AI_NovelGenerator)，main 快照 `f9aefef90b1493c579d7f72547efb4a3d8a0da25`，AGPL-3.0。

`chapter.py` 分别读取全局摘要、人物状态、最近章节，并加入检索材料；`finalization.py` 更新摘要、人物状态与向量库，单个文本文件采用原子替换。多个文件与索引的更新仍不能由此推导为一个整体事务；向量更新失败可留下警告。

借鉴：把正文、压缩状态、检索分开。幻月需要版本依赖、事务 outbox 与可恢复重建队列，避免正稿更新后摘要/索引仍悄悄引用旧状态。向量检索作为后续增强，不成为首版运行依赖。

源码依据：[章节上下文](https://github.com/YILING0013/AI_NovelGenerator/blob/f9aefef90b1493c579d7f72547efb4a3d8a0da25/novel_generator/chapter.py)、[定稿流程](https://github.com/YILING0013/AI_NovelGenerator/blob/f9aefef90b1493c579d7f72547efb4a3d8a0da25/novel_generator/finalization.py)。注意不要与其它作者的同名仓库混淆。

## 4. Xiaoyangy/novel-studio：Agent 长任务与压缩策略

[仓库](https://github.com/Xiaoyangy/novel-studio)，main 快照 `ed04a106f665f456246af3c4414ba62992a2a1d1`，Apache-2.0。

此快照为 Go 项目。上下文文档区分多种 Agent 会话；`internal/agents/context_manager.go` 接入工具结果压缩/完整摘要，保留输出与近期上下文预算，对承载本书事实的工具结果区别处理。README 提到中断续跑；没有在本次验证其崩溃恢复可靠性。

借鉴：正文事实与普通工具日志不能一视同仁压缩，长任务需要可观测预算和持久化阶段。幻月首版保留单一共写 Agent，先做好取消/候选/恢复，再考虑多 Agent 编剧体系。

源码依据：[上下文机制](https://github.com/Xiaoyangy/novel-studio/blob/ed04a106f665f456246af3c4414ba62992a2a1d1/docs/context-management.md)、[上下文管理器](https://github.com/Xiaoyangy/novel-studio/blob/ed04a106f665f456246af3c4414ba62992a2a1d1/internal/agents/context_manager.go)。

## 5. 长文本编辑：单独验证，不能用模型记忆代替

[CodeMirror 官方指南](https://codemirror.net/docs/guide/)说明视口外内容避免全部绘制；[百万行示例](https://codemirror.net/examples/million/)是编辑器能力演示，不是幻月中文/IME/WebView2性能证据。目标选型为 CodeMirror 6 文本编辑适配层，T05B 用实际基准确认；Monaco 与现有 textarea 是 spike 对照。视口渲染解决 DOM 成本，仍须按章读取、限定编辑缓存、后台 diff、恢复自动保存。

## 6. 形成的方案

- 保留原始确认正文，建立设定与出处索引；摘要是可丢弃、可重建的派生物。
- 每次请求只装配任务需要的硬约束、当前选段、近期状态、相关证据；不拼全书。
- 区分作者全知事实、角色认知、叙述时间和未来计划；历史章修改不能自动读取未来回收结果。
- 云上下文明确 token 预算、来源与省略原因，必需内容超限就阻止请求。
- UI 按章加载；AI 输出是待审核 patch；版本冲突拒绝覆盖；确认后的索引更新可续跑。
- “百万字不崩”落实为数据规模、响应时间、内存、异常退出、引用失效的验收集，不能凭 README 或提高字数常量承诺。

## 7. 许可证与后续复用

上述 SPDX 来自2026-10-02 GitHub仓库许可证元数据，具体复用还需核对选中文件头、依赖与锁定版本 LICENSE。当前只参考机制，未移植代码；GPL/AGPL 内容不直接粘进幻月 MIT 核心。MIT/Apache 也要保留对应署名/声明并复测。复用状态写入 `docs/reuse-inventory.md`。

更细的代码审计属于实现阶段；不能把本次局部阅读当作这些项目的安全审计或功能认证。
