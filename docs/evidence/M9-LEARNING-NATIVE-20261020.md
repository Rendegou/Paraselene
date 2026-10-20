# M9 学习窗口原生执行与关闭修复（2026-10-20）

状态：本机专项原生矩阵PASS，完整学习隔离审计仍PARTIAL；M5–M9不整体提升为完成。

## 本次变更

新增独立 `tests/learning_native` CMake探针及 `scripts/check-learning-native.ps1`。它编译正式LearningWindow/Profile/Security代码，使用隐藏HWND、当前WebView2运行时及项目内全新合成TEMP；不启动Flutter引擎、不使用Computer Use、不打开作者库或凭据。仅测试目标定义friend宏，正式runner不定义，不增加应用可调用的测试接口。

真实运行发现正式Close先释放最后的InPrivate controller，再调用ClearBrowsingDataAll，会返回 `0x8007139F`，随后cleanup_failed阻止重开。修正为保留controller到清理完成/失败/15秒超时后的统一Shutdown；开始清理时导航空白页结束旧页面和Worker。复审指出代次改变后不能跳过资源拦截，现存活实例的旧代次或清理中请求明确收到本地403，空白页只在清理阶段获准导航。

## 真实断言

- 英文和中文固定页面通过正式资源白名单载入，实际InPrivate设置为true，原生窗口没有显示；运行时 `155.0.4283.62`。
- 真正Pyodide Worker执行 `double(2/0/-3)`，分别得到4/0/-6；无限循环30秒后被页面终止，之后新Worker仍可成功执行。
- 页面未知资源返回403；loopback、file及外部module请求被拒绝，并收到对应CSP violation，避免把不存在的地址/文件当作隔离证明。目标只含合成路径、回环和保留的invalid域名。
- 原生设置确认host objects和web messaging禁用；页面尝试postMessage后真实WebMessageReceived观察器计数为0。方法属性存在与否不作为判据。
- Python通过js.fetch请求同源 `/worker-denied`，既断言response.status为403，也由原生事件读到相同请求的本地403响应。
- Worker持续请求时先建立活跃请求证据，再显式推进代次，确定性观察至少3个旧回调仍返回本地403；之后关闭并确认controller/webview/HWND释放。重开后localStorage合成标记为空。
- 禁止导航触发本地拒绝并关闭沙箱，清理成功，预期的单次fault通知可见；不要求受攻击页面继续保留。

## 证据与产物

- `m9-learning-native/final/build.txt`：独立C++17目标 `/W4 /WX` 编译PASS。
- `m9-learning-native/final/stdout.txt`、`stderr.txt`、`result.json`：最终suite退出0；`inputs-sha256.json`记录正式源、探针和固定资源。
- `m5/windows-release-learning-final.txt`：最终正式Windows Release PASS（13.7秒增量构建）。
- `m9-learning-native/bundle.txt`及`bundle/copied-bundle-manifest.json`：最终独立包PASS，`build/m1-distribution-539908b16847424699f0bfe82145b672`；移除SDK PATH退出0，缺复制DLL退出1。
- 首轮路径引号、错误消息判据、清理故障及中间诊断均保留在同目录的历史子目录；没有删除断言或改golden。弱引用/代次/profile pins和Worker明确403两个探针审查问题已修订；关闭期防火墙问题已修订，末次只读复审无新增确定缺陷。

本次仅原生C++实现变化，未重复此前已通过的482项普通Flutter/生产DLL全量；后补真实工作台UI2项、专用加密库2项和最终Dart无问题分析见 `M6-SOURCE-MARKS-20261019.md`。

## 仍未验证

探针直接初始化真实controller，未把此次结果冒称Flutter方法通道open的原生端到端验收。权限/下载/popup变体、进程崩溃注入、profile目录攻击、不同运行时版本及完整隔离审计仍未完成；桌宠/托盘/quiet、IME/DPI/多屏、净机安装、作者数据接管、真实模型/发布均未执行。既有“学习Python执行全部NOT_RUN”已由本次专项结果部分替代，不据此宣称全产品替代完成。

## 2026-10-20 隔离矩阵扩展与目录固定缺陷

本批仅使用脚本创建的GUID合成TEMP及隐藏原生窗口，未恢复Computer Use。新增实际NewWindowRequested、PermissionRequested和DownloadStarting观察器：正式处理器先运行，观察器仅读取Handled、DENY和Cancel；同源window.open、Notification请求及合成blob下载均到达原生处理器，页面权限结果亦为denied。仅覆盖这些具体变体，不代表所有权限/popup/下载形态。

合成profile覆盖未知既有目录拒绝且保留、错误marker拒绝、硬链接marker拒绝，以及目录固定。真实测试发现原先只有FILE_READ_ATTRIBUTES的句柄并不能阻止MoveFileEx重命名：profile-path-diagnostic/stdout.txt中9个句柄存活时moved=1。正式learning_profile.cpp增加FILE_LIST_DIRECTORY，使省略FILE_SHARE_DELETE真正生效；profile-fixed中变为moved=0/error=32，关闭释放后同目录可移动。最终探针还核验祖先目录重命名被拒。未因此宣称junction构造/所有路径替换攻击已验证。

新增Page.crash仅针对探针持有的renderer，不枚举或终止其他进程；观察真实RENDER_PROCESS_EXITED后要求正式故障处理释放窗口/controller/webview并清理成功。前轮crash-final已观察到崩溃及成功清理，但探针沿用了前次导航的fault累计值、错误断言总数为1，导致退出1；最终改为记录注入前计数并要求恰好新增一次。历史失败日志全部保留。

正式Release：windows-release-profile.txt PASS；独立包bundle-profile/copied-bundle-status.json PASS，build/m1-distribution-952d79ba895f471e84c1a95a6b956fef，去除SDK PATH退出0、缺DLL退出1。FILE_LIST_DIRECTORY修复经独立只读复审无新增确定缺陷；复审建议不要夸大祖先攻击证据，随后新增了祖先重命名断言。本批未重复Dart/Rust全量，正式C++ /W4 /WX编译由独立探针和Release覆盖。

最终专项PASS：m9-learning-native/isolation-final/result.json退出0，stdout.txt记录全部断言通过，stderr.txt为空；inputs-sha256.json固定本轮正式源/探针/资源。完整隔离审计仍PARTIAL：junction/目录替换的更多构造、更多权限/弹窗/下载变体、browser进程崩溃、版本矩阵及Flutter方法通道真实open端到端尚无本批证据；桌宠/托盘/quiet、IME/DPI/多屏、净机安装仍未完成。真实模型、作者库、凭据、发布均未操作。

## 2026-10-20 后续专项替代状态

profile/祖先junction、更多popup与自动下载权限、地理位置DENY、browser崩溃与失败后禁止重开、原生编码方法通道Open现已有本机真实专项通过。另发现并修复祖先junction校验晚于目录创建，目标不再接收新profile目录。当前详情与最终日志见`M9-LEARNING-AUDIT-20261020.md`；上述较早“browser/junction未验证”已由具体专项部分替代。原生编码通道不含Flutter引擎，版本与完整攻击/物理系统矩阵仍未完成。
