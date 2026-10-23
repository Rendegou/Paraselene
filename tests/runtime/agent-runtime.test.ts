import assert from "node:assert/strict";
import test from "node:test";
import { createAgentRuntime, requireAgentRuntime, RuntimeError } from "../../src/lib/runtime/agent-runtime";
import { createLegacyRustRuntime } from "../../src/lib/runtime/legacy-rust";
import type { ChatRequest, IssuedPreview, LlmStreamEvent, RuntimeId } from "../../src/lib/runtime/contracts";

// SIMULATED transport: synthetic text only; no model, credentials, WebView or filesystem access.
const request: ChatRequest = { space: "idea", messages: [{ role: "user", content: "synthetic prompt" }] };

function fixture(id: RuntimeId = "legacy-rust") {
  const sends: string[] = [];
  const previews: ChatRequest[] = [];
  const result: IssuedPreview = {
    id: "native-once-only-ticket",
    prepared: { ...structuredClone(request), model: "synthetic-model", estimated_tokens: 4 },
  };
  let sendImpl = async (_token: string, onEvent: (event: LlmStreamEvent) => void) => {
    onEvent({ type: "delta", content: "synthetic answer" });
    onEvent({ type: "done", finish_reason: "stop", usage: { input_tokens: 4, output_tokens: 3 } });
  };
  const driver = {
    descriptor: { id, capabilities: { cancel: false, toolExecution: false, sessionResume: false } },
    async preview(value: ChatRequest) { previews.push(value); return result; },
    async send(token: string, onEvent: (event: LlmStreamEvent) => void) {
      sends.push(token);
      await sendImpl(token, onEvent);
    },
    async listModels() { return ["synthetic-model"]; },
  };
  return {
    runtime: createAgentRuntime(driver), driver, sends, previews, result,
    setSend(impl: typeof sendImpl) { sendImpl = impl; },
  };
}

function runtimeError(code: RuntimeError["code"]) {
  return (error: unknown) => error instanceof RuntimeError && error.code === code;
}

test("legacy adapter delegates the request, backend ticket and stream without exposing credentials", async () => {
  const f = fixture();
  const runtime = createLegacyRustRuntime(f.driver);
  assert.equal(f.previews.length, 0, "construction must not prepare or send a model request");
  assert.equal(f.sends.length, 0);
  assert.equal(runtime.descriptor.capabilities.cancel, false);
  assert.equal(runtime.cancel, undefined);
  const preview = await runtime.preview(request);
  assert.deepEqual(f.previews, [request]);
  assert.equal(preview.runtimeId, "legacy-rust");
  const events: LlmStreamEvent[] = [];
  await runtime.send(preview, (event) => events.push(event));
  assert.deepEqual(f.sends, ["native-once-only-ticket"]);
  assert.deepEqual(events, [
    { type: "delta", content: "synthetic answer" },
    { type: "done", finish_reason: "stop", usage: { input_tokens: 4, output_tokens: 3 } },
  ]);
  assert.deepEqual(await runtime.listModels(), ["synthetic-model"]);
});

test("preview snapshot stays unchanged if the driver later modifies its original object", async () => {
  const f = fixture();
  const preview = await f.runtime.preview(request);
  assert.notEqual(preview.prepared, f.result.prepared);
  assert.notEqual(preview.prepared.messages, f.result.prepared.messages);
  assert.ok(Object.isFrozen(preview));
  assert.ok(Object.isFrozen(preview.prepared));
  assert.ok(Object.isFrozen(preview.prepared.messages[0]));
  assert.equal(Reflect.set(f.result.prepared.messages[0], "content", "driver changed its copy"), true);
  assert.equal(preview.prepared.messages[0].content, "synthetic prompt");
  assert.equal(Reflect.set(preview.prepared.messages[0], "content", "changed"), false);
});

test("foreign, copied, cross-engine and already-consumed previews never reach a driver", async () => {
  const a = fixture();
  const b = fixture();
  const dsh = fixture("dsh");
  const preview = await a.runtime.preview(request);
  await assert.rejects(b.runtime.send(preview, () => {}), runtimeError("invalid_preview"));
  await assert.rejects(dsh.runtime.send(preview, () => {}), runtimeError("invalid_preview"));
  await assert.rejects(a.runtime.send({ ...preview }, () => {}), runtimeError("invalid_preview"));
  assert.deepEqual(b.sends, []);
  assert.deepEqual(dsh.sends, []);
  assert.deepEqual(a.sends, []);
  await a.runtime.send(preview, () => {});
  await assert.rejects(a.runtime.send(preview, () => {}), runtimeError("invalid_preview"));
  assert.equal(a.sends.length, 1);
});

test("a concurrent double-send consumes the preview before entering the asynchronous transport", async () => {
  const f = fixture();
  let release!: () => void;
  const paused = new Promise<void>((resolve) => { release = resolve; });
  f.setSend(async () => paused);
  const preview = await f.runtime.preview(request);
  const first = f.runtime.send(preview, () => {});
  await assert.rejects(f.runtime.send(preview, () => {}), runtimeError("invalid_preview"));
  assert.equal(f.sends.length, 1);
  release();
  await first;
});

test("transport failure is preserved and the uncertain ticket is not automatically retried", async () => {
  const f = fixture();
  const failure = new Error("synthetic transport failure");
  f.setSend(async () => { throw failure; });
  const preview = await f.runtime.preview(request);
  await assert.rejects(f.runtime.send(preview, () => {}), (error) => error === failure);
  await assert.rejects(f.runtime.send(preview, () => {}), runtimeError("invalid_preview"));
  assert.equal(f.sends.length, 1);
});

test("model errors remain structured events rather than fabricated successful completions", async () => {
  const f = fixture();
  const event: LlmStreamEvent = { type: "error", kind: "gate_closed", message: "synthetic closed space" };
  f.setSend(async (_token, onEvent) => { onEvent(event); });
  const received: LlmStreamEvent[] = [];
  await f.runtime.send(await f.runtime.preview(request), (value) => received.push(value));
  assert.deepEqual(received, [event]);
});

test("explicit unavailable dsh selection never falls back to the existing backend", () => {
  const f = fixture();
  assert.equal(requireAgentRuntime("legacy-rust", [f.runtime]), f.runtime);
  assert.throws(() => requireAgentRuntime("dsh", [f.runtime]), runtimeError("runtime_unavailable"));
  assert.deepEqual(f.previews, []);
  assert.deepEqual(f.sends, []);
});

test("capability declarations cannot advertise an unimplemented cancel action", () => {
  const f = fixture();
  assert.throws(() => createAgentRuntime({
    ...f.driver,
    descriptor: { ...f.driver.descriptor, capabilities: { ...f.driver.descriptor.capabilities, cancel: true } },
  }), runtimeError("invalid_capabilities"));
});
