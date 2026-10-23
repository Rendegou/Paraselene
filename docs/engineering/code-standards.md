# 代码规范与质量门禁

更新：2026-10-03。这些是从现在起执行的工程规则；自动检查工具接入为 T05A 的 PLANNED 工作，不能把本文当作已启用的 lint。

## 1. 从 ATLAS 借鉴什么

已只读检查 `D:\ATLAS\CONTRIBUTING.md`、`docs/MAP.md`、`scripts/production-readiness.py`。可借鉴的是目录地图、公共 API 契约、统一质量入口、本地/CI 同口径、不可用检查不能报通过、测试完整性约束。检查范围内未确认统一的函数长度上限；下面的长度/复杂度阈值是为幻月制定的规则。ATLAS 的 Python/Go/Linux 命令不搬到本项目，也不复制其 AGPL 代码。

## 2. 函数、组件与文件

- 普通函数目标 ≤40 个有效行，门槛 ≤60；函数只做一件事，业务流程用有意义的助手函数表达。
- React 组件函数 ≤150 个有效行；其中副作用/请求协调须提取到按领域命名的 hook。普通 hook/事件处理器按 60 行执行。
- 生产模块 ≤400 个有效行；测试文件建议 ≤600。`mod.rs`/公开 barrel 保持薄，只做导出/少量组装。
- TypeScript 圈复杂度 ≤10，嵌套业务分支建议 ≤3 层；Rust 采用 Clippy cognitive_complexity ≤20 的独立口径，不能把两种指标视作相同。
- 有效行排除空行/独立注释，函数/组件通过 AST 识别；禁止用简单正则、拆空函数、压成一行或到处 lint-disable 绕过门槛。
- 例外必须记录在带路径/符号/原因/负责人/清理条件的基线清单；新普通函数不得超过80行，组件不得超过200行。仅测试数据、协议表、生成代码可单独分类，不能用“历史文件”豁免新增复杂逻辑。
- 既有巨型文件按增量债务管理：不要求一次清完；修改复杂函数必须降低或保持指标，新逻辑进入新模块。例外不能永久无人负责。

## 3. 命名、类型与注释

- Rust 文件/函数 snake_case，类型 PascalCase；React 组件文件 PascalCase，领域 TS 文件采用项目约定的可读名称。避免 `data`、`temp`、`handleAll`。
- Rust public API 用 rustdoc，TS 导出函数/IPC 类型用 JSDoc 或清晰的接口说明：输入、返回、错误、副作用、版本条件、坐标单位。
- 注释解释原因与不变量，例如为何必须重新核对版本、为何不能把候选加入正史；不逐行复述实现。
- 禁止随意 `any`、双重类型断言、吞异常、业务路径 `unwrap/expect`。来自模型/文件/IPC 的输入进行结构、大小和作用域校验。
- 保留 typed error；UI 给可执行的错误反馈，日志只留错误码/ID/计数/耗时，不留正文/密钥。

## 4. 状态、异步与数据

- 每个请求绑定 work_id、document_id、base_version、working_revision、operation_id。切章/切作品/取消后，旧响应不得污染新页面。
- 所有关键写入事务化；乐观锁在后端检查。可重试写入有幂等键；并发写按章节串行/明确冲突，不能最后写入者静默覆盖。
- effect 清理监听/订阅/定时器；重渲染不创建第二个生成请求。取消信号传播到网络/流和任务队列。
- 正文不反复复制到 React 全局 state；索引、摘要、diff 放受控后台任务，主线程只更新可见内容。
- 迁移有合成旧库升级/重开测试。新规则保留已有版本树、正稿/试写隔离、云开关与外发票据。

## 5. 检查入口与工具状态

REAL：统一入口 `scripts/check-quality.ps1`（`-List` 列出检查与工具可用性，`-All` 全跑，`-Check <名称>` 单项；退出码 0 全过 / 1 有 FAIL / 3 有 NOT_RUN / 2 用法错）。AST 度量工具：`scripts/quality/code-metrics.mjs`（TypeScript AST，函数/组件/模块有效行 + 圈复杂度 + IPC 边界检查，基线 `docs/engineering/code-metrics-baseline.json`）与 `tools/code-metrics`（Rust AST syn 口径，基线 `docs/engineering/rust-metrics-baseline.json`）；例外登记在 [债务清单](debt-register.md)。前端行为测试：`scripts/quality/run-web-tests.mjs`（node:test + TypeScript 转译，零新增依赖）。检查项现状：typecheck/build/web-tests/ipc-boundary/ts-metrics/cargo-novel-memory-test/cargo-check-paraselene/rust-metrics/cargo-clippy 为 PASS；cargo-fmt 为 FAIL（历史文件未格式化，批量机械重写会污染他人改动，暂记债务，清理随各模块下次触碰单独 rustfmt）。检查入口须可列出检查并按项运行，本地与以后 CI 使用同一入口；缺工具/依赖/环境记 NOT_RUN/FAIL，不能返回虚假 PASS。

只新增与本阶段相关的必要依赖并锁版本，不混用包管理器。第三方依赖/核心编辑器选型写 ADR。已存在的 `pnpm-lock.yaml` 为前端锁文件，不能顺便重置整个依赖树。

可复跑基线命令（在工作副本，用 pwsh）：

```powershell
$env:PATH='C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
pnpm typecheck
pnpm build
cargo test -p paraselene-novel-core -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline
cargo check -p paraselene --target-dir 'D:\MyAgent\.cargo-target' --offline
```

一次运行一条并记录退出码；不要前一步失败后仍把整批报绿。格式/Clippy 接入后按变更模块运行，再报告遗留警告。全量命令 `cargo test --workspace --target-dir 'D:\MyAgent\.cargo-target' --offline` 在2026-10-01有凭据库环境失败；过滤 `-- --skip keyring_设置查询删除_往返` 的结果只算“过滤后通过”，不算 G20 全量 PASS。不读取凭据文件来规避失败。

## 6. 测试、review 与完成

- 领域规则用合成数据确定性测试；前端测用户行为/状态边界；Tauri 权限、IME、窗口和性能必须有真实 WebView2 证据。
- 重点断言：未确认不进正史、过期 patch 拒绝、重复采纳幂等、Unicode 不误替换、未来信息不越界、摘要失效可恢复。
- 测试应能发现错误，不仅镜像实现；禁止无断言、catch 后当 PASS、把 timeout 当成功、全部用 mock 却宣称原生通过。
- 每个阶段 review 对照 spec/数据不变量/迁移/取消/性能/隐私；无需为纯文案修改添加行为测试。
- 合并/交付前列出修改范围、实际命令、结果、未测项与证据；更新看板/模块文档。功能已写但原生未验收保持 PARTIAL。
