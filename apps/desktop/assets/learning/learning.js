// This page never evaluates learner code and never forwards worker messages to Tauri IPC.
const code = document.getElementById("code");
const run = document.getElementById("run");
const reset = document.getElementById("reset");
const hint = document.getElementById("hint");
const hintText = document.getElementById("hint-text");
const status = document.getElementById("status");
const result = document.getElementById("result");
const example = code.value;
const hints = ["先想清楚：输入 x 后，要把哪个计算结果交还给调用者？", "在函数里写 return，并让返回值等于 x 乘以 2。", "完整写法是 return x * 2。可以再运行一次测试。"];
let hintLevel = 0;
let worker = null;
let workerUrl = null;
let requestId = 0;
let timeout = null;
let readyToken = null;
let submittedCode = "";

function stopWorker() {
  if (timeout !== null) clearTimeout(timeout);
  timeout = null;
  worker?.terminate();
  worker = null;
  if (workerUrl) URL.revokeObjectURL(workerUrl);
  workerUrl = null;
  readyToken = null;
  run.disabled = false;
  code.disabled = false;
}

function startWorker() {
  // A Blob module Worker inherits this window's CSP. The import target is fixed.
  workerUrl = URL.createObjectURL(new Blob([
    "import('https://learning-sandbox.invalid/worker.js').catch(error => self.postMessage({type:'boot-error', message:String(error)}));",
  ], { type: "text/javascript" }));
  worker = new Worker(workerUrl, { type: "module" });
  worker.onmessage = (event) => {
    const message = event.data;
    if (!message || typeof message !== "object") return;
    if (message.type === "ready" && readyToken === null && typeof message.token === "string" && message.token.length === 36) {
      readyToken = message.token;
      status.textContent = "Python 已就绪，正在运行测试…";
      worker.postMessage({ type: "run", id: requestId, code: submittedCode });
    } else if (message.type === "result" && readyToken !== null && message.token === readyToken && message.id === requestId) {
      status.textContent = message.passed === 3 ? "3 / 3 项测试通过" : `${message.passed} / 3 项测试通过`;
      result.textContent = typeof message.detail === "string" ? message.detail.slice(0, 4000) : "结果格式错误";
      stopWorker();
    } else if (message.type === "boot-error" && readyToken === null) {
      status.textContent = "运行器加载失败";
      result.textContent = String(message.message).slice(0, 1000);
      stopWorker();
    }
  };
  worker.onerror = () => {
    status.textContent = "运行器启动失败";
    result.textContent = "请关闭练习窗口后重试。";
    stopWorker();
  };
}

run.addEventListener("click", () => {
  stopWorker();
  if (code.value.length > 20_000) {
    status.textContent = "代码不能超过 20,000 个字符";
    return;
  }
  requestId += 1;
  submittedCode = code.value;
  run.disabled = true;
  code.disabled = true;
  status.textContent = "正在启动本地 Python…";
  result.textContent = "";
  try { startWorker(); } catch {
    status.textContent = "无法启动运行器";
    stopWorker();
    return;
  }
  timeout = setTimeout(() => {
    status.textContent = "运行超时，已结束本次执行";
    result.textContent = "检查是否有无限循环，再试一次。";
    stopWorker();
  }, 30_000);
});

reset.addEventListener("click", () => {
  stopWorker();
  code.value = example;
  hintLevel = 0;
  hintText.textContent = "";
  hint.disabled = false;
  status.textContent = "已恢复题目";
  result.textContent = "";
});
hint.addEventListener("click", () => {
  if (hintLevel >= hints.length) return;
  hintText.textContent = `提示 ${hintLevel + 1} / 3：${hints[hintLevel]}`;
  hintLevel += 1;
  hint.disabled = hintLevel >= hints.length;
});
window.addEventListener("pagehide", stopWorker);
