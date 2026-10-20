// This page never evaluates learner code and never forwards worker messages to Tauri IPC.
const code = document.getElementById("code");
const run = document.getElementById("run");
const reset = document.getElementById("reset");
const hint = document.getElementById("hint");
const hintText = document.getElementById("hint-text");
const status = document.getElementById("status");
const result = document.getElementById("result");
const example = code.value;
const hints = ["What result should the function return for input x?", "Use return to give back x multiplied by 2.", "Try return x * 2, then run the tests again."];
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
    "import('https://learning-sandbox.invalid/worker-en.js').catch(error => self.postMessage({type:'boot-error', message:String(error)}));",
  ], { type: "text/javascript" }));
  worker = new Worker(workerUrl, { type: "module" });
  worker.onmessage = (event) => {
    const message = event.data;
    if (!message || typeof message !== "object") return;
    if (message.type === "ready" && readyToken === null && typeof message.token === "string" && message.token.length === 36) {
      readyToken = message.token;
      status.textContent = "Python is ready. Running tests…";
      worker.postMessage({ type: "run", id: requestId, code: submittedCode });
    } else if (message.type === "result" && readyToken !== null && message.token === readyToken && message.id === requestId) {
      status.textContent = message.passed === 3 ? "3 / 3 tests passed" : `${message.passed} / 3 tests passed`;
      result.textContent = typeof message.detail === "string" ? message.detail.slice(0, 4000) : "Invalid result format";
      stopWorker();
    } else if (message.type === "boot-error" && readyToken === null) {
      status.textContent = "Runtime could not load";
      result.textContent = String(message.message).slice(0, 1000);
      stopWorker();
    }
  };
  worker.onerror = () => {
    status.textContent = "Runtime could not start";
    result.textContent = "Close the exercise window and try again.";
    stopWorker();
  };
}

run.addEventListener("click", () => {
  stopWorker();
  if (code.value.length > 20_000) {
    status.textContent = "Code must be at most 20,000 characters";
    return;
  }
  requestId += 1;
  submittedCode = code.value;
  run.disabled = true;
  code.disabled = true;
  status.textContent = "Starting local Python…";
  result.textContent = "";
  try { startWorker(); } catch {
    status.textContent = "Runtime could not start";
    stopWorker();
    return;
  }
  timeout = setTimeout(() => {
    status.textContent = "Run timed out and was terminated";
    result.textContent = "Check for infinite loops and try again.";
    stopWorker();
  }, 30_000);
});

reset.addEventListener("click", () => {
  stopWorker();
  code.value = example;
  hintLevel = 0;
  hintText.textContent = "";
  hint.disabled = false;
  status.textContent = "Exercise reset";
  result.textContent = "";
});
hint.addEventListener("click", () => {
  if (hintLevel >= hints.length) return;
  hintText.textContent = `Hint ${hintLevel + 1} / 3: ${hints[hintLevel]}`;
  hintLevel += 1;
  hint.disabled = hintLevel >= hints.length;
});
window.addEventListener("pagehide", stopWorker);
