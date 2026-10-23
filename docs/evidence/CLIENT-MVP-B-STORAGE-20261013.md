# CLIENT-MVP B：Rust 持久基础与原子作者操作

日期：2026-10-13。负责人：codex/b-storage。状态：领域实现与合成测试 PASS；原生端到端验收由主任务另记，本文不宣称 CLIENT_MVP_PASS。

工作目录 `D:\MyAgent\paraselene-work`，只处理 memory-core 和本文。既有未提交成果保留；未读作者私人作品库、Key 或凭据，未调用模型。Tauri/IPC/前端由主任务负责。

## 实现

- working copy 允许有效空正文并沿用 CAS。显式 delete 带 expected_revision，None 仅在无稿时幂等；旧窗口不能删新稿。保存返回本次提交的快照，避免事务后另读被下一窗口写入污染。
- V11 最小迁移增加 archived_at、location LoreKind、lore_source_anchors 与 novel_threads。旧 lore CHECK 通过事务重建父表，同时备份恢复唯一子表 lore_versions，原版本不丢。UI 设置复用 settings；未新增整作品 JSON 权威库、地图坐标或关系编辑结构。
- 章节归档/恢复检查作品及章节归属，重复归档幂等，保留版本/编辑稿/线程；活动摘要默认过滤归档，可单独读取归档摘要。重排仍维持全集合同，适配层负责合并活动与归档目录。
- 资料可保存空正文；专用 save_lore_entry 名称与新版本在一个 CAS 事务内保存，固定作者 origin，未确认不会被标为 AI。版本返回来自当前提交事务。关联出处显式检查同作品，保留旧版 stale 信息。
- 专用线程 CAS 持久化受校验 schemaVersion=1 快照，隔离 work/document/thread；校验冻结目标、UTF-16 emoji 坐标/quote、草稿、引用、请求、候选、记录等结构和大小。读取在途请求标 interrupted，不自动重新付费请求。正文保存与线程保存互不代替。
- confirm_author_working_copy 同事务校验 head、working revision、working baseHead，读取已保存正文，严格保留非空正稿边界；创建 origin=user 版本，working revision+1/baseHead 同步。at_context 入口再核对用于冲突提示的有序 canonical `(documentId,versionId)` 签名。旧基础 API 保留。
- rollback_novel_working_copy 同事务校验 head、working revision、版本归属，移动 head 并丢弃指定稿，不删除历史分支。故障时整体回滚。
- derived 原 tests 原样拆到 derived_tests.rs，避免现存模块超过生产模块阈值；未修改摘要业务逻辑或增加基线豁免。

## 实际检查

环境：PowerShell 7；既定 Windows GNU Rust 工具链；PATH 前置 `C:\tools\paraselene-build\mingw64\bin`，target-dir 为 `D:\MyAgent\.cargo-target`。

1. `cargo test -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline`：退出 0，102 unit + 5 author-version + 6 storage + 6 lore = 119 tests PASS，0 filtered。涉及文件库关闭重开、空稿恢复、跨作品拒绝、stale revision/base/head/context、迁移失败恢复、未来库拒绝和故障事务回滚。
2. 最终资料提交快照/线程大小校验之后，`cargo test -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline --test client_mvp_storage --test client_mvp_author_versions`：退出 0，6 + 5 PASS。
3. `cargo test -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline client_mvp_migration_tests`：退出 0，3 PASS。V10 合成文件库原稿/编辑稿 revision/资料版本/出处完整，升级重开可建空地点；故意阻断 V11 保持 user_version=10 且数据未变，移除阻断后可继续；未来版本拒绝无写。
4. `cargo clippy -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline -- -W clippy::cognitive_complexity`：退出 0，无 Clippy 警告。
5. `pwsh -File scripts/check-quality.ps1 -Check rust-metrics`：退出 0，baseline/current 均 36，added=[]。本轮新函数/模块未增加度量债务。
6. 对本轮触碰的 Rust 模块与新增测试定向 rustfmt：退出 0。未运行或宣称全仓 cargo-fmt PASS。

沙箱初跑曾拒绝 rustfmt/Clippy 配置访问，部分旧文件操作/摘要测试失败；用已授权的既定工具链提权全量重跑全部通过。保留既有 test unused-import/unused-variable/non-snake-case 警告，不批量清理他人代码。

## 公开入口与限制

公开 API 位于 `novel/author_versions.rs`、`archive.rs`、`lore_edit.rs`、`lore_sources.rs`、`threads.rs`；NovelThread 已从 memory-core 导出。删除和回退的 expected_revision 类型为 Option<i64>，作者确认的 revision 为 i64。

at_context 的签名覆盖现有 novel_canonical_entries 正稿文档版本，调用方须使用计算 conflict warnings 的同一份 entries 生成签名，不能另读一个新签名掩盖检查期间的变化。来源锚点 Rust 范围仍为 Unicode scalar，线程编辑器范围为 UTF-16，边界转换由适配层负责。

原生关闭、IME、安装升级、系统导出及真实请求没有在此子任务运行。以上领域测试不能替代 A/B 原生出口；主任务需以同一构建验证实际客户端并更新总体证据。
