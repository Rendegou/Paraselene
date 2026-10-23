import { createAgentRuntime } from "./agent-runtime";
import type { AgentRuntime, ChatRequest, IssuedPreview, LlmStreamEvent } from "./contracts";

/** 现有原生 IPC 的三个动作；依赖从 ipc.ts 注入，测试不需要 WebView。 */
export interface LegacyLlmTransport {
  preview(request: ChatRequest): Promise<IssuedPreview>;
  send(previewId: string, onEvent: (event: LlmStreamEvent) => void): Promise<void>;
  listModels(): Promise<string[]>;
}

/** 保留 Rust 的预览/密钥/云开关逻辑，不宣称已具备 Agent 调度和取消能力。 */
export function createLegacyRustRuntime(transport: LegacyLlmTransport): AgentRuntime {
  return createAgentRuntime({
    descriptor: {
      id: "legacy-rust",
      capabilities: { cancel: false, toolExecution: false, sessionResume: false },
    },
    preview: (request) => transport.preview(request),
    send: (previewId, onEvent) => transport.send(previewId, onEvent),
    listModels: () => transport.listModels(),
  });
}
