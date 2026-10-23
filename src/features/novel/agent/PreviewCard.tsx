// 外发预览卡片。规则（project-map §3）与契约见下方 PreviewCard 的文档注释。

import type { IssuedPreview } from "../contracts";

/**
 * 外发预览卡片：原样展示后端签发的一次性预览（模型、估算 token、消息体）。
 *
 * 契约（project-map §3）：UI 只能展示后端返回的 preview，不能伪造或截断外发内容；
 * `estimate` 为 true 时额外显示 token 估算，提示用户确认发送的成本。
 * 确认回调由父组件负责，本组件是纯展示 + 一个确认按钮。
 */
export function PreviewCard(props: {
  title: string;
  preview: IssuedPreview;
  estimate?: boolean;
  confirmLabel: string;
  busy: boolean;
  onConfirm: () => void;
}) {
  return <div className="novel-ai-preview">
    <h5>{props.title} · {props.preview.prepared.model}</h5>
    {props.estimate && <p>估算约 {props.preview.prepared.estimated_tokens} token。确认后才发送给 DeepSeek。</p>}
    <div className="novel-ai-messages">{props.preview.prepared.messages.map((message, index) => <section key={index}>
      <strong>{message.role === "system" ? "规则与已确认约束" : "已确认参考与本次要求"}</strong><pre>{message.content ?? ""}</pre>
    </section>)}</div>
    <button className="primary" type="button" disabled={props.busy} onClick={props.onConfirm}>{props.confirmLabel}</button>
  </div>;
}
