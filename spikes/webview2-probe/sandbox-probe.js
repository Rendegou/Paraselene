// Browser-side G13 probe. No user code or user data.
(async () => {
  const report = (result) => {
    window.location.replace("/probe-result.html?report=" + encodeURIComponent(JSON.stringify(result)));
  };
  const main = { tauriBridge: typeof window.__TAURI_INTERNALS__ !== "undefined" };
  main.cspViolations = [];
  window.addEventListener("securitypolicyviolation", (event) => {
    main.cspViolations.push({ directive: event.effectiveDirective, blockedUri: event.blockedURI });
  });
  try {
    main.ping = await Promise.race([
      window.__TAURI_INTERNALS__.invoke("probe_ping"),
      new Promise((_, reject) => setTimeout(() => reject(new Error("ping timeout")), 3000)),
    ]);
  } catch (error) { main.pingError = String(error); }
  let worker;
  // Blob workers inherit the creating document's CSP; asset-URL workers do not.
  let workerUrl;
  try {
    workerUrl = URL.createObjectURL(new Blob(["import('http://tauri.localhost/sandbox-probe-worker.js').catch(error => self.postMessage({bootError: String(error)}));"], { type: "text/javascript" }));
    worker = new Worker(workerUrl, { type: "module" });
  }
  catch (error) { report({ main, workerError: String(error) }); return; }
  let latestStage = "worker created";
  const timeout = setTimeout(() => {
    report({ main, timeout: true, latestStage });
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
  }, 45000);
  worker.onmessage = (event) => {
    if (event.data.stage) { latestStage = event.data.stage; return; }
    clearTimeout(timeout);
    report({ main, worker: event.data });
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
  };
  worker.onerror = (event) => {
    clearTimeout(timeout);
    report({ main, workerError: event.message || "unknown worker error", filename: event.filename, lineno: event.lineno });
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
  };
})();
