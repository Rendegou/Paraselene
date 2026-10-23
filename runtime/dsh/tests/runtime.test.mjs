import assert from "node:assert/strict";
import test from "node:test";
import { existsSync } from "node:fs";
import { runProbe } from "../scripts/probe.mjs";
import { launchOfflineBridge } from "../src/launch.mjs";

async function connect() {
  const runtime = await launchOfflineBridge();
  const events = [];
  let pending = "";
  let failure;
  const listeners = new Set();
  runtime.child.stdout.setEncoding("utf8");
  runtime.child.stdout.on("data", chunk => {
    pending += chunk;
    let newline;
    while ((newline = pending.indexOf("\n")) !== -1) {
      const line = pending.slice(0, newline);
      pending = pending.slice(newline + 1);
      try { events.push(JSON.parse(line)); }
      catch { failure = new Error("Expected a protocol JSON frame"); }
    }
    for (const notify of listeners) notify();
  });
  void runtime.exited.then(result => {
    failure ??= new Error(`Runtime exited: ${JSON.stringify(result)}`);
    for (const notify of listeners) notify();
  });
  const waitFor = predicate => new Promise((resolve, reject) => {
    const timeout = setTimeout(() => finish(new Error("Timed out waiting for a protocol frame")), 10_000);
    function finish(error, value) { clearTimeout(timeout); listeners.delete(check); error ? reject(error) : resolve(value); }
    function check() {
      const value = events.find(predicate);
      if (value) finish(undefined, value);
      else if (failure) finish(failure);
    }
    listeners.add(check);
    check();
  });
  try { await waitFor(event => event.type === "ready"); }
  catch (error) { await runtime.dispose(); throw error; }
  return { ...runtime, events, waitFor, send: command => runtime.child.stdin.write(`${JSON.stringify({ version: 1, ...command })}\n`) };
}

async function waitForExit(runtime) {
  let timeout;
  try {
    return await Promise.race([
      runtime.exited,
      new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error("Runtime did not exit")), 5_000); }),
    ]);
  } finally { clearTimeout(timeout); }
}

test("real dsh profile streams, cancels one activity, accepts later work and exits", { timeout: 25_000 }, async () => {
  const result = await runProbe();
  assert.equal(result.model, "SIMULATED");
  assert.ok(result.passed.includes("run after cancel"));
});

test("EOF disposes an idle dsh process and removes its isolated home", { timeout: 20_000 }, async () => {
  const runtime = await connect();
  try {
    runtime.child.stdin.end();
    assert.equal((await waitForExit(runtime)).code, 0);
    await runtime.dispose();
    assert.equal(existsSync(runtime.directory), false);
  } finally { await runtime.dispose(); }
});

test("cancel in the creation batch settles once before later work", { timeout: 20_000 }, async () => {
  const runtime = await connect();
  try {
    runtime.child.stdin.write([
      { version: 1, type: "run", requestId: "early-cancel", scope: { space: "personal" }, prompt: "wait-for-cancel" },
      { version: 1, type: "cancel", requestId: "early-cancel" },
    ].map(command => JSON.stringify(command)).join("\n") + "\n");
    assert.equal((await runtime.waitFor(event => event.type === "done" && event.requestId === "early-cancel")).outcome, "cancelled");
    runtime.send({ type: "run", requestId: "after-early", scope: { space: "idea" }, prompt: "synthetic" });
    assert.equal((await runtime.waitFor(event => event.type === "done" && event.requestId === "after-early")).outcome, "completed");
    assert.equal(runtime.events.filter(event => event.type === "done" && event.requestId === "early-cancel").length, 1);
  } finally { await runtime.dispose(); }
});

test("EOF during model streaming cancels and reaps the process", { timeout: 20_000 }, async () => {
  const runtime = await connect();
  try {
    runtime.send({ type: "run", requestId: "eof-active", scope: { space: "learning" }, prompt: "wait-for-cancel" });
    await runtime.waitFor(event => event.type === "delta" && event.requestId === "eof-active");
    runtime.child.stdin.end();
    assert.equal((await waitForExit(runtime)).code, 0);
    await runtime.dispose();
    assert.equal(existsSync(runtime.directory), false);
  } finally { await runtime.dispose(); }
});

test("malformed input is rejected safely and an oversized unfinished line closes the process", { timeout: 20_000 }, async () => {
  const runtime = await connect();
  try {
    runtime.child.stdin.write("synthetic-private-not-json\n");
    const rejected = await runtime.waitFor(event => event.type === "error" && event.code === "INVALID_JSON");
    assert.equal(JSON.stringify(rejected).includes("synthetic-private"), false);
    runtime.child.stdin.write("x".repeat(65_537));
    await runtime.waitFor(event => event.type === "error" && event.code === "INPUT_TOO_LARGE");
    assert.equal((await waitForExit(runtime)).code, 1);
  } finally { await runtime.dispose(); }
});
