# 小说客户端交互修复与后续开发交接

日期：2026-10-13。用户明确要求新开会话，先做好交互细节，再继续执行 `docs/novel/client-mvp-plan-20261012.md`。新会话为本轮唯一代码、构建和原生窗口负责人；原会话完成交接后不再并行改动。

## 用户最新要求

用户报告：选中某段文字，左侧出现带数字的圆圈；关闭“选中修改”后圆圈消失。希望修好细节，并举一反三检查其他交互问题。根因尚未复现，不能只据代码宣称已定位。

预期：关闭面板收起临时界面，保留已创建讨论、草稿和可重新打开的页边标记。仅普通选区没有创建讨论时，不凭空留下持久标记。正文修改导致锚点确实失效时，应明确展示可恢复讨论入口和状态，不能猜测相似文字位置。沿用暖白正文/浅灰外框，保持现有功能和 Kimi 的实现。

已读代码事实：

- `writing/useThreadStore.ts` 的 `close` 仅 `setActiveId(null)`，不删除记录。
- `writing/useNotebook.ts` 的 markers 来源为所有当前章线程，与 activeId 分开；`threadModel.ts` 的 `threadMarkers` 仅返回有效锚点。
- `writing/editorSlots.ts` 用 CM Decoration 渲染编号按钮，activeId 仅控制引文高亮；需要实际检查 reconfigure、DOM 和样式，不能推断关闭一定不会消失。
- `.paragraph-marker` 是绝对定位按钮；需检查滚动/裁切、多标记同一行、面板收起布局变化、最小窗口及真实鼠标点击。
- `usePersistentThreads` / `PersistentThreadRegistry` 最近刚修了正文外部变更与受信任 ChangeDesc 映射的竞态，不能通过绕过 CAS 或相似句搜索来修界面。

举一反三的范围：关闭与重开、选区与讨论状态分离、切章/作品、线程草稿和引用、标记排序与重叠、编辑/undo/redo/回退后的锚点、资料卡/版本/菜单 Escape 分层、焦点和选择范围回归、中文 IME、保存失败时保留稿与操作入口、浮层遮挡。按实际发现修缺陷，避免无依据重设计和无限打磨。

## 工作环境和边界

- 工作副本 `D:\MyAgent\paraselene-work`，分支 `codex/client-mvp-20261012`。工程根目录是 MyAgent 的子目录，请先切到这里，再按 AGENTS 开工必读。
- Windows / PowerShell 7 `pwsh`。不要使用 powershell.exe、Bash、Docker。保留巨大既有 dirty/untracked 树，不 reset，不同步至 `D:\paraselene`。
- 不读取私人 DB、Key、env 或认证文件。模型只用官方 DeepSeek BYOK，真实付费请求须走外发预览和作者明确确认。当前没有为 C 提供真实请求确认。
- 先认领看板和设置任务标题；未知原因用“排查”，根因确认再改为“修复”。按用户最新指示优先交互，之后继续计划，不需要重复询问是否继续。
- 建议用 impeccable / systematic-debugging 及相应验证技能。UI 保留 incumbent 设计，真实操作用合成材料。

## 当前开发状态

A 原生 PARTIAL；B 正式工作区与保存代码已实施、原生验收 PARTIAL；C/D 尚未实施。不要宣称 CLIENT_MVP_PASS。

B 已接入：按章 SQLite 加载/working copy CAS、正文/资料/线程/偏好独立保存、切换和退出屏障、持久保存错误与重试、当前内存稿恢复导出、章节归档/排序/查找、作者确认/回退、资料作者确认与不可变版本出处。预览和正式数据源显式分离；模型按钮在正式界面仍明确不可用。

主要入口：`NativeStudioApp.tsx`、`native/NativeSession.ts`、`NativeLore.ts`、`SaveCoordinator.ts`、`PersistentThreadRegistry.ts`、`usePersistentThreads.ts`、`exportSnapshot.ts`、共享 `writing/NotebookApp.tsx`；Tauri `commands/studio_workspace.rs` 和 `commands/novel.rs`；memory-core 的 novel 工作稿/作者版本/线程/出处事务。

新线程先读 `docs/evidence/CLIENT-MVP-B-20261013.md`、`CLIENT-MVP-B-STORAGE-20261013.md`、`CLIENT-MVP-B-NATIVE-20261013.md` 和 A_NATIVE；部分证据文案未同步以下最新进展，历史结果不能算当前构建验收。

## 最新验证与尚未编译的改动

