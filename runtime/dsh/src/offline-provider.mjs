import { setTimeout as delay } from "node:timers/promises";
import { LlmAdapter } from "@deepseek-ai/dsh-llm";

/** Synthetic provider for the M02 probe. It never opens an HTTP connection. */
class OfflineAdapter extends LlmAdapter {
  async *stream(options) {
    options.signal?.throwIfAborted();
    const text = options.messages.flatMap(message => message.content ?? [])
      .filter(block => block.type === "text").map(block => block.text).join(" ");
    yield { type: "block-start", index: 0, blockType: "text" };
    yield { type: "text-delta", index: 0, text: "OFFLINE_" };
    // This fixture gives the real loop an outstanding request to cancel.
    if (text.includes("wait-for-cancel")) await delay(60_000, undefined, { signal: options.signal });
    options.signal?.throwIfAborted();
    yield { type: "text-delta", index: 0, text: "DSH_RESPONSE" };
    yield { type: "block-end", index: 0, block: { type: "text", text: "OFFLINE_DSH_RESPONSE" } };
    yield { type: "finish", reason: { kind: "stop" } };
  }
}

export const name = "paraselene-offline-provider";
export const inject = ["llm"];

/** Register only the synthetic provider; real model transport remains M03 work. */
export function apply(ctx) {
  ctx.llm.registerAdapter(["paraselene-offline"], new OfflineAdapter());
}
