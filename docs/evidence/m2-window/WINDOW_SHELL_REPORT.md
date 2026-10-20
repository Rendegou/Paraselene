# M2-W 自定义窗口外壳：实施与验收记录

日期：2026-10-18。状态：**IN_PROGRESS，默认保留系统标题栏**。迁移计划 §13 的强制出口尚未全部通过，不标 COMPLETE。

## 实现范围

- `lib/window/` 的可注入窗口服务封装最小化、最大化/还原、拖动、窗口状态与关闭请求。Widget 不直接调用插件；关闭仅调用 `windowManager.close()`，不使用 `destroy()`、第二个 close listener 或 `setPreventClose()`。
- 现有 runner 守卫在 Flutter/plugin 处理前截获 WM_CLOSE；自定义关闭、Alt+F4 与系统菜单共用 WorkbenchApp 的保存/恢复导出决策。恢复导出成功仍需明确选择退出。
- 标题栏独立一行，不替换原工作台命令。标题按可用宽度截断并提供完整 Tooltip/语义；按钮中英本地化、44px 以上目标、键盘焦点、焦点语义、悬停/按压状态。
- 窗口初始化并发共享；隐藏失败后恢复系统边框。释放时恢复边框，隐藏调用晚返回不再刷新或遗留无框窗口。
- 正式入口仅 `--window-shell` 开启，`--system-title-bar` 强制回退，默认系统标题栏。独立 `integration_test/m4_native_probe.dart --window-shell` 使用明示的合成内存故障仓库；`--real` 仍只连接专用隔离测试 DLL/run。
- 未修改 Rust 数据权威，未提升 M3 生产编辑器状态，未更新 golden。

## 依赖与消息顺序

锁定 window_manager 0.5.2（MIT，维护者最低 Dart 3.0/Flutter 3.3，本机 Flutter 3.32.1/Dart 3.8.1）。新增传递依赖为 screen_retriever 0.2.2、其 linux/macos/windows/platform_interface 0.2.2，以及 json_annotation 4.9.0；精确版本与哈希见 pubspec.lock。screen_retriever 的本地许可证为 MIT。

