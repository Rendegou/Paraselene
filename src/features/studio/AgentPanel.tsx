import { useState } from "react";
import type { AgentMessage, PanelTab, PendingChange, SourceReference } from "./model";
import { StudioIcon } from "./StudioIcon";

interface PanelProps {
  tab: PanelTab; setTab: (tab: PanelTab) => void; references: SourceReference[];
  messages: AgentMessage[]; selectionText: string; pending: PendingChange | null;
  onSend: (text: string) => void; onReference: (id: string) => void;
  apply: () => void; reject: () => void; close: () => void;
}

/** 引用条目按钮：图标 + 标题的紧凑跳转 chip，点击回调到来源正文。 */
function ReferenceLink({ reference, onReference }: { reference: SourceReference; onReference: (id: string) => void }) {
  return <button type="button" className="reference-chip" onClick={() => onReference(reference.id)}><StudioIcon name="link" size={13} />{reference.title}<StudioIcon name="arrow" size={12} /></button>;
}

/** 会话页：消息流（含引用 chip）、待审修改入口、快捷起手建议、选段上下文与输入区。 */
function AgentConversation(props: PanelProps) {
  const [input, setInput] = useState("");
  return <><div className="agent-conversation">
    <div className="agent-task-heading"><span className="agent-avatar"><StudioIcon name="pen" size={17} /></span><div><strong>一起写这一章</strong><p>先讨论，再修改。</p></div></div>
    {props.messages.map((message) => <article key={message.id} className={`agent-message ${message.role}`}>
      <span className="message-role">{message.role === "user" ? "你" : "幻月 · 演示回复"}</span>
      <p>{message.body}</p>
      {message.references && <div className="message-references">{message.references.map((id) => {
        const reference = props.references.find((item) => item.id === id);
        return reference ? <ReferenceLink key={id} reference={reference} onReference={props.onReference} /> : null;
      })}</div>}
    </article>)}
    {props.pending && <button type="button" className="agent-change-link" onClick={() => props.setTab("changes")}><StudioIcon name="changes" /><span>一处修改待审阅<small>查看原文与新文本</small></span><StudioIcon name="arrow" size={16} /></button>}
    <div className="agent-suggestions"><span>试试这样开始</span>
      {["保留悬念，续写一小段", "让人物的动作更克制"].map((text) => <button type="button" key={text} onClick={() => { setInput(text); }}>{text}<StudioIcon name="plus" size={13} /></button>)}
    </div>
    <div className="agent-context"><span>本章相关资料</span><div>{props.references.map((reference) => <ReferenceLink key={reference.id} reference={reference} onReference={props.onReference} />)}</div></div>
  </div>
  <form className="agent-composer" onSubmit={(event) => { event.preventDefault(); if (!input.trim()) return; props.onSend(input.trim()); setInput(""); }}>
    {props.selectionText && <div className="selection-context"><StudioIcon name="file" size={13} /><span>已引用选段 · {props.selectionText.length} 字</span></div>}
    <label className="sr-only" htmlFor="agent-prompt">与幻月讨论</label>
    <textarea id="agent-prompt" value={input} onChange={(event) => setInput(event.target.value)} placeholder="描述你想改的地方…" rows={3} />
    <div className="composer-bottom"><span>交互演示 · 未连接模型</span><button type="submit" disabled={!input.trim()} aria-label="发送消息" title="发送消息"><StudioIcon name="arrow" size={17} /></button></div>
  </form></>;
}

/** 修改审阅页：无候选时理念空态；有候选时展示前后对照并允许应用/拒绝。 */
function ChangeReview({ pending, apply, reject }: Pick<PanelProps, "pending" | "apply" | "reject">) {
  if (!pending) return <div className="panel-empty"><StudioIcon name="changes" size={28} /><h2>每次修改，由你决定</h2><p>在 Agent 中提出要求，候选会先出现在这里。正文不会被自动覆盖。</p></div>;
  return <div className="change-review"><div className="change-heading"><h2>审阅修改</h2><span>1 处 · 演示候选</span></div>
    <p className="change-instruction">{pending.instruction}</p>
    <div className="diff-original"><span>修改前</span><p>{pending.before || "此处为正文结尾，将新增一段。"}</p></div>
    <div className="diff-proposed"><span>修改后</span><p>{pending.after}</p></div>
    <p className="change-note">应用到本机体验稿，可立即撤销。</p>
    <div className="change-actions"><button className="studio-button" type="button" onClick={reject}>拒绝修改</button><button className="studio-primary" type="button" onClick={apply}><StudioIcon name="check" size={15} />应用修改</button></div>
  </div>;
}

/** 引用列表页：全部来源条目卡片，点击打开出处正文。 */
function ReferencesPanel({ references, onReference }: Pick<PanelProps, "references" | "onReference">) {
  return <div className="references-panel"><h2>沿着引用，找回依据</h2><p className="panel-intro">人物为什么这样做，伏笔从哪里开始。点击打开来源正文。</p>
    {references.map((reference) => <article key={reference.id} className="source-entry"><div><StudioIcon name="link" size={15} /><h3>{reference.title}</h3></div><blockquote>{reference.quote}</blockquote><p>{reference.note}</p><button type="button" onClick={() => onReference(reference.id)}>打开出处<StudioIcon name="arrow" size={14} /></button></article>)}
  </div>;
}

/** Agent 面板容器：tab 页签（Agent/修改/引用）+ 对应页内容，修改页在有候选时显示计数。 */
export function AgentPanel(props: PanelProps) {
  return <aside className="studio-agent" aria-label="Agent 与引用面板">
    <div className="agent-panel-heading"><div role="tablist" aria-label="Agent 面板">
      {(["agent", "changes", "references"] as PanelTab[]).map((tab) => <button key={tab} type="button" role="tab"
        aria-selected={props.tab === tab} aria-controls={`panel-${tab}`} id={`tab-${tab}`} className={props.tab === tab ? "selected" : ""} onClick={() => props.setTab(tab)}>
        {{ agent: "Agent", changes: "修改", references: "引用" }[tab]}{tab === "changes" && props.pending && <span className="tab-count">1</span>}</button>)}
    </div><button className="icon-button" type="button" onClick={props.close} aria-label="收起 Agent 面板"><StudioIcon name="panel" size={17} /></button></div>
    <section className="agent-panel-body" role="tabpanel" id={`panel-${props.tab}`} aria-labelledby={`tab-${props.tab}`}>
      {props.tab === "agent" && <AgentConversation {...props} />}
      {props.tab === "changes" && <ChangeReview pending={props.pending} apply={props.apply} reject={props.reject} />}
      {props.tab === "references" && <ReferencesPanel references={props.references} onReference={props.onReference} />}
    </section>
  </aside>;
}
