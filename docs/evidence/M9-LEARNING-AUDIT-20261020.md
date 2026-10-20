# M9 学习隔离补充审计（2026-10-20）

状态：本机定向验收继续补齐，完整产品及运行时版本矩阵仍PARTIAL。仅合成数据，无Computer Use、作者库、Key、真实模型或发布。

## 发现与修复

真实junction fixture确认正式PrepareProfile先CreateDirectory再检查祖先，虽拒绝启动，却在junction目标创建固定名空目录。修前失败日志：`m9-learning-native/junction-write-before`。修复为先校验并固定TEMP全部祖先，再创建profile并校验/固定profile；保留盘根与不支持路径的拒绝规则。回归要求拒绝profile/祖先junction、哨兵字节不变，并明确断言祖先junction目标没有新profile目录。未扫描或递归清理任何目录。

## 原生隔离专项

- profile及祖先junction实际构造并观察拒绝；未知目录、错误/硬链接marker、profile与祖先重命名、释放句柄后可移动保留原断言。
- 同源、外域及about:blank的NewWindowRequested均由正式处理器设置Handled；外域popup在导航前阻止。
- 通知请求观察原生DENY；blob下载观察DownloadStarting.Cancel。第二次data下载实际经过MULTIPLE_AUTOMATIC_DOWNLOADS权限门，要求该请求已DENY且没有第二次DownloadStarting；不把未触发下载事件当作取消证明。
- 地理位置单列`-Geolocation`专项：controller保持FALSE时API等待可见文档，首轮超时日志保留；父HWND仍隐藏，只激活内部controller后文档visible。严格要求原生GEOLOCATION种类、DENY状态、恰好一个请求及页面code1，避免操作系统拒绝造成假通过。未允许真实定位。
- Page.crash与Browser.crash均通过持有的专用WebView实例注入；新GUID profile与ExclusiveUserDataFolderAccess确保不共用作者浏览器profile。不枚举或按名称关闭任何进程。renderer崩溃清理成功；browser崩溃导致清理失败时，窗口/COM仍释放，报告清理错误并阻止正式Open重开，不将清理失败描述为清理PASS。

## 原生编码方法通道

新增`learning_channel_probe`目标，以StandardMethodCodec编码请求，进入正式LearningWindow注册的原生handler，再解码真实返回envelope。校验错误方法/参数/locale/空或过长及非法UTF-8标题、忙碌拒绝、WM_CLOSE取消、迟到创建不复活；中英正式Open分别成功、选定固定页面、真实Pyodide得到4/0/-6、重复Open复用窗口、WM_CLOSE后清理成功。

探针创建独立非输入Windows desktop，并在CreateProcess时指定该desktop。没有SwitchDesktop调用；启动和成功显示窗口后均核验其与用户input desktop不同。仅切换线程desktop的早期方案会使controller创建返回0x80070057；修正为整个专有子进程从启动进入该desktop后通过。首轮SW_HIDE启动标志覆盖了第一次ShowWindow，亦已修正，失败日志保留。父进程只对自己CreateProcess得到的句柄执行超时终止；没有对既有应用操作。

这是原生编码通道到真实WebView的验收，不启动Flutter引擎，不能冒称Dart侧经Flutter引擎到原生的完整端到端。正式包不定义PARASELENE_LEARNING_PROBE，也没有新增可调用测试接口；新增friend仅存在于独立探针编译目标。

## 证据与边界

最终运行、正式Release和独立包结果将在本节后列明。静态检查以C++ /W4 /WX编译和正式Release为本批门禁；没有Dart/Rust业务改动，不重复已通过的大回归或改golden。只读复审指出的位置权限假通过风险已补严格原生状态断言；祖先写入缺陷修复后的末次只读复审无新增确定缺陷。

仍未完成：其他权限/下载/popup与路径攻击变体、不同WebView2运行时、Flutter引擎完整open链路、桌宠/托盘/quiet实际交互、完整IME/DPI/多屏、系统文件对话框组合与净机安装。作者数据接管、真实模型及发布不在当前授权内；不把这些项目改成PASS或用已有单机结果替代。

## 最终结果

- `m9-learning-native/junction-write-fixed/result.json`：完整扩展原生专项退出0；含修前失败、修后祖先junction目标无新profile目录、popup/自动下载权限、双语Python、Worker/CSP/消息、超时、关闭/重开、renderer/browser崩溃。
- `m9-learning-native/channel-final/result.json`：原生编码通道专项退出0；中英真实Open/Pyodide/重复打开/WM_CLOSE与取消迟到均通过，且所显示窗口始终在非input desktop。
- `m9-learning-native/geolocation-final/result.json`：严格GEOLOCATION+DENY原生状态及页面拒绝专项退出0；父HWND保持隐藏。
- `m9-learning-native/windows-release-audit.txt`：正式Windows Release退出0（16.9秒增量）。
- 各专项`inputs-sha256.json`记录正式源码、独立探针及固定资源；独立C++目标以/W4 /WX编译通过。PowerShell脚本语法解析与本轮tracked原生diff空白检查通过。
- 只读复审提出的地理位置状态断言缺口已修订；祖先先写入缺陷的修前失败与最终通过均保留，末次复审无新增确定缺陷。
