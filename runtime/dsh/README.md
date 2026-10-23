# dsh 桥接验证（M02）

状态：**REAL：官方 dsh CLI、Agent 循环、流式事件、取消与进程回收；SIMULATED：模型回复；PLANNED：产品接入及真实模型出口。** 这里不是可供用户选择的聊天后端，也没有“接不上 dsh 就返回固定文本”的产品降级路径。

固定依赖为 npm `@deepseek-ai/dsh@0.2.1-rc.2`，对应本轮审阅的上游 commit [`687f282e8625c6b8d11ff58211a90524be2e4317`](https://github.com/deepseek-ai/deepseek-harness/commit/687f282e8625c6b8d11ff58211a90524be2e4317)。`pnpm-lock.yaml` 固定依赖解析与包完整性；升级时必须重跑这里的真实运行时测试。插件为幻月自行实现，使用上游公开接口，没有复制或修改上游源码；上游依赖许可证为 MIT。

## 运行

在 PowerShell 7 中使用 Node.js **22.19 以上的 22.x** 与 pnpm 11；本次云环境实际验证 Node.js 22.21.1、pnpm 11.25.0。

```powershell
pnpm --dir runtime/dsh install --frozen-lockfile --ignore-scripts
pnpm --dir runtime/dsh test
pnpm --dir runtime/dsh probe
```

安装需要网络。测试不使用 API Key、不访问模型服务，只让本地 synthetic provider 产生测试回复。某些云执行沙箱默认禁止子进程或等待系统调用，会导致 Node `spawn` 出现 EPERM 或子进程无输出；应使用允许子进程的执行权限重新运行，不能将这种结果当成通过。本次使用云执行器的附加权限运行后，9 项测试全部通过；Windows 尚未验证。

`probe` 成功时仅打印运行时/模型类别和通过项，不打印用户语料。`test` 覆盖协议校验、真实流式输出、重复请求、并发拒绝、取消及随后继续工作、创建期间取消、空闲/运行中 EOF、超长输入关闭和临时目录回收。命令及实际结果由主迁移证据文档记录。

## 实现边界

- `src/launch.mjs` 通过官方 `dsh --profile paraselene-offline` 启动，使用新建临时 `DSH_HOME`，不读取已有 dsh profile。环境按允许清单继承系统/代理/CA 变量，不继承模型凭据或任意 Node preload。
- profile 仅挂载 `llm`、`session`、`session-projection`、`system-prompt`、`tools`、`agent`、`agent-loop` 及自有离线 provider/bridge。没有挂载 shell、文件工具、标题、压缩、遥测、日志上传或真实模型适配器。官方 CLI 的安装依赖仍较多，这份组合不代表最终安装包已精简。
- `src/bridge.mjs` 通过 `ctx.agents.create`、`followup`、`whenIdle` 和 `cancel` 驱动真实循环，消费 `agent/assistant-stream`。同一进程一次只接受一个活动，终止事件在 Agent 回收完成后发出。退出清理由 Cordis effect 注册。
- `src/offline-provider.mjs` 是**测试专用** `LlmAdapter`，固定回复 `OFFLINE_DSH_RESPONSE`；特殊合成提示用于验证运行中取消。它没有 HTTP 实现。会话仅在内存中，退出后不恢复。
- scope 校验只证明协议要求显式空间/作品归属，**不等于后端已验证用户授权**。真实记忆工具必须由幻月服务按授权和作品归属检查；M03/M04 完成前不能接入私人记忆。

## 协议 v1

一行一个 JSON 对象，UTF-8 单行最多 65,536 bytes。仅接受 `run`、`cancel`、`shutdown`，拒绝未知字段、凭据与路径配置。请求 ID 只允许 1–80 位字母、数字、下划线和连字符，同一进程中不能复用。

```json
{"version":1,"type":"run","requestId":"example-1","scope":{"space":"personal"},"prompt":"synthetic request"}
{"version":1,"type":"cancel","requestId":"example-1"}
{"version":1,"type":"shutdown"}
```

空间为 `personal/idea/novel/learning`；`novel` 必须携带 `scope.workId`，其他空间不接受作品 ID。响应为 `ready/started/delta/done/error`；每个活动的 `done` 携带 `completed/cancelled` 结果。非法命令或非活动 ID 的取消返回错误，不影响其他活动。异常错误使用固定消息，避免回显请求正文。stdin EOF 会取消活动并请求官方启动器退出；父进程清理有 EOF → SIGTERM → SIGKILL 阶梯并移除临时 home。

## 后续接入

M03 应以自有受控适配器替换测试 provider，保留原生凭据、最终请求冻结/预览、一次性授权与发送前空间重检。标题、压缩和子 Agent 的请求也必须遵守同一授权策略。随后才把桥接协议映射到前端运行时接口、增加持久化/恢复和业务工具，并在 Windows 验证打包与资源占用。当前没有完成这些工作，不能将本探针描述为内核迁移完成。
