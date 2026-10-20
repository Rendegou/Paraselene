# M4 原生存储与真实关窗复验（2026-10-18）

状态：存储审查阻断项已修正并复验；真实系统导出取消后绕过关窗屏障的缺陷已复现、修正、同路径复验。M4 整体验收仍按下列实际覆盖与限制判断，不代表 M3 生产化、M2-W 或 M5–M9 完成。未提交 commit。

本轮 SDK 命令均已结束，无保留的交互探针窗口；SDK 槽位已释放。Windows 集成测试完成后仅将测试标题改成准确的 head-only confirmation（旧日志标题含 rollback，实际上未执行回退），未改变行为。

## 存储修正

- `test-support` 显式隔离 arbitrary-root crate API、测试 helper 与发布故障点；默认生产 bridge 仍只打开固定 owned root。helper 是 feature-gated Cargo bin，未增加 FRB 任意路径入口。旧 target 缓存内的历史 helper 未删除；不能据此声称所有历史目录无 helper。
- 最终 DPAPI 包发布前、读取时共享 128 MiB 上限，计入加密开销。小限额测试验证恰好边界成功、超限拒绝、旧 snapshot 不变、已变更会话毒化。
- pending 必须通过 DPAPI/版本/目的/根绑定与 SQLite integrity 检查后才能删除；删除使用同一独占 DELETE 句柄。未知、损坏、空 pending 保留并拒绝打开。
- 自己新建的 staging 使用 delete-on-close，完整写入并 flush 后才清除 ON_CLOSE 删除标记；强杀半写阶段由内核删自己的文件，完整 pending 可认证恢复。普通 FileDispositionInfo(false) 不能清除此创建标记，修正为 FileDispositionInfoEx。
- SQLite backup 序列化副本将 WAL header 的读写版本改为独立 image 的 1/1；正文不做换行或 Unicode 规范化。跨进程 dump 输出 JSON 正文并重算 BLAKE3，与独立预期比较，包括 CRLF、组合/分解音符、emoji、空稿、确认版本、确认后 rebased 草稿。
- 新 owned 入口覆盖 hardlink、payload/pending/lock 的 reparse、根与祖先 symlink 拒绝；本机均实际执行，无权限跳过为零。

## Dart 测试隔离

`NativeRuntime` 在 FRB 初始化与开会话之前调用无副作用 C ABI scope。scope 来自 application 的实际 feature，避免 Cargo mixed-feature 构建让 bridge 自报生产而 application 实际打开测试根。缓存初始化后也校验期望身份。

生产 scope=1；独立测试 DLL scope=2，要求显式 diagnostic override 与严格 32 位小写十六进制 runId。测试基目录固定 `build/m4-owned-test-v1`；fixture 排他创建自己的 run 与 sentinel，拒绝已有目录、reparse、未知文件，非递归按 allowlist 清理自己的文件。两份测试不再递归删除生产 ownedstore。真实 GUI 试验遗留的本轮独立 run 目录保留，没有按前缀扫删。

scope probe 只校验身份，不打开会话。缺 runId、生产误载 test DLL、匹配 DLL、缓存身份反转均有独立 PASS 日志。

## 真实 Windows 关窗发现与修正

默认独立 native probe 使用内存 synthetic repository，故意让 save 失败。生产 main 未选择这个入口。Computer Use 通过用户已授权的本次 exe 操作系统 X、Alt+F4 和真实 file_selector SaveAs。

