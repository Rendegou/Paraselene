// Only this Worker executes learner code. It has no Tauri bridge or parent IPC forwarding.
import { loadPyodide } from "/pyodide/pyodide.mjs";
let pyodide;
const resultToken = crypto.randomUUID();
const send = self.postMessage.bind(self);
try {
  pyodide = await loadPyodide({ indexURL: "https://learning-sandbox.invalid/pyodide/" });
  send({ type: "ready", token: resultToken });
} catch (error) {
  send({ type: "boot-error", message: String(error) });
}

self.onmessage = async (event) => {
  const { type, id, code } = event.data ?? {};
  if (type !== "run" || !Number.isSafeInteger(id) || typeof code !== "string" || code.length > 20_000 || !pyodide) return;
  // One run per Worker. Learner Python cannot re-enter this handler while it runs.
  self.onmessage = null;
  let scope;
  try {
    scope = pyodide.runPython("{}");
    // Use the isolated namespace directly; wrapping compile/exec loses async evaluation.
    await pyodide.runPythonAsync(code, { globals: scope, filename: "<exercise>" });
    const fn = scope.get("double");
    let passed = 0;
    const notes = [];
    for (const [value, expected] of [[2, 4], [0, 0], [-3, -6]]) {
      try {
        const actual = typeof fn === "function" ? fn(value) : undefined;
        const ok = typeof actual === "number" && actual === expected;
        if (ok) passed += 1;
        notes.push(`double(${value}) → ${String(actual)}, expected ${expected}: ${ok ? "passed" : "failed"}`);
      } catch (error) {
        notes.push(`double(${value})：${String(error).slice(0, 500)}`);
      }
    }
    fn?.destroy?.();
    send({ type: "result", token: resultToken, id, passed, detail: notes.join("\n") });
  } catch (error) {
    send({ type: "result", token: resultToken, id, passed: 0, detail: String(error).slice(0, 4000) });
  } finally {
    scope?.destroy();
  }
};
