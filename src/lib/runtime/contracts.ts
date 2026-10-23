/** 幻月自己的模型交互契约；不依赖 Tauri、Node 或某个 Agent 引擎。 */
export type Space = "personal" | "idea" | "novel" | "learning";

export interface ToolCallRequest {
  readonly id: string;
  readonly name: string;
  readonly arguments: string;
}

export interface ChatMessage {
  readonly role: "system" | "user" | "assistant" | "tool";
  readonly content: string | null;
  readonly tool_calls?: readonly ToolCallRequest[];
  readonly tool_call_id?: string;
  readonly name?: string;
}

export interface ProviderTool {
  readonly name: string;
  readonly description: string;
  readonly parameters: unknown;
}

/** 用户请求；空间授权仍由实际发送请求的受信后端检查。 */
export interface ChatRequest {
  readonly space: Space;
  readonly messages: readonly ChatMessage[];
  readonly model?: string;
  readonly max_tokens?: number;
  readonly temperature?: number;
  readonly tools?: readonly ProviderTool[];
}

/** 后端准备的可展示快照；发送只使用后端票据，不重新提交这份内容。 */
export interface PreparedChat {
  readonly space: Space;
  readonly messages: readonly ChatMessage[];
  readonly model: string;
  readonly estimated_tokens: number;
  readonly max_tokens?: number;
  readonly temperature?: number;
  readonly tools?: readonly ProviderTool[];
}

/** 原生后端的签发格式，保留现有 IPC 的字段。 */
export interface IssuedPreview {
  readonly id: string;
  readonly prepared: PreparedChat;
}

export interface Usage {
  readonly input_tokens: number;
  readonly output_tokens: number;
}

/** done 表示本次发送完成；模型错误保持 error 事件，传输失败则拒绝 Promise。 */
export type LlmStreamEvent =
  | { readonly type: "delta"; readonly content: string }
  | { readonly type: "tool_calls"; readonly calls: readonly ToolCallRequest[] }
  | { readonly type: "done"; readonly finish_reason: string; readonly usage?: Usage }
  | { readonly type: "error"; readonly kind: string; readonly message: string };

export type RuntimeId = "legacy-rust" | "dsh";

/** 能力只描述已经接通的接口，不能由引擎本身的能力推断。 */
export interface RuntimeDescriptor {
  readonly id: RuntimeId;
  readonly capabilities: {
    readonly cancel: boolean;
    readonly toolExecution: boolean;
    readonly sessionResume: boolean;
  };
}

/** 仅在签发它的适配器实例内有效；不是可跨进程保存的授权凭据。 */
export interface RuntimePreview extends IssuedPreview {
  readonly runtimeId: RuntimeId;
}

/**
 * 构造运行时不启动进程、不联网。preview 只准备预览；send 消费一次性预览。
 * 本接口不接收密钥；底层后端仍负责授权、密钥、请求内容一致性与发送前重检。
 */
export interface AgentRuntime {
  readonly descriptor: RuntimeDescriptor;
  preview(request: ChatRequest): Promise<RuntimePreview>;
  send(preview: RuntimePreview, onEvent: (event: LlmStreamEvent) => void): Promise<void>;
  listModels(): Promise<string[]>;
  /** 只有 capabilities.cancel 为 true 时提供；Promise 完成表示取消已被后端确认。 */
  cancel?(runId: string): Promise<void>;
}
