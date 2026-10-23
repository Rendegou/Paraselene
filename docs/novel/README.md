# 小说客户端入口

更新：2026-10-12。用户要求放弃当前桌宠形态，先做好小说创作前端，缩减多线计划。

2026-10-13：原生正式入口已接 `studio/native/NativeStudioApp.tsx`，正式作品/保存/资料/讨论持久化已实施，原生验收进行中；浏览器与design入口继续预览。证据见 [B接线](../evidence/CLIENT-MVP-B-20261013.md)。真实DeepSeek与安装后出口尚未完成；下述未接线描述保留为2026-10-12历史。

当前只有三步：前端体验 → 真实内核接线 → 引用/Agent 深入。唯一任务状态源是 [最新看板](../progress-checkpoint.md)，当前产品目标见 [方向](../development-direction.md)。

本轮活动界面在 `src/features/studio/StudioApp.tsx`；原 `src/features/novel/` 版本/保存/patch/设定业务保留，下一步接入新界面。当前预览与正式 SQLite 数据分离，示例审阅不调用模型。

- [项目框架](../engineering/project-map.md)：目录、依赖方向和用户的创作路径。
- [客户端最低可用计划](client-mvp-plan-20261012.md)：从Demo到Windows客户端的四个交付出口、异常光标专项与其他Agent审查格式。
- [前端开源参考](frontend-references-20261012.md)：本轮选择、源码检查和排除项。
- [本轮交付证据](../evidence/NOVEL-UI-20261012.md)：实际检查、浏览器证据与未测范围。
- 历史 [产品规格](product-spec.md)、[上下文与存储](context-and-storage.md)、[八阶段计划](implementation-plan.md)、[旧开源研究](open-source-research.md) 保留；只在实现当前三步涉及的具体规则时参考，不重新展开整套规划。
