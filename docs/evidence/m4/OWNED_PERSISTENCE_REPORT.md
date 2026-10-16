# M4 owned-synthetic 持久化实施报告

2026-10-16。实现 ADR-004 与 `OWNED_PERSISTENCE_BRIEF.md`。状态：**Rust 与 Dart 真实 DLL 层 PASS；Windows  runnable 关闭屏障与 M4-6 组合验收 NOT_RUN**。

## 本次完成（相对 GPT 断点）

- 补完 `workspace.rs` 的 `with_state` 闭包（断点时编译阻塞点），并把 `with_db` 统一路由进
  `with_state` 变更屏障：所有写入口（create/save/discard/chapter/confirm/rollback/
  select_work/set_ui_session/workspace_state 的损坏备份写）经同一 helper 发布，读取不发布。
- `close()` 改为绕过毒化检查直接释放 DB/fixture/进程锁（合同要求显式 close 始终可用；
  毒化会话不再发布）。
- 新增跨进程测试辅助进程 `src/bin/m4_owned_helper.rs`（seed/dump/hold/crashy）与
  `tests/m4_owned_store.rs`；新增进程内故障测试 `src/owned_fault_tests.rs`。
- FRB 重生成（2.11.1，`openOwnedSynthetic` 进入 Dart 绑定）；`RealWorkspaceRepository.openOwned()`
  与 `_root` 可空化；`test/m4_owned_repository_test.dart` 真 DLL 双会话恢复 + 错误映射。

## 合同六项验证对照

| 合同要求 | 证据 | 结果 |
|---|---|---|
| 1. 两个独立 native 进程保存/恢复精确状态 | `two_processes_save_and_restore_exact_state`：seed 与 dump 两个进程的规范输出逐字节一致（含 CRLF/emoji/空正文/revision/hash/最近作品/UI session/确认版本） | PASS |
| 2. 第二写者拒绝，持有进程退出后可重开 | `second_writer_is_rejected_then_recovers`（`owned_store_busy` → 退出后 dump 成功） | PASS |
| 3. payload 篡改/未知内容拒绝；reparse/hardlink | `tampered_payload_and_unknown_content_are_rejected`、`unknown_store_content_is_rejected`；旧 provenance 3 项保持 PASS | PASS |
| 4. 发布故障毒化、读写拒绝、close 不重发布、重开只含上次成功稿 | `publish_failure_poisons_session_and_close_never_republishes`（fail_publish 受控故障缝） | PASS |
| 5. 原子发布只读得到完整旧/新快照 | 同上：故障缝在原子替换前返回，重开为旧快照；`rolled_back_conflict_does_not_poison` 覆盖回滚误报 | PASS（受控故障缝，非真实断电） |
| 6. Dart real-FFI openOwned/reopen 错误映射与生命周期；原 API 回归 | `m4_owned_repository_test.dart` 2 项真 DLL 通过；`m4_repository_test.dart` 5 项、`m1_real_ffi_test.dart` 1 项回归通过 | PASS |

## 命令与退出码（日志在 docs/evidence/m4/checks/）

- `m4-owned-fmt.txt` exit 0；`m4-owned-clippy.txt` exit 0（-D warnings，all-targets）；
  `m4-owned-rust-tests.txt` exit 0（application 全量：lib 3 + hardening 6 + migration 1 +
  owned_store 6 + selection 2 + workspace 11 + provenance 3 + session 5）；
  `m4-owned-bridge-build.txt` exit 0。
- `m4-owned-dart-fmt.txt` exit 0；`m4-owned-analyze.txt` exit 0（--fatal-infos）；
  `m4-owned-dart-tests.txt` exit 0（8 项）；`m4-owned-domain-tests.txt` exit 0（19 项）。
- 全部 Rust 命令固定 `+stable-x86_64-pc-windows-msvc --locked --offline --target-dir build/rust-m1-msvc`。

## 代价与限制（如实记录）

- 每次变更发布=整库 backup→serialize→DPAPI→原子替换；发布失败比对也取一次逻辑快照。
  仅合成数据规模验证，不宣称作者大库性能。DPAPI 是当前用户保护，不抗同用户主动伪造进程。
- `open_owned_at_for_test` 是 doc(hidden) 的测试专用入口；正式入口固定 ROOT，不接外部库。
- 冷恢复选中作品=最近列表首项（owned_session.rs 内注释）；内存稿不抗强杀（只保最后已发布）。
- Windows 关闭屏障、UI 接线与 M4-6 真实组合验收属后续切片，本报告不覆盖。
