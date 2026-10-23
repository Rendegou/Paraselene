import assert from "node:assert/strict";
import test from "node:test";
import { MAX_LINE_BYTES, parseCommand } from "../src/protocol.mjs";
import { offlineEntries } from "../src/launch.mjs";

const run = { version: 1, type: "run", requestId: "request-1", scope: { space: "personal" }, prompt: "synthetic" };

test("wire rejects unknown spaces, missing novel ownership, credentials and path fields", () => {
  for (const candidate of [
    { ...run, scope: { space: "unknown" } },
    { ...run, scope: { space: "novel" } },
    { ...run, scope: { space: "personal", workId: "work" } },
    { ...run, apiKey: "synthetic-forbidden-field" },
    { ...run, cwd: "synthetic-path" },
    { ...run, scope: { space: "personal", sourcePath: "synthetic-path" } },
  ]) assert.throws(() => parseCommand(JSON.stringify(candidate)));
});

test("wire requires bounded identities, prompt, version and JSON without reflecting rejected input", () => {
  for (const candidate of [
    { ...run, version: 2 }, { ...run, requestId: "../invalid" },
    { ...run, prompt: " " }, { ...run, prompt: "x".repeat(8_193) },
    { ...run, type: "unknown" },
  ]) assert.throws(() => parseCommand(JSON.stringify(candidate)));
  assert.throws(() => parseCommand("x".repeat(MAX_LINE_BYTES + 1)), { code: "INPUT_TOO_LARGE" });
  assert.throws(() => parseCommand("synthetic-private-invalid-json"), error => !error.message.includes("synthetic-private"));
});

test("accepted requests retain explicit scope and cancel only names one request", () => {
  assert.deepEqual(parseCommand(JSON.stringify(run)), run);
  const novel = { ...run, scope: { space: "novel", workId: "work-1" } };
  assert.deepEqual(parseCommand(JSON.stringify(novel)), novel);
  assert.deepEqual(parseCommand('{"version":1,"type":"cancel","requestId":"request-1"}'), { version: 1, type: "cancel", requestId: "request-1" });
});

test("offline composition mounts only the explicit kernel and fixture plugins", () => {
  assert.deepEqual(offlineEntries().map(entry => entry.id), [
    "llm", "session", "session-projection", "system-prompt", "tools", "agent", "agent-loop",
    "paraselene-offline-provider", "paraselene-offline-bridge",
  ]);
  assert.deepEqual(offlineEntries().find(entry => entry.id === "agent-loop").config, { agents: [] });
});
