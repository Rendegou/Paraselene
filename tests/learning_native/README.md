# Windows learning isolation probe

Run `pwsh -File scripts/check-learning-native.ps1` from the repository root after a Release build. The standalone CMake target compiles the shipping learning-window sources with a test-only friend; the application target never defines that macro. It uses the configured CMake/Flutter wrapper and pinned WebView2 SDK, without starting a Flutter engine.

The probe creates a hidden native window and a fresh synthetic TEMP directory inside `build/learning-native`. It directly initializes the real InPrivate controller, resource firewall and lifecycle; it does not test the Flutter method-channel `open` request path. Existing gateway tests cover that request shape. It neither opens author data nor uses Computer Use. Resources come from the Release asset directory. No model requests or keys are involved.

Checks include English and Chinese Pyodide execution with exact expected numbers, page CSP violations for loopback/file/external-module attempts, an actual native-message delivery observer, a Worker same-origin unknown resource returning an explicit native 403, infinite-loop termination and a subsequent successful run, live Worker closure, cleared storage on reopen, and forbidden navigation closing the sandbox. A deliberate generation fence while a Worker continues requesting makes stale-callback denial deterministic; absence of a local response fails, regardless of eventual connection errors.

The suite found that closing the last InPrivate controller before clearing its profile returns `0x8007139F`. Cleanup now retains the controller until completion or its timeout, navigates to blank to end document workers, and continues returning local 403s to stale/closing resource callbacks.

This is a targeted local native suite, not a full sandbox audit or clean-machine claim. Additional permission/download/popup variants, browser-process crashes, profile-junction attacks, supported runtime versions, Windows quiet/tray/pet, IME/DPI and multiple monitors need separate evidence. Specific notification/blob/popup, profile rename and renderer-crash cases are covered by the extension below. Failed runs and synthetic profiles are retained for diagnosis; the script does not recursively delete them.

本轮新增实际通知权限/同源popup/blob下载拒绝观察、未知profile/错误与硬链接marker拒绝、profile和祖先重命名固定、探针自有renderer崩溃处理。发现并修复FILE_READ_ATTRIBUTES单独使用无法阻止目录重命名，改为同时请求FILE_LIST_DIRECTORY。独立只读复审、正式Release及复制包验证通过；最终日志见docs/evidence/m9-learning-native/isolation-final。更多权限/下载/popup变体、junction替换、browser崩溃、版本和物理系统矩阵仍需单独证据。仅脚本提供的GUID合成TEMP具备隔离保证；不要绕过脚本直接在真实TEMP运行探针。

2026-10-20后续：`-Channel`启动编码原生method-channel专项，整个专有子进程从启动进入非input Windows desktop，从不SwitchDesktop；`-Geolocation`单列严格位置权限专项（隐藏父HWND内激活controller，读回原生GEOLOCATION及DENY）。默认专项另含实际profile/祖先junction、外域/空白popup、第二次data下载的MULTIPLE_AUTOMATIC_DOWNLOADS DENY和专有browser崩溃。正式profile现先固定祖先再mkdir，防止拒绝前仍在junction目标创建目录。所有运行必须通过脚本，显式TEMP参数和合成marker匹配后才开始测试。详见docs/evidence/M9-LEARNING-AUDIT-20261020.md；完整Flutter引擎链路、版本和其他系统矩阵仍未完成。
