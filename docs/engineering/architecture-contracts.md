# 架构与数据合同

更新：2026-10-23。本文件维护仍有效的系统不变量、技术边界和当前目录归属，不列当前任务状态。它从原迁移计划与已落地 ADR 中收敛合同；原计划已[完整归档](../history/snapshots/migration-plan-before-unification-20261023.md)，其中旧目录提案、阶段授权和未实现状态不覆盖本文件或[当前状态](../progress.md)。

## 代码职责

- `apps/desktop/lib/workspace/presentation/`、`cowrite/`、`lore/`、`legacy/` 的界面负责展示和转发意图；可测试的业务/异步协调由 controller、registry、service 或 repository 持有。沿用构造注入与 ChangeNotifier/Listenable。
- `workspace/data/` 和 `native/` 是本地原生能力接缝。Widget 不自行新建数据库、网络客户端或 FRB 句柄；共享控件和主题经 `lib/theme/` 使用。
- `packages/text_contract/` 是 Flutter/IO/数据库无关的坐标和语言合同。编辑事务、布局、IME 与具体保存生命周期属于桌面应用。
- `rust/application/` 编排业务与存储，`rust/bridge/` 提供有限 FRB 边界；`rust/core/` 是带原来源/许可证/哈希的固定复用快照，不把修改原 Tauri 工程作为依赖。
- `native/generated/`、`l10n/generated/` 由固定工具生成，第三方快照按各自来源维护；不手改生成代码或通过扩大排除范围绕过自有代码检查。

普通目录边界和数据所有权由代码与 review 共同落实；当前 AST 门禁不证明全部 import 方向或深只读性质正确。已知接缝整改见当前队列，不以规范发布冒充源码已整改。

## 正文、坐标与语言

- 编辑器/选段范围使用半开 UTF-16 code units；Rust SourceAnchor 使用 Unicode 标量索引，UTF-8 bytes 与 grapheme 另有用途。边界转换拒绝 surrogate 中间位置、越界及不匹配引文。
- 不隐式做 NFC/NFKC、换行、全半角、标点、大小写或 bidi 控制符归一化。BLAKE3 由 Rust 对确切原文计算；Dart 验证 wire 格式不等于验证摘要对应正文。
- target/baseBody 保存完整冻结原文；锚点只随真实编辑事务映射，不用相似搜索重绑。只有全文精确恢复到 baseBody 时才可恢复已知原坐标。
- 同行多标记独立可达，段下仅一个活动线程；讨论 Widget、占位、请求和候选不进入正文坐标、复制、Markdown 或 undo 内容。候选采纳作为可撤销编辑动作，撤销不重新发请求。
- UI locale、作品/章节语言和生成输出语言独立。切 UI 语言不能改正文、hash、选区、undo、草稿或已预览材料；协议值和作者内容不本地化。

## 保存、版本、线程与关闭

- EditingSession 持有同步内存编辑稿，repository 是持久化写入口；Rust 裁决 document/head/revision/hash 与采纳事务。保存编辑稿、采纳候选、确认正式版本是不同动作。
- 保存按文档串行快照 CAS，flush 必须覆盖 await 期间新增编辑；冲突不通过偷换 expectedRevision 变成成功。确认/回退校验目标身份与当前版本；patch 正文与状态在同一事务采纳。
- 作者线程与服务端 operation 分开持久化；读时按 operationId 合并。作者快照不重复存服务端请求/候选，不放大快照上限掩盖重复数据。20 万字、四次操作、未发草稿及重开的回归语义保留。
- 切章/作品、归档、确认、回退和关闭等待适用的正文、偏好与线程保存；失败保留身份、内存稿与可达恢复入口。迟到响应绑定 session/work/document/thread/operation 身份或代次。
- 系统 X、Alt+F4、自绘关闭和应用退出共享关闭决策。确认保存/恢复选择后才实际关闭；重复请求合并，最小化不关闭会话。IME 组字须有明确提交/取消策略，不能强制丢弃。
- 恢复导出优先当前内存稿，其他章节失败必须说明部分结果；取消/失败不显示已保存。可读导出与可恢复密封备份分开，恢复演练不替换当前写入方。

## 原生、模型与数据来源

- FRB 的 Dart/Rust/生成器固定同版 2.11.1，版本握手和能力校验先于写入；不把整个数据库、Mutex 或平台对象暴露到 Dart。架构理由见 [M1 ADR](../adr/0001-m1-workspace.md)。
- 默认工作台使用真实桥接的应用自有持久合成库（owned-synthetic），由当前 Windows 用户 DPAPI 密封；独立临时 fixture 和专用 test-support DLL 各有来源/身份校验。细节见 [ADR-004](../ADR-004-m4-synthetic-persistence.md)，其旧实施状态以进度页为准。
- 现有 SQLite schema/迁移顺序、WAL/FTS/外键与存储来源防护不得因 UI 迁移改变。打开数据库可能迁移和写入，不能把未知作者库的 open 称为只读。
- owned-store 发布失败保留明确失败/毒化语义，不能使用已推进但未持久化的 revision 假称成功；现有存储损坏不得静默清空重建。
- 原作者库不接管、不扫描。未来接管必须有明确数据根、一致性备份/WAL策略、停写与单写者互斥、完整性及回退证明；新客户端加锁不能阻止未协作的旧客户端。
- 模型仅官方 DeepSeek BYOK 接缝。完整消息、引用、语言与版本组成同一次外发预览及一次性许可；改变材料须重预览。重连查询 operation，不自动重放付费发送。
- 取消确认不保证请求从未抵达供应商或零费用；取消/完成/采纳竞争由 Rust 状态和事务裁决。错误返回稳定 code/安全参数，不记录正文、凭据或私人路径。
- 学习 WebView/Pyodide 的隔离、权限和生命周期独立验收；Flutter 或 Python Worker 本身不构成安全沙箱。桌宠/学习的专项通过不继承为写作或全系统通过。

## 工具链、性能与分发

当前已测基线为 Flutter 3.32.1 / Dart 3.8.1、FRB 2.11.1、Windows x64 MSVC 目标；依赖按各包 `pubspec.lock` 与 `rust/Cargo.lock` 恢复。机器安装路径可通过脚本参数覆盖，不改全局工具链默认值来满足单个任务。升级另作兼容性任务，并重验绑定、字体和 golden 环境。

生产编辑器使用 raw UTF-16 自有排版/输入路径。20 万字编辑 P95 ≤50ms 的目标和超长单行冷跳/stress 滚动限制见 [M3 方案](../M3-PRODUCTION-EDITOR-PLAN.md)；性能结论必须绑定 profile/release、设备、合成样本与当前源码，旧数字不自动继承。

发布交付完整 Flutter Windows bundle，核对 bridge/插件/运行时/字体和受控 DLL 路径，不能只发 EXE。净机、离线/中文空格路径、非管理员、安装升级及数据保留独立验收。开发检查、视觉检查与发布批准的流程见 [Agent 工作流](agent-workflow.md)。