查阅 Context7 的 leanflutter/window_manager 初始化/隐藏标题栏/窗口事件文档，以及 Flutter Overlay/导航 API；同时核对当前 SDK 和锁定插件的源码。维护者页面：[window_manager](https://pub.dev/packages/window_manager)、[README](https://github.com/leanflutter/window_manager/blob/main/README.md)、[Flutter Overlay](https://api.flutter.dev/flutter/widgets/Overlay-class.html)。文档存在不代表原生矩阵通过。

插件 Windows Close() 向主 HWND 发送 WM_SYSCOMMAND/SC_CLOSE；随后的 WM_CLOSE 被既有 NativeCloseGuard 在 plugin 处理前消费。插件 Destroy() 直接 PostQuitMessage，因此本实现禁止使用。隐藏标题栏沿用插件的 Windows 边框实现，不声称已支持 HTMAXBUTTON/Snap 悬停。

正式独立包清单已包含 window_manager_plugin.dll 与 screen_retriever_windows_plugin.dll，见 production-bundle/copied-bundle-manifest.json。

## 原生发现与修正

1. 首次探针出现 No Overlay widget found：MaterialApp.builder 中的标题栏在 Navigator 外，Tooltip 缺少 Overlay。加入 Overlay.wrap，并增加完整工作台 Tooltip 回归。失败截图 overlay-integration-failure.png 保留。
2. 独立审查指出隐藏平台调用在释放后返回可能遗留隐藏边框：增加共享恢复 Future 与释放检查，测试覆盖 pending minimum-size、pending hide、availability 后调度释放。
3. 独立审查指出 ExcludeSemantics 掩盖 IconButton 焦点：保留按钮语义、仅排除图标/重复 Tooltip 文本，以 MergeSemantics 合成一个有标签、动作和焦点状态的节点。
4. 完整工作台 UIA 树仍缺少 caption 控件；新增工作台级断言复现。SDK 源码确认 ModalBarrier 的 BlockSemantics 屏蔽同容器中先绘制的兄弟节点。将 Navigator 放进独立 Semantics(container:true)，标题栏语义恢复；单组件测试不能替代此接线测试。

审查：requesting-code-review 技能要求的只读子代理审查，未运行 SDK；两项 P2 已修正。同步在 ChangeNotifier 通知回调内 dispose 的无效测试已改为调度释放。生产行为证据来自本记录中的实际执行。

## 已执行的行为证据

| 检查 | 结果/证据 |
|---|---|
| 标题栏初次显示 | PASS，titlebar-native.png，原工作台工具栏仍可见 |
| 自定义最大化、图标变还原 | PASS，maximized.png |
| 空白标题区双击还原 | PASS，实际窗口回到原尺寸 |
| 自定义最小化/恢复 | PASS，点击最小化后重新 activate 窗口，合成工作台仍在；不等同会话持久化验收 |
| Alt+Space 系统菜单 | PASS，system-menu.png |
| 组合输入中自定义关闭 | 本次按键序列 PASS：物理 a 的候选窗存在时点击关闭，进入保存失败恢复 UI，窗口保留；custom-close-save-failed.png |
| 重复 Alt+F4 | PASS，既有恢复决策仍仅一份，repeated-close-single-dialog.png |
| 系统 SaveAs/导出读回/明确退出 | PASS，composition-export-readback.json、composition-export-success.png、explicit-exit.png；导出47字节，正文恰为一个 a；明确 Exit anyway 后 PID47276 结束 |
| 独立复制 Release 合成探针 | 已启动并正常 Alt+F4 关闭，release-copied-titlebar.png；最终语义修正后的探针单列补证 |

上述组合仅来自合成材料，不据此声称完整 IME、真实持久存储故障或全部入口组合通过。M4 的实际 Rust 存储故障、系统写入失败、导出后继续编辑、旧版本 UI 回退等另见 ../m4/NATIVE_FOLLOWUP_REPORT.md。

## 检查与失败保留

- 定向窗口+生命周期回归：23 PASS，window-final-regression.txt。完整工作台语义断言后：10个标题栏测试 PASS，workbench-semantics-isolated.txt。
- 普通 Dart 回归：435 PASS，ordinary-dart-final.txt。排除 m2_golden_test.dart 与 m4_owned_repository_test.dart；后者为专用 owned FFI 验证，不能把普通回归当其重跑。
- 普通回归首轮430 PASS/5 FAIL，均因未指定开发测试 DLL（bridge_dll_missing），ordinary-dart-tests.txt；第二轮显式使用已验证生产 Release DLL 路径后435通过。不覆盖失败日志。
- analyze-verified.txt：无问题。production-release-build.txt：正式入口 Release 构建退出0。production-bundle-check.txt：独立复制、移除 SDK PATH，11项合成诊断退出0，缺桥接 DLL 退出1。
- 早期测试中的多余 SemanticsHandle 未及时释放，改为使用框架默认语义生命周期。早期编译/语义失败日志均保留。
- debug 探针 stderr 有 empty JSON 解析提示及退出时 Vsync 提示，来源尚未定位；不能把空 stderr 当通过条件。独立 Release 探针 stderr 单列保存。

## 未通过或未运行的强制出口

- 空白区拖动：自动化 drag 未观察到位移（两次截图原点均21,15），目前为 **UNRESOLVED**。不把 API 调用完成算通过；需分离输入注入时序与实际拖动行为。
- 八向缩放、贴边、Snap Layout 悬停、100/125/150/200% 物理 DPI、多屏、实际 Windows 高对比度：**NOT_RUN**。Widget 高对比度/字号/RTL 模拟不代替系统实测。
- Win+方向键：**NOT_RUN**，Computer Use 技能禁止发送 Windows 键快捷键，需人工验收；未绕过该限制。
- 完整输入/组合策略、切章切作品/宽稿专注全矩阵、启动中关闭全原生矩阵：**NOT_RUN**。当前 M3 接线及其原有8张 golden 失败图保留。
- 辅助技术原生树在语义隔离后的复验，以及自定义 caption 键盘全程遍历：最终探针继续补证；widget焦点语义通过不等于屏幕阅读器通过。

默认系统标题栏是当前交付路线。强制出口通过前保持 M2-W IN_PROGRESS；M5及后续模块不由本报告提升。

## 最终补证

- 最终隔离语义后的 Release 探针目录见 synthetic-final-bundle-root.txt，完整文件哈希见 synthetic-final-bundle-manifest.json。移除 SDK PATH 后可见启动，原生 UIA 明确列出 Minimize / Maximize / Close window（final-native-uia.txt、final-release-titlebar.png）。该证据覆盖此前“原生树待复验”，不代表屏幕阅读器全流程验收。
- 最终探针 PID47928 通过 Alt+Space → 系统菜单关闭正常结束，无未保存稿件；release-final-probe-stderr.txt 为空。前一个复制 Release 探针 PID33896 也正常 Alt+F4 结束。
- 原生 Tab/反向 Tab 的本次注入未证明从内容进入 caption 的完整遍历，仍保留 NOT_RUN；不据此覆盖 Widget 的焦点状态断言。
- 最终探针对右侧边缘的一次 drag 也未观察到宽度变化（1272×716不变），该边标记 UNRESOLVED，其余七向仍 NOT_RUN。不能把此限制统称为全部八向已测失败，也不能推断为已确认插件缺陷。
- 正式 main 最终恢复构建：production-release-final-build.txt，exit0。最新独立正式包验证：production-final-bundle-check.txt / production-final-bundle/，11项合成诊断exit0、缺DLLexit1、SDK PATH已移除；两个新增插件 DLL 随包分发。
- 只读独立复审对语义容器隔离与 Overlay 无新增 actionable finding，确认模态对话框仍屏蔽工作台底层内容，caption 保持可达；不代替原生验收。
- 最终源码上的普通回归仍为435 PASS：ordinary-dart-verified.txt；analyze-complete.txt 无问题。format 7文件0变化，git diff --check 退出0。
- 环境与代码基线：HEAD cb2271778163a0fb98d1ebf4737ade0a0790b619 + 未提交工作树；OS注册表 25H2/build26200.9711（历史ProductName字符串不用于判断发行名）。未采集物理DPI，不猜测；精确源码哈希见 source-manifest.json。原工程只读，本次未操作；core目录无git diff，未访问作者库/密钥/认证，未发模型请求。
- 最后一次 diff 检查为 diff-check-final.txt，按仓库既有换行配置 exit0。中途为了屏蔽换行提示临时使用 `-c core.autocrlf=false`，使 CRLF 被当作尾随空白而退出2；该尝试保留在 diff-check.txt。未改全局/仓库配置，未批量转换文件。

接续命令（只使用已复制合成探针，不打开正式作者库）：读取 synthetic-final-bundle-root.txt 中的目录，以该目录下 paraselene_flutter.exe 的 `--window-shell` 参数启动。要复验实际 Rust 库，仅按既有 OwnedStoreFixture 的预检与独占 run 协议使用 `--real`，不得用固定 ownedstore。当前所有已记录探针 PID 均已结束，合成导出与运行目录保留。

## 2026-10-18 拖动复核与键盘焦点修复

本节覆盖上文相应待查项；历史失败证据保留。

- 用户实际操作确认“标题区拖动、右边框缩放两项都能正常操作”。同一 Release 合成探针 PID19168、DPR1.5 的 drag-trace-stdout.txt 记录了原生 move/resize 事件。两项改为人工 PASS；其余边角、DPI/多屏/Snap 等矩阵仍 NOT_RUN。
- 自动化 drag 已到达 startDragging，但移动注入集中在原生模态拖动启动前，调用约20ms结束且未移动。结合人工通过，支持注入时序限制；没有据此改动生产拖动实现。首版 Release Offset/Rect 日志没有数值，后续探针源码改为标量并过滤 hover；尚未重建验证该日志改进。
- 新增全工作台 Tab 测试稳定复现 caption 不可达，失败焦点树保留 keyboard-traversal-before.txt。根因是 WidgetsApp 外层 Navigator Scope 默认 closedLoop，标题栏在该 scope 之外。仅自定义外壳首帧后通过公开 NavigatorState.focusNode.enclosingScope 设置 parentScope；dialog 后代 scope 保持闭环。固定 navigatorKey 生命周期内有效；未来动态更换 Navigator/外壳时需重新同步。
- 正向与反向 Tab 到达三个 caption、Enter 关闭、真实 showDialog 双向 Tab 不逃出，以及原有窗口/关闭生命周期，共26测试 PASS：keyboard-window-lifecycle-final.txt。误写测试路径的首轮失败保留 keyboard-window-lifecycle.txt，不能当成功。
- 独立 review_window_shell 审查支持当前公开API与首帧接入方案，要求双向遍历及模态隔离测试，现已覆盖。此前435普通回归和正式包验证是历史结果，未宣称本次完整重跑。
- 用户物理 Esc 停止 Computer Use，已停止桌面操作。PID19168 未由代理关闭；当前 Release 输出是合成 trace 探针，并非最新焦点修复后的正式 main。最新原生键盘验证、正式 Release 重建/独立包验证待续；M2-W 仍 IN_PROGRESS，默认系统标题栏。
- 最新 flutter analyze 退出0、No issues found：keyboard-analyze.txt（49.5秒）。git diff --check 退出0。最终只读进程检查确认 PID19168 仍运行。

## 2026-10-18 原生键盘与正式包复验

- 新复制 Release 合成探针 PID24116 运行最新焦点修复，目录见 keyboard-native-process.json。旧 PID19168 已经 Alt+F4 正常退出并在重建前确认结束。
- 从合成正文点击建立焦点后，Tab 可到标题栏；稳定 UIA 明确观察 Minimize/Maximize（native-tab-maximize-uia.txt）。前台切换造成自动化反向路径取证不充分；用户随后明确确认“正反向遍历都正常”，因此三个 caption 的基本双向遍历记为人工 PASS。不扩大为全部快捷键或屏幕阅读器通过。
- keyboard-native-probe-build.txt、keyboard-production-build.txt 均退出0。keyboard-production-bundle-check.txt：最新焦点修复 main 独立复制包移除 SDK PATH，合成11项退出0、缺DLL退出1。目录 build/m1-distribution-a028eecd690c4c5e95b0abf2d7158a12。
- 字体后续修复与检查见 ../m3/EDITOR_FONT_FOLLOWUP.md。在此之后须以该报告的最新正式产物为准。
- 用户再次物理 Esc 停止 Computer Use，未再执行任何桌面操作；PID24116 最后只读检查仍运行，未强杀。默认系统框与 M2-W 剩余八向/DPI/多屏/Snap 门槛保持。
