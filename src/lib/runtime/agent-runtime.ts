import type {
  AgentRuntime, ChatRequest, IssuedPreview, LlmStreamEvent,
  RuntimeDescriptor, RuntimeId, RuntimePreview,
} from "./contracts";

export type RuntimeErrorCode = "runtime_unavailable" | "invalid_preview" | "invalid_capabilities";

/** 可按 code 分类；消息不包含请求正文或底层凭据。 */
export class RuntimeError extends Error {
  constructor(readonly code: RuntimeErrorCode, message: string) {
    super(message);
    this.name = "RuntimeError";
  }
}

/** 平台传输由 IPC 层注入；实际请求仍由后端票据决定。 */
export interface RuntimeDriver {
  readonly descriptor: RuntimeDescriptor;
  preview(request: ChatRequest): Promise<IssuedPreview>;
  send(previewId: string, onEvent: (event: LlmStreamEvent) => void): Promise<void>;
  listModels(): Promise<string[]>;
  cancel?(runId: string): Promise<void>;
}

function freezeSnapshot<T>(value: T, seen = new WeakSet<object>()): T {
  if (value && typeof value === "object" && !seen.has(value)) {
    seen.add(value);
    for (const child of Object.values(value)) freezeSnapshot(child, seen);
    Object.freeze(value);
  }
  return value;
}

/**
 * 把平台驱动包装为幻月接口。预览对象绑定当前实例，调用 send 前先消费，
 * 避免跨引擎错投、双击重发，以及传输失败后不确定的自动重试。
 * 这只是界面侧误用保护，不能替代受信后端的一次性票据和空间授权。
 */
export function createAgentRuntime(driver: RuntimeDriver): AgentRuntime {
  if (driver.descriptor.capabilities.cancel !== (typeof driver.cancel === "function")) {
    throw new RuntimeError("invalid_capabilities", "取消能力与运行时接口不一致");
  }
  const descriptor = freezeSnapshot(structuredClone(driver.descriptor));
  const issued = new WeakMap<RuntimePreview, string>();
  const runtime: AgentRuntime = {
    descriptor,
    async preview(request) {
      const result = await driver.preview(request);
      // 拷贝后再冻结，防止驱动复用或修改对象，造成界面显示与已签发内容漂移。
      const preview: RuntimePreview = freezeSnapshot({
        runtimeId: descriptor.id,
        id: result.id,
        prepared: structuredClone(result.prepared),
      });
      issued.set(preview, result.id);
      return preview;
    },
    async send(preview, onEvent) {
      const token = issued.get(preview);
      if (token === undefined || preview.runtimeId !== descriptor.id) {
        throw new RuntimeError("invalid_preview", "预览已失效或不属于当前运行时，请重新预览");
      }
      issued.delete(preview);
      await driver.send(token, onEvent);
    },
    listModels: () => driver.listModels(),
    ...(driver.cancel ? { cancel: (runId: string) => driver.cancel!(runId) } : {}),
  };
  return Object.freeze(runtime);
}

/** 显式选择不存在的运行时会失败，绝不静默切换到另一个引擎。 */
export function requireAgentRuntime(id: RuntimeId, runtimes: readonly AgentRuntime[]): AgentRuntime {
  const runtime = runtimes.find((candidate) => candidate.descriptor.id === id);
  if (!runtime) throw new RuntimeError("runtime_unavailable", "请求的运行时尚未接入");
  return runtime;
}