修正前：正文 `a` → 系统 X → 保存失败恢复提示 → Export draft → 系统 SaveAs → Escape → Alt+F4，窗口直接消失。不是 framework 模拟信号推断。Flutter 官方 issue [168335](https://github.com/flutter/flutter/issues/168335) 亦记录 modal file dialog 后关闭监听绕过现象；本地复现是本次修正依据。

runner 现在在 engine/plugin 处理前拦截 WM_CLOSE，异步调用同一 Dart 关闭屏障。native pending 与 Dart exitFlight 合并重复请求；仅 Dart 明确返回 true 后投递内部消息，在 engine callback 之外销毁窗口。异常/未实现/取消保持窗口。启动时必须完成 guard enable 握手才打开默认 repository。

修正后同路径结果：

1. 系统 X 触发保存失败提示，保留正文。
2. 取消真实 SaveAs 后，Alt+F4 再次显示一个恢复对话框；重复 Alt+F4 仍只有一个对话框，窗口保留。证据 `checks/m4-native-close-guard-after-cancel.png`。
3. 真实 SaveAs 导出到本轮新建 `build/m4-native-export-20261018-guard/recovery.txt`，成功提示有实际路径。读回 47 字节，正文完全为 `# M4 native synthetic\n\n## Recovery chapter\n\na\n\n`。SHA256 `FFECC701EBA231F8A5C9CABC1B7F122CA95CD5E112C2250DEFFEA449E5ECD58A`。字节与截图保存在 `m4-native-export-bytes.json` / `m4-native-export-success.png`。
4. 导出成功后出现单独的明确退出决策，选择 Exit anyway 后窗口消失。没有将系统对话框取消记作成功。
5. `--real` 探针使用实际 Rust test DLL 与新 sentinel run。键入并提交 `a`，显示 All changes saved，系统 X 正常退出。独立 helper 重开同一合成库，读回 body="a"、revision=3，存储 hash 与重算 BLAKE3 均为 `17762fddd969a453925d65717ac3eea21320b66b54342fde15128d6caf21215f`。见 `m4-native-real-after-close-dump.txt`。

真实库探针最初三次用 Start-Process Hidden 启动，首个 ShowWindow 被启动参数隐藏，曾误认为停在首帧前；阶段日志证明已完成初始化与 runApp。停止这些已知无窗口测试进程，保留各自测试库；使用可见交互模式后成功。未把这三次启动记成关窗 PASS。

## 命令与结果

路径均相对 repository；日志在 `docs/evidence/m4/checks`。SDK 顺序执行，Rust 固定 MSVC / locked / offline。

| 检查 | 实际结果 / 日志 |
|---|---|
| `cargo +stable-x86_64-pc-windows-msvc test --manifest-path rust/Cargo.toml -p paraselene-application -p paraselene-memory-core -p paraselene-novel-core --features paraselene-application/test-support --target-dir build/rust-m4-test-msvc --locked --offline` | exit 0；220 passed、0 ignored；`m4-native-followup-rust-final.txt` |
| 四个强杀发布边界 | during-staging / after-flush / before-replace / after-replace 均必须先到达 marker 才杀，完整旧态或新态；8 owned tests PASS；`m4-native-followup-boundaries.txt` |
| 默认与 test-support clippy `--all-targets --no-deps -- -D warnings`；app/bridge fmt check | exit 0；`m4-native-followup-clippy.txt`、`m4-native-followup-final-clippy.txt` |
| 默认显式构建 helper | 预期 exit 101，要求 test-support；`m4-native-followup-helper-gate.txt` |
| test DLL 与 mixed-feature build | exit 0；`m4-native-followup-test-bridge.txt`、`m4-native-followup-mixed-build.txt`；scope probes 另存 `m4-native-followup-scope-*.txt` |
| `flutter test test/m4_owned_repository_test.dart` | 2 PASS，独立 run 清理自身；`m4-native-followup-owned-ffi.txt` |
| `flutter test integration_test/m4_app_test.dart -d windows`，新 test DLL runId | exit 0，2 PASS，目录/编辑/空稿/重命名/归档恢复/确认/冷恢复；`m4-native-followup-windows-integration.txt`。适配已有 EditorViewport 输入连接与正文断言，未修改编辑器实现；单 head 场景只检查无回退按钮，未执行真实 UI rollback |
| 当前工作树全部非 golden 普通测试（排除 owned 专用测试） | exit 0，420 PASS；`m4-native-followup-dart-final.txt` |
| native channel 与 framework 并发关窗、保存失败、取消/失败/成功导出生命周期 | exit 0，8 PASS；`m4-native-close-guard-widget-final.txt`。widget mock 只证明 Dart 决策，不代表真实 WM_CLOSE |
| `flutter analyze --fatal-infos` | exit 0，无问题；`m4-native-close-guard-analyze.txt` |
| probe debug / 正式 main release 构建 | exit 0；`m4-native-close-guard-build.txt`、`m4-native-real-probe-build.txt`、`m4-native-followup-final-release.txt` |
| `scripts/verify-m1-bundle.ps1` 独立复制正式包、移除 SDK PATH | PASS；合成诊断 exit 0、缺 DLL exit 1；`m4-native-followup-bundle.txt` 与同名目录的 report/manifest |

失败记录不覆盖：早期 Rust boundary fixture 使用非法 UI JSON 失败，后改为真实合法 schema 后复跑通过；旧 Dart 回归 414 PASS/4 FAIL 为过期开发 DLL 缺 scope symbol，生产新 DLL 复跑相关 7 项通过，再跑全部普通测试 420 PASS。工作区 sandbox 原生句柄权限造成 invalid_synthetic_root；实际原生测试在自动批准的所需权限下执行。没有以这些失败日志冒充最终成功。

收尾时一次 analyze 误在 repository 根目录执行，扫描 `build` 中历史 M3 实验副本并报 435 issues（exit 1，`m4-native-followup-final-analyze.txt`）；不改这些历史副本，改在 `apps/desktop` 正确包目录执行，结果另存 `m4-native-followup-desktop-final-analyze.txt`。

环境与构建 SHA256 分别记录在 `m4-native-followup-environment.json`、`m4-native-followup-sdk.txt`、`m4-native-followup-artifacts.json`。Flutter 3.32.1 / Dart 3.8.1；Windows 注册表报告 DisplayVersion=25H2、build=26200.9711（旧 ProductName 文本仍为 Windows 10 Home，不据此猜测实际发行标识）。`git diff --check` exit 0。

## 复审、边界与未验项目

requesting-code-review 要求的只读独立复审发现一项 mixed-feature scope P2，已经修正；再次检查原生 guard、生命周期与 scope 无新增 actionable findings。审查未运行测试，行为证据由本报告所列执行提供。

- 不宣称硬件断电安全，只覆盖进程强杀和 Windows 文件句柄语义。
- 本轮没有运行/rebaseline golden，保留原有 8 张失败图片；当前 M3 接线不因此成为生产化验收通过。
- 系统文件写入失败与导出成功后 Keep editing 的真实 GUI 组合尚未逐项复验；对应 Dart gateway/文件测试通过不能替代真实 GUI。
- 真实 IME 全矩阵、长文性能仍未验收。观察到组合与字符不等于完整 IME 合格。
- M2-W 仍 PLANNED，M5–M9 NOT_RUN。未读取作者库/正文、密钥或环境认证文件，未发送真实模型请求；原工程未操作。core 目录本次无 git diff。

## 2026-10-18 接续原生组合验收

本会话新证据（未改变生产存储/关闭逻辑）：
- 系统 SaveAs 选择本轮独立 locked.txt，另一已知测试进程以 FileShare.Read 持有读句柄。确认写入后应用显示 Export failed，窗口保留，无 Exit anyway；原文件仍为 synthetic-locked-sentinel。证据 m4-system-write-failed.png。
- 再次通过系统 X → Export draft → 新 keep-editing.txt，独立读回 49 字节，正文为 aaa，SHA256 AD6D2862C6A9F5426270A0E04CFEC618DE16B2DF2C871BDE09437EFD2A13975A。关闭成功提示后选择 Keep editing，物理按键 b 后正文变为 aaab，窗口继续存活。type_text 的 K 未进入当前 M3 编辑器，不把该次输入算通过；此处不证明 M3/IME 完整性。两张 keep-editing-resumed 截图中 final 才包含 b。
- 原生探针增加 --versions，仅 standalone 入口预置两次确认及未确认合成稿。实际 Rust test DLL 新 run，经真实版本列表展开旧版、警示、确认回退。系统 X 正常退出，独立 helper dump 确认正文精确为 version-one\r\né é 👩‍💻，head 指向旧版本，版本数仍为2，BLAKE3 e04bff7456d163fa9f1ef7b70a8eeb22c6dff3ac24d00994655e14660c47bb55。见 m4-ui-rollback.png / m4-ui-rollback-cold-dump.txt。
- 另一新实际 Rust run e4f508701c5049b8a3ca2e425172dfb5，在初始化完成后对其 snapshot.dpapi 持有 FileShare.Read 读句柄，制造 Windows 共享冲突。编辑后系统 X 出现 durable_save_failed 恢复提示，实际 FFI、非 Dart 替身。释放读句柄后仍按毒化会话规则导出内存稿，不虚称修复后可继续持久保存。系统导出 real-ffi.txt 49 字节，内容/哈希见 m4-real-ffi-export-readback.json；成功 UI 截图 m4-real-ffi-export-success.png。该实验是共享冲突，非硬件故障。

全部 run/导出目录保留；无扫描前缀清理。构建初次受限 SDK 无输出，所需权限重试后被本会话误启动的无窗口旧 Debug EXE 文件锁阻塞（LNK1168）；精确核对并终止该 PID 后构建成功，失败日志保留。内存故障探针在导出与继续编辑取证后以精确 PID 结束，不能把该 teardown 称正常退出 PASS。

M4 完整出口尚受当前 M3 接线的 golden 与完整输入/组合验收限制；不覆盖前报告的限制，不标全矩阵完成。继续推进 M2-W 独立探针，保留系统标题栏回退路线。

补充：实际 Rust 故障 run 在导出读回后，经成功提示的明确 Exit anyway 正常退出。独立 helper 重开为故障前的空正文，证据 m4-real-ffi-failure-cold-dump.txt；这与失败提交未持久化、内存稿由恢复导出保存的合同一致。上述系统写入失败、导出后继续编辑、历史版本 UI 回退的旧 NOT_RUN 项已由本节新证据覆盖，完整 IME 与 golden 状态不提升。
