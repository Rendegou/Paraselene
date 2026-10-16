# M4 owned-synthetic 持久化实施合同

先读 `docs/ADR-004-m4-synthetic-persistence.md`，本合同实现该决策；不包含 UI。

## 边界与接口

- Windows / pwsh；仓库 `D:\MyAgent\paraselene-flutter`，分支 `codex/flutter-migration-20261015`。原工程 `D:\MyAgent\paraselene-work` 只读，绝不访问作者库/密钥/env；`rust/core/**` 79 文件保持原样。
- 新增独立的 `Session::open_owned_synthetic()` 及 FRB 入口和 `RealWorkspaceRepository.openOwned()`；现有 `open_synthetic(root)` 的来源保护和现有测试保持。
- 正式 owned store 固定在 `D:\MyAgent\paraselene-flutter\build\m4-owned-synthetic-v1`。不接受外部原始库、导入文件或任意生产目录参数。测试使用应用内部受控 test-only 根或独立 synthetic 测试根，不能删除既有用户状态。
- 存储发布的内容是当前用户 DPAPI 保护的、版本化、目的/固定位置绑定的完整 SQLite 快照；DPAPI 不被宣传为抵抗同用户主动伪造进程的安全边界。
- 启动验证并解封后，排他创建新的随机标记 M1 fixture，写入新建且已固定身份的空 DB，再 Database::open；不能通过 marker 绕过旧的未知已有文件拒绝。
- SQLite backup API 复制到内存连接后 serialize；不得假设 WAL 主文件或裸 serialize 自动包含已提交逻辑状态。只加应用层缓存依赖/features，core 不变。

## 原子性与生命周期

- owned store 整个会话排他进程锁；路径链/文件拒绝 reparse 与 hardlink、未知已有非空内容。已有损坏状态启动报错，不替换为空库。
- 所有数据库变更：同一 State mutex 内执行应用操作、生成快照、DPAPI、排他临时文件写入、flush、原子替换已发布 payload，然后才向调用方返回成功。初始化/迁移也在 ready 前发布。
- 全部写入口都要覆盖：create/save/draft discard/chapter changes/confirm/rollback/select_work/set_ui_session，以及 workspace_state 的损坏最近记录备份。用一致 helper 避免入口漏接；读取不应每次无条件发布。
- 发布失败返回稳定 ASCII `durable_save_failed`，毒化会话；其后读写都拒绝，保留最后已发布快照，不能在 close 重新发布。Dart 内存稿由 SaveCoordinator 保留供导出。显式 close 应仍能安全释放 DB/fixture/进程锁。
- 进程强杀后下一次启动恢复最后完整成功发布的快照。发布成功但响应丢失允许恢复较新提交。不尝试用旧 revision 在已提交但未发布的内存库继续写。
- 正常 close 释放资源；不可误删 caller-owned 路径；临时 fixture 只清理自己新建并核验的根。
- 保存选中 work 与最近/每作品 UI prefs 的冷恢复；选中 work 可由最近第一项推导，需明确并测试。
- 全量快照限 M4 合成数据，记录成本，不能声称作者大库性能通过。

## 必须验证

1. 两个独立 native 进程：A 建两作品/两章、保存精确 Unicode/CRLF/空正文/修订/最近/UI、确认与历史；强制终止 A，B 恢复已成功稿及相关元数据/hash。
2. 同时第二写者拒绝，第一会话退出/被杀后可重新打开。
3. payload 篡改、reparse/hardlink、未知 raw DB/目录内容拒绝，且旧 M1 provenance tests 仍通过。
4. 实际持久发布故障：提交后 seal/publish 失败，返回 durable_save_failed，后续 read/write 拒绝，close 不发布，重开只有上次成功状态。
5. 原子发布故障前后只能读到完整旧或新快照，不能部分 payload；使用明确受控 fault seam，不称作真实断电硬件测试。
6. Dart real-FFI openOwned/reopen 错误映射和仓库生命周期；原 API 回归。

SDK 单槽位。固定 Rust `cargo +stable-x86_64-pc-windows-msvc --target-dir build/rust-m1-msvc --locked --offline`（从 rust 跑时按现有脚本路径调整），Flutter `D:\flutter_sdk\flutter\bin\flutter.bat`；生成桥脚本 `scripts/generate-m1-bridge.ps1`。日志只写 `docs/evidence/m4/checks/m4-owned-*`，不得覆盖 M1/M2 历史日志。

生产模块不超过 400 行，函数目标40/上限60有效行。适当拆分；保持 constructor DI 和现有依赖架构。只写本切片，不触碰 UI/controller/SaveCoordinator。不得并行派实施代理。最终报告写 `docs/evidence/m4/OWNED_PERSISTENCE_REPORT.md`，包含具体命令结果/测试覆盖/NOT_RUN/性能代价；短回复 DONE 或 NEEDS_CONTEXT，SDK 槽位释放。不要 commit。
