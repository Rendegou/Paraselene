# ADR-0003：通过适配层与插件接入 dsh 运行时

- 日期：2026-10-23
- 状态：接受迁移方向；默认后端切换待 M03、M05 验收
- 依据：用户要求评估 Rust 核心迁往 dsh，并进一步要求“计划迁移，然后开始执行”
- 执行计划：[dsh-migration-plan.md](../dsh-migration-plan.md)

## 背景

幻月现有前端已经使用 React、TypeScript 和 Vite。Rust 工作区提供记忆导入、SQLite 检索、出处、旧想法状态、角色包及模型流式调用；完整 Agent 工具循环、任务取消与恢复仍待建设。

DeepSeek Harness（dsh）提供可组合的 Agent 运行设施。其模型、持久化、工具和 Agent 循环都是插件，独立产品可以经自定义 profile 与桥接插件驱动运行时。当前检查基线为 `0.2.1-rc.2`、提交 `687f282e8625c6b8d11ff58211a90524be2e4317`，仍处于开发预览期，存在破坏性变更。

这次迁移复用通用执行能力，保持幻月的桌面产品方向和长期数据边界。接入 dsh 不等于已经获得有出处的长期记忆，也不代替小说与 Python 执行环境的验收。

## 决策

1. 幻月独立发行。使用固定版本 dsh、自定义 profile 和随幻月发布的自有插件，不维护长期 fork。
2. 界面面向幻月定义的 TypeScript 运行时契约。适配层只处理请求、预览授权、流式事件、任务身份、取消和能力声明，不预先建设多框架通用平台。
3. 当前 Rust 模型实现先接入同一契约，作为兼容基线；dsh 通过独立进程的桥接协议实现后续适配。应用启动经 dsh profile，不直接依赖上游内部插件树作为私有启动器。
4. 幻月数据库拥有长期业务状态：原始导入资料、出处、个人事实、旧想法、小说正稿及学习记录。dsh 日志拥有 Agent 执行过程。业务写入由幻月领域接口完成，不让两套存储同时修改同一份权威数据。
5. Tauri 原生窗口、系统凭据、现有记忆服务先保留。数据库迁往 TypeScript 是独立决策，不与运行时替换捆绑。
6. M03 完整外发授权、M05 Windows 原生验收通过前，产品默认后端保持现有实现。实验必须标明 REAL / SIMULATED / PLANNED，能力缺失显式报错，不自动绕过授权或切换实现。

## 必须保持的约束

- Key 不进入 WebView 或 dsh 进程；正式 dsh provider 经原生受控出口调用 DeepSeek 官方 API。系统凭据存储沿用现有能力。
- 预览绑定最终待发送内容，后端保存请求并消费一次性票据；发送前再次检查空间云开关。工具结果、后续轮次、压缩、标题及子 Agent 调用都受同一出口约束。
- `llm/stream` 可观察标准模型调用，但仍早于 provider 最终协议投影。只在此处挂一个预览 hook，不能证明“预览等于实际发送”。
- 不挂载会增加未批准外发内容的插件。关闭官方组合默认启用的增量会话日志上传和插件包信息贡献，核对额外遥测；只批准提示词不代表批准会话日志字段。
- 四空间和小说作品的权限在幻月后端验证，不能相信模型提供的 `space` 或 `workId`。原始全文检索接口不直接成为模型工具。
- 模型只产生候选或试写。事实、旧想法状态和小说正稿由用户确认；Python 执行继续遵守 ADR-0002，dsh 的 shell 工具不能代替学习沙箱。

## SDK 取舍

当前官方 TypeScript SDK 没有运行中单次取消协议；关闭运行时才会中止。双向审批所需的 server→client requests 尚未实现，`run().finalResponse` 也只是活动区间内最后提交的助手消息。

因此默认 SDK 可用于受限原型，不能直接充当完整产品交互层。自有桥接插件需要明确任务身份、流事件终止语义、取消确认与进程退出行为，再通过契约测试和真实 dsh 离线验证。上游公开 Agent 接口具备取消能力，不等于幻月已经接通它。

## 代价与退出路径

插件仍需跟随上游破坏性变更维护；固定版本、锁文件和契约回归将变化集中到适配层。额外 Node 进程的冷启动、驻留内存、CPU 与打包复杂度必须在 Windows 实测后接受。

M01/M02 不修改现有数据库格式。回退时停止并回收 dsh 进程，丢弃当前待确认请求，以现有实现重新预览；不得自动重发、双写正稿或把未完成请求标成成功。若后续涉及数据格式变更，先另立迁移与兼容方案。

## 参考

- [dsh 架构与 profile 组合](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/docs/architecture.md)
- [TypeScript SDK 当前限制](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/sdk/client/README.md#known-limitations-and-deferred-work)
- [模型服务与统一调用边界](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/llm/llm/README.md)
- [官方会话日志上传配置](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/session/session-log-deepseek/README.md)
