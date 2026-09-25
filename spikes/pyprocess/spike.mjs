// 本地受限进程方案 spike（T00 / ADR-0002 证据）。
// 测量：python 子进程启动耗时、执行耗时，并实测默认进程模型的隔离边界
// （预期：默认子进程可读用户文件、可联网 —— 证明裸 subprocess 不满足 G13）。
// 运行：node spike.mjs（在 spikes/pyprocess 目录下）
import { spawn } from "node:child_process";

const PY = "C:\\Users\\HP\\AppData\\Local\\Programs\\Python\\Python312\\python.exe";

function runPy(code) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const p = spawn(PY, ["-I", "-c", code], { stdio: ["ignore", "pipe", "pipe"] });
    let out = "", err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("close", (code2) => resolve({ ms: Math.round(performance.now() - t0), out: out.trim(), err: err.trim(), code: code2 }));
  });
}

// 1) 启动 + 执行开销（含解释器启动）
const t0 = performance.now();
const r1 = await runPy("print('ok')");
console.log("startup+exec ms:", r1.ms, "out:", r1.out);

// 2) 隔离边界实测
const fsProbe = await runPy(`
try:
    open(r"C:\\Windows\\win.ini").read(10)
    print("FS-ACCESSIBLE")
except Exception as e:
    print("FS-BLOCKED:", type(e).__name__)
`);
console.log("fs probe:", fsProbe.out);

const netProbe = await runPy(`
import socket
try:
    s = socket.create_connection(("example.com", 80), timeout=3)
    s.close()
    print("NET-ACCESSIBLE")
except Exception as e:
    print("NET-BLOCKED:", type(e).__name__)
`);
console.log("net probe:", netProbe.out);
