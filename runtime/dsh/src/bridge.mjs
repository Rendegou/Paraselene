import { createUserMessage } from "@deepseek-ai/dsh-llm";
import { SessionId } from "@deepseek-ai/dsh-session";
import { MAX_LINE_BYTES, PROTOCOL_VERSION, ProtocolError, parseCommand } from "./protocol.mjs";

export const name = "paraselene-offline-bridge";
export const inject = ["agents", "appReady", "appExit"];

/** Drive one owned dsh activity at a time. This fixture-only bridge is not exposed to the product UI. */
export function apply(ctx) {
  const exit = ctx.get("appExit");
  let active;
  let closed = false;
  let pending = "";
  const usedIds = new Set();
  const emit = event => {
    if (!process.stdout.destroyed) process.stdout.write(`${JSON.stringify({ version: PROTOCOL_VERSION, ...event })}\n`);
  };
  const reject = (error, requestId) => emit({
    type: "error", ...(requestId ? { requestId } : {}),
    code: error instanceof ProtocolError ? error.code : "RUNTIME_ERROR",
    message: error instanceof ProtocolError ? error.message : "The offline runtime failed",
  });

  async function run(command) {
    if (closed) { reject(new ProtocolError("CLOSED", "Runtime is closing"), command.requestId); return; }
    if (active) { reject(new ProtocolError("BUSY", "Another request is active"), command.requestId); return; }
    if (usedIds.has(command.requestId)) {
      reject(new ProtocolError("DUPLICATE_ID", "Request identifiers cannot be reused"), command.requestId); return;
    }
    usedIds.add(command.requestId);
    const activity = { requestId: command.requestId, cancelled: false, abort: new AbortController(), handle: undefined, done: undefined };
    active = activity;
    activity.done = (async () => {
      let terminal;
      try {
        const handle = await ctx.agents.create({
          sessionId: SessionId(`paraselene-${command.requestId}`),
          agentOptions: { provider: "paraselene-offline", model: "simulated" },
          signal: activity.abort.signal,
        });
        activity.handle = handle;
        if (activity.cancelled) {
          terminal = { type: "done", outcome: "cancelled" };
        } else {
          emit({ type: "started", requestId: command.requestId, scope: command.scope, modelMode: "SIMULATED" });
          handle.agent.followup(createUserMessage({
            content: [{ type: "text", text: command.prompt }], source: { kind: "user" },
          }));
          await handle.agent.whenIdle();
          const ending = handle.agent.session.snapshotEvents().findLast(event => event.type === "turn/end");
          if (activity.cancelled && ending?.data.reason.kind === "aborted") {
            terminal = { type: "done", outcome: "cancelled" };
          } else if (ending?.data.reason.kind === "completed") {
            terminal = { type: "done", outcome: "completed" };
          } else {
            terminal = { type: "error", code: "TURN_FAILED", message: "The offline turn did not complete" };
          }
        }
      } catch (error) {
        terminal = activity.cancelled
          ? { type: "done", outcome: "cancelled" }
          : { type: "error", code: "RUNTIME_ERROR", message: "The offline runtime failed" };
      } finally {
        try { await activity.handle?.dispose(); }
        catch { terminal = { type: "error", code: "DISPOSE_FAILED", message: "The offline activity did not dispose" }; }
        if (active === activity) active = undefined;
        // Completion follows disposal, so no live agent can emit after its terminal frame.
        emit({ ...terminal, requestId: command.requestId });
      }
    })();
    await activity.done;
  }

  function cancel(requestId) {
    if (!active || active.requestId !== requestId) {
      reject(new ProtocolError("NOT_RUNNING", "No matching active request"), requestId); return;
    }
    active.cancelled = true;
    active.abort.abort(new Error("Cancelled by the bridge client"));
    active.handle?.agent.cancel({ kind: "user" });
  }

  const stop = async () => {
    closed = true;
    if (active) { cancel(active.requestId); await active?.done; }
  };
  const accept = line => {
    let command;
    try { command = parseCommand(line); }
    catch (error) { reject(error); return; }
    if (command.type === "run") { void run(command); return; }
    if (command.type === "cancel") { cancel(command.requestId); return; }
    closed = true;
    void stop().finally(() => { exit(0); });
  };
  const onData = chunk => {
    if (closed) return;
    pending += chunk;
    let newline;
    while ((newline = pending.indexOf("\n")) !== -1) {
      const line = pending.slice(0, newline);
      pending = pending.slice(newline + 1);
      accept(line);
    }
    if (Buffer.byteLength(pending, "utf8") > MAX_LINE_BYTES) {
      reject(new ProtocolError("INPUT_TOO_LARGE", "Command exceeds the input limit"));
      pending = "";
      closed = true;
      void stop().finally(() => { exit(1); });
    }
  };
  const onEnd = () => { void stop().finally(() => { exit(0); }); };
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", onData);
  process.stdin.once("end", onEnd);
  ctx.on("agent/assistant-stream", ({ agent, frame }) => {
    if (active?.handle?.agent !== agent || frame.type !== "chunk" || frame.chunk.type !== "text-delta") return;
    emit({ type: "delta", requestId: active.requestId, content: frame.chunk.text });
  });
  ctx.appReady.onReady(() => emit({ type: "ready", runtime: "dsh", runtimeVersion: "0.2.1-rc.2", modelMode: "SIMULATED" }));
  ctx.effect(() => async () => {
    process.stdin.off("data", onData);
    process.stdin.off("end", onEnd);
    process.stdin.pause();
    process.stdin.destroy();
    await stop();
  }, "paraselene-bridge.stdio");
}
