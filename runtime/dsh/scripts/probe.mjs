import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { launchOfflineBridge } from "../src/launch.mjs";

/** Exercise a real dsh CLI process with synthetic prompts and a synthetic, network-free provider. */
export async function runProbe() {
  const runtime = await launchOfflineBridge();
  const events = [];
  const listeners = new Set();
  let pending = "";
  let stderr = "";
  let exited;
  let parseError;
  runtime.child.stderr.setEncoding("utf8");
  runtime.child.stderr.on("data", text => { stderr = (stderr + text).slice(-4_000); });
  runtime.child.stdout.setEncoding("utf8");
  runtime.child.stdout.on("data", text => {
    pending += text;
    let newline;
    while ((newline = pending.indexOf("\n")) !== -1) {
      const line = pending.slice(0, newline);
      pending = pending.slice(newline + 1);
      try { events.push(JSON.parse(line)); }
      catch { parseError = new Error("The bridge wrote a non-JSON protocol line"); }
    }
    for (const notify of listeners) notify();
  });
  void runtime.exited.then(result => { exited = result; for (const notify of listeners) notify(); });
  const waitFor = predicate => new Promise((resolve, reject) => {
    const timeout = setTimeout(() => finish(new Error(`Offline probe timed out; ${stderr}`)), 15_000);
    function finish(error, event) {
      clearTimeout(timeout);
      listeners.delete(check);
      error ? reject(error) : resolve(event);
    }
    function check() {
      if (parseError) { finish(parseError); return; }
      const event = events.find(predicate);
      if (event) { finish(undefined, event); return; }
      if (exited) finish(new Error(`dsh exited before the expected frame: ${JSON.stringify(exited)}; frames=${JSON.stringify(events.map(event => [event.type, event.code, event.requestId]))}; ${stderr}`));
    }
    listeners.add(check);
    check();
  });
  const send = command => runtime.child.stdin.write(`${JSON.stringify({ version: 1, ...command })}\n`);
  try {
    const ready = await waitFor(event => event.type === "ready");
    assert.equal(ready.runtimeVersion, "0.2.1-rc.2");
    assert.equal(ready.modelMode, "SIMULATED");

    send({ type: "run", requestId: "complete-1", scope: { space: "personal" }, prompt: "synthetic request" });
    const completed = await waitFor(event => event.type === "done" && event.requestId === "complete-1");
    assert.equal(completed.outcome, "completed");
    assert.equal(events.filter(event => event.type === "delta" && event.requestId === "complete-1").map(event => event.content).join(""), "OFFLINE_DSH_RESPONSE");

    send({ type: "run", requestId: "complete-1", scope: { space: "idea" }, prompt: "duplicate request" });
    assert.equal((await waitFor(event => event.type === "error" && event.requestId === "complete-1")).code, "DUPLICATE_ID");

    send({ type: "run", requestId: "cancel-1", scope: { space: "novel", workId: "synthetic-work" }, prompt: "wait-for-cancel" });
    await waitFor(event => event.type === "delta" && event.requestId === "cancel-1");
    send({ type: "run", requestId: "busy-1", scope: { space: "personal" }, prompt: "busy request" });
    assert.equal((await waitFor(event => event.type === "error" && event.requestId === "busy-1")).code, "BUSY");
    send({ type: "cancel", requestId: "wrong-id" });
    assert.equal((await waitFor(event => event.type === "error" && event.requestId === "wrong-id")).code, "NOT_RUNNING");
    send({ type: "cancel", requestId: "cancel-1" });
    const cancelled = await waitFor(event => event.type === "done" && event.requestId === "cancel-1");
    assert.equal(cancelled.outcome, "cancelled");

    send({ type: "run", requestId: "after-cancel", scope: { space: "learning" }, prompt: "synthetic followup" });
    assert.equal((await waitFor(event => event.type === "done" && event.requestId === "after-cancel")).outcome, "completed");
    const cancelIndex = events.indexOf(cancelled);
    assert.equal(events.slice(cancelIndex + 1).some(event => event.type === "delta" && event.requestId === "cancel-1"), false);
    assert.equal(events.filter(event => event.type === "done" && event.requestId === "cancel-1").length, 1);

    send({ type: "shutdown" });
    const result = await Promise.race([
      runtime.exited,
      new Promise((_, reject) => {
        const timeout = setTimeout(() => reject(new Error(`dsh shutdown did not finish; ${stderr}`)), 5_000);
        timeout.unref();
      }),
    ]);
    assert.equal(result.code, 0);
    return { runtime: "REAL dsh 0.2.1-rc.2", model: "SIMULATED", passed: ["stream", "terminal", "request ownership", "busy rejection", "cancel", "run after cancel", "shutdown"] };
  } finally {
    await runtime.dispose();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(JSON.stringify(await runProbe(), null, 2));
}