- Web 测试在最近一次线程映射修正后退出 0；之前 81 项，新增 2 项，合计 83。最终日志计数如需交付可重新验证一次。不要同时运行多个 run-web-tests，它共用临时目录。
- TypeScript 类型检查与代码指标验证在最后 toolbar 移动之后退出 0；TS 指标 7/7 无新增，IPC 检查最近一次无违规。
- memory-core 全量历史 119/119；之后新增“恢复当前确认稿仅丢弃正确 revision 的编辑稿”测试，author_versions 6/6 通过。尚未重跑全量新 120 项，不能把 120 写成已测。
- novel-core 34/34、core Clippy、Rust 指标 36/36 通过；损坏最近作品列表的 Tauri 针对测试 1/1 通过。全仓格式历史欠账未全量通过。
- 最近已编译隔离例子 SHA256 `9D1F313271FDCD84D21817D6DB50CFBED668E461193009FD46027D60136AF809`；嵌入 `index-CYa-Mhep.js` SHA256 `ADAB26D045711373D49972B0BCB1DEFA915C2185E1379F3FF766CFFD3D25A337`。这是开发 example，不是安装产物。
- 上述构建后源码又改变三处，必须重新构建再声明同构建验证：允许显式恢复当前确认稿；ready 线程在正文外部变更/回退时安全失效并通过 ChangeDesc 重映射；把“章节与版本”从固定底部移进 NotebookToolbar，修复覆盖保存失败提示中导出按钮的实际问题。
- Vite 最近构建主包 547.78 kB（gzip 178.10 kB），>500 kB 警告未隐藏。

## 当前原生窗口与未完成验证

唯一测试 DB：`D:\MyAgent\paraselene-work\.client-mvp-tests\native-b.db`。例子 `src-tauri/examples/native_workspace_probe.rs`，标题精确为 `幻月 · B阶段合成验收`。例子显式指定测试 DB，未注册模型/Key IPC。故障注入第二参数 `--fail-body-saves` 仅例子使用，产品命令没有该开关。

真实观察已有：两章不同中文 emoji 正文正常关闭重开恢复；最终已编译例子重开后人物正文/已确认状态和未发讨论草稿恢复；故障注入后新输入保持在内存，切章被取消，Alt+F4 被取消，持续显示保存失败/退出未完成。此前 native evidence 文件未追加最终这些观察，请用新实际验证补充，区分作者转述和独立验证。

上一原生验证子 Agent 在系统保存对话框打开后报告账户 usage limit 并停止。最后用键盘绕过底部按钮遮挡，已打开系统保存对话框，但保存和 UTF-8 读回没有得到结果，不得记 PASS。窗口可能仍开着，包含合成未保存恢复稿；接管时先查看精确目标，完成备份，保留或安全释放这个测试窗口，禁止粗暴终止所有同名或其他窗口。原生工具仅操作这个合成目标，不碰用户其他应用。上一 Agent 不会再操作 UI，也不要循环重启它绕过额度限制。

Computer Use 经 `mcp__node_repl` / `@oai/sky`；不是 CUA（原生能力禁用）。先读 computer-use skill。真实系统 DPI 150%，100/125% 未测。

Rust build 会因运行中合成例子锁住 tauri-build os32 资源而失败，释放目标后再编。构建 PATH 加 `C:\tools\paraselene-build\mingw64\bin;`；运行例子再加 `D:\MyAgent\.cargo-target\debug;` 供 WebView2Loader.dll。Rust target dir `D:\MyAgent\.cargo-target`，offline。沙箱 canonicalize/OUT_DIR 与 Vite 子进程曾需 require_escalated，按实际工具审查处理。

## 修完交互后继续原计划

先补 B 原生出口（尤其失败导出读回、当前版本回退、讨论标记与草稿恢复），冻结同一构建并记录事实，再做最小 C 和 D。用户要求顺序是先修细节，再继续开发；不并行让旧会话修改相同源码或 target。

C 已做只读契约审查，尚无实施：旧 prepare_edit 仅确认稿，缺当前 working revision/body/thread/operation 和引用设定版本；旧 apply patch 不是 working copy + patch 状态单事务；取消未接线，现有 SSE 只有连接超时、缺 total/idle timeout。应复用安全预览一次性许可，绑定真实材料和 revision，候选归属线程，原子 CAS 采纳，取消后不入候选，重复采纳幂等。正式界面不能用示例候选伪装真实模型。代码与合成验证能先完成，真实 Key/发请求确认与安装实测缺失时如实记录，不自行伪造验收。

D 尚无当前安装后的启动/离线/升级恢复证据。交互修正写证据并更新看板；原计划后续推进遇到确实需要用户材料/确认才提问，普通实现选择直接完成。
