// Dedicated Worker G13 probe. Do not evaluate user-supplied code here.
import { loadPyodide } from "/pyodide/pyodide.mjs";
(async () => {
  const result = {
    workerTauriBridge: typeof self.__TAURI_INTERNALS__ !== "undefined",
    workerIpcGlobal: typeof self.ipc !== "undefined",
    workerWebviewBridge: typeof self.chrome?.webview !== "undefined",
    cspViolations: [],
  };
  self.addEventListener("securitypolicyviolation", (event) => {
    result.cspViolations.push({ directive: event.effectiveDirective, blockedUri: event.blockedURI });
  });
  try {
    const response = await fetch("https://example.com/", { mode: "no-cors" });
    result.externalFetch = `resolved:${response.type}`;
  } catch (error) { result.externalFetch = `rejected:${String(error)}`; }
  try {
    const response = await fetch("file:///C:/Windows/win.ini");
    result.fileFetch = `resolved:${response.type}`;
  } catch (error) { result.fileFetch = `rejected:${String(error)}`; }
  try {
    const response = await fetch("http://ipc.localhost/", { mode: "no-cors" });
    result.ipcFetch = `resolved:${response.type}`;
  } catch (error) { result.ipcFetch = `rejected:${String(error)}`; }
  try {
    for (const name of ["pyodide-lock.json", "pyodide.asm.mjs", "pyodide.asm.wasm", "python_stdlib.zip"]) {
      const response = await fetch("http://probe-assets.localhost/pyodide/" + name);
      self.postMessage({ stage: `${name}: ${response.status} ${response.headers.get("content-type")}` });
      if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
      await response.body.cancel();
    }
    self.postMessage({ stage: "loading Pyodide" });
    const pyodide = await loadPyodide({ indexURL: "http://probe-assets.localhost/pyodide/" });
    self.postMessage({ stage: "Pyodide loaded" });
    result.pyodideLoaded = true;
    result.pythonFileExists = pyodide.runPython("__import__('os').path.exists('C:/Windows/win.ini')");
    result.pythonJsBridge = pyodide.runPython("hasattr(__import__('js'), '__TAURI_INTERNALS__')");
    result.pythonFetchVisible = pyodide.runPython("hasattr(__import__('js'), 'fetch')");
    try {
      await pyodide.runPythonAsync("from pyodide.ffi import to_js\nawait __import__('js').fetch('https://example.com/', to_js({'mode': 'no-cors'}))");
      result.pythonExternalFetch = "resolved";
    } catch (error) { result.pythonExternalFetch = `rejected:${String(error)}`; }
  } catch (error) { result.pyodideError = String(error); }
  self.postMessage({ ...result, final: true });
})();
