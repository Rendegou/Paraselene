# ADR-0002：Python 练习执行环境选用 Pyodide（WASM）

- 状态：条件接受；执行引擎候选已选，隔离方案未通过安全验收（2026-09-26 复核）
- 决策者：kimi（依据 spike 数据），对应验收项 G12/G13/G19

## 背景

幻月的 Python 5 分钟练习需要在本机执行用户代码。Goal §4.4 要求：运行器不可读用户私人目录、不可联网（G13 要有自动化测试证明），且空闲不占用资源（轻量）。

## Spike 实测（2026-09-26，本机，spikes/ 下脚本可复跑）

| 指标 | Pyodide（Node 测量） | 本地子进程（python 3.12 `-I`） |
|---|---|---|
| 加载/启动耗时 | 冷 2529ms / 热 1325ms | 87ms |
| 内存增量（RSS） | +83MB（Node 基线 31MB → 114MB） | ~15MB/进程 |
| 安装包体积 | 14MB（pyodide.asm.wasm 约 11MB） | 0（系统已有 Python） |
| 文件系统访问 | **BLOCKED**（仅虚拟 MEMFS，`C:/Windows/win.ini` 不可达） | **ACCESSIBLE**（默认即可读） |
| 网络 | Node 环境 ACCESSIBLE；WebView2 尚未实测，Pyodide 官方支持经 `js.fetch` / `pyfetch` 联网 | **ACCESSIBLE**（默认即可连 example.com:80） |

## 决定

**v1 可用 Pyodide 作为执行引擎，但不能在拥有 Tauri IPC 的主 WebView 中直接运行用户代码。** T00 的 Node spike 只比较了运行开销与裸进程风险，未证明 WebView2 的安全边界。理由：

1. WASM 虚拟文件系统阻止普通 Python 文件 API 直接读取 Windows 路径，但 Pyodide 的 `js` 模块暴露宿主 JavaScript 全局对象，并提供 `pyfetch`。只关闭 Node 集成并不能证明不可联网；主 WebView 的 Tauri 命令还可能被用户代码间接调用。
2. 编辑器可留在主卡片，执行器必须放在独立隔离上下文。候选是无 Tauri capability 的独立 WebView/不透明来源，并以 CSP 禁止网络；实现前先验证平台对该边界的实际执行。不能靠删除 `fetch` 等全局函数做安全保证。
3. 按需加载对冲内存代价：只在用户点开练习窗口时加载 Pyodide，关闭即释放（对应 brief"展开窗口才加载执行环境"）。

## 后果

- 代价：+83MB RSS 与 1.3–2.5s 加载延迟（仅练习窗口存活期间）； Pyodide 的 Python 版本与包生态受限（纯函数练习足够；numpy 等包需单独评估 micropip）。
- 红线：**主 WebView 不运行不可信 Python**。独立执行上下文需无 Tauri IPC 权限、无网络出口、无用户目录访问；G13 必须在真实 Windows WebView2 中测试 `import js`、`pyodide.http.pyfetch`、Tauri 命令与文件访问的反例。
- `withGlobalTauri` 是 Tauri API 的全局注入选项，不能与 Node 集成混为一谈；Tauri 官方说明自定义命令默认允许所有应用 WebView 调用，因此隔离窗口还需单独收紧命令权限。
- 备选（未采用，记录在案）：本地受限进程 + Job Object/低完整性令牌；未来若做"运行真实项目代码"的重型场景再评估。

## 复核来源与门禁

- [Pyodide Python API](https://pyodide.org/en/stable/usage/api/python-api.html)：`js` 映射全局 JavaScript 作用域，并有 `pyodide.http` 网络接口。
- [Pyodide FAQ](https://pyodide.org/en/stable/usage/faq.html)：官方示例从 Python 调用 `js.fetch`。
- [Tauri capabilities](https://tauri.app/security/capabilities/)：自定义命令默认可被应用的所有窗口和 WebView 调用。
- 在 G13 隔离反例测试通过前，T06 不得把 Pyodide 原型标为安全沙箱或开放任意用户代码执行。

## 验证

- spikes/pyodide/spike.mjs、spikes/pyprocess/spike.mjs 可复跑；数据原文见 docs/evidence/T00-20260926.md。
