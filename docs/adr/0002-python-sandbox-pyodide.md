# ADR-0002：Python 练习执行环境选用 Pyodide（WASM）

- 状态：已接受（2026-09-26，T00 spike 实测后锁定）
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
| 网络 | Node 环境 ACCESSIBLE（Node socket shim）；**WebView2 浏览器环境无 Node 集成时不可达** | **ACCESSIBLE**（默认即可连 example.com:80） |

## 决定

**v1 采用 Pyodide，在 WebView2 中以纯浏览器上下文运行（禁 Node 集成）**。理由：

1. 沙箱是默认姿态而非补救措施：WASM 虚拟文件系统 + 无 Node 桥接 = 天然满足 G13；本地子进程在 Windows 上默认零隔离，真隔离要靠 Job Object + 受限令牌/AppContainer，成本高且仍有缝隙。
2. 与 Tauri 架构同侧：练习代码在前端编辑器 → 同进程 WASM 执行，IPC 往返为零，测试结果回传即时。
3. 按需加载对冲内存代价：只在用户点开练习窗口时加载 Pyodide，关闭即释放（对应 brief"展开窗口才加载执行环境"）。

## 后果

- 代价：+83MB RSS 与 1.3–2.5s 加载延迟（仅练习窗口存活期间）； Pyodide 的 Python 版本与包生态受限（纯函数练习足够；numpy 等包需单独评估 micropip）。
- 红线（写进 AGENTS.md §4 已有）：WebView2 **禁止开启 Node 集成**（`withGlobalTauri`/Node.js 桥接），否则沙箱失效——G13 的自动化测试要覆盖这一点。
- 备选（未采用，记录在案）：本地受限进程 + Job Object/低完整性令牌；未来若做"运行真实项目代码"的重型场景再评估。

## 验证

- spikes/pyodide/spike.mjs、spikes/pyprocess/spike.mjs 可复跑；数据原文见 docs/evidence/T00-20260926.md。
