// Pyodide 沙箱方案 spike（T00 / ADR-0002 证据）。
// 测量：npm 包加载 + WASM 运行时初始化耗时、常驻内存增量、执行一个带断言的练习函数。
// 运行：node spike.mjs（在 spikes/pyodide 目录下）
import { loadPyodide } from "pyodide";

const mem = () => process.memoryUsage().rss / 1024 / 1024;
const memBaseline = mem();

const t0 = performance.now();
const pyodide = await loadPyodide();
const tLoad = performance.now() - t0;
const memAfterLoad = mem();

// 模拟练习场景：定义函数 + 跑测试（对应 G12 的"补全代码 → 可重跑测试"）
const t1 = performance.now();
const result = pyodide.runPython(`
def add(a, b):
    return a + b

assert add(2, 3) == 5
assert add(-2, 2) == 0
"ok"
`);
const tExec = performance.now() - t1;

// 沙箱性快速验证（表达式形式，取最后一个表达式的值）：
// 1) 文件系统：open 应只能落在 Pyodide 虚拟 FS（MEMFS），真实路径不可达
// 2) 网络：标准库 socket 不可用
const fsCheck = pyodide.runPython(
  `"FS-BLOCKED" if __import__("os").path.exists("C:/Windows/win.ini") == False else "FS-ACCESSIBLE"`
);
const netCheck = pyodide.runPython(
  `("NET-BLOCKED", None) if not __import__("importlib").util.find_spec("socket") else ("NET-?", "socket-exists")`
);

console.log(JSON.stringify({
  nodeBaselineMB: Math.round(memBaseline),
  loadMs: Math.round(tLoad),
  execMs: Math.round(tExec),
  rssAfterLoadMB: Math.round(memAfterLoad),
  rssDeltaMB: Math.round(memAfterLoad - memBaseline),
  result,
  fsCheck,
  netCheck: netCheck[0],
}, null, 2));
