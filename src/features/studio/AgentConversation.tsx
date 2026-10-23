import { Icon } from "./Icon";
import type { Studio } from "./useStudio";
import type { Message } from "./types";
import type { locateSource } from "./previewModel";
interface Props {
  studio: Studio;
  example: ReturnType<typeof locateSource>;
  quote: string;
  messages: Message[];
  demonstrateChange: () => void;
}
/**
 * Agent 会话内容（预览版）：欢迎语、示例审阅消息（含引用 chip）、
 * 修改审阅演示入口与历史消息流。内容为体验作品示例数据，不连接模型。
 */
export function AgentConversation({
  studio,
  example,
  quote,
  messages,
  demonstrateChange,
}: Props) {
  return (
    <>
      <div className="studio-agent-intro">
        <span className="studio-agent-avatar">
          <Icon name="spark" size={21} />
        </span>
        <h2>和故事一起，向深处走。</h2>
        <p>选一段正文，带上人物与设定，讨论下一步。修改先审阅，再由你决定。</p>
      </div>
      <div className="studio-sample-message">
        <div>
          <strong>一次创作审阅</strong>
          <span>示例</span>
        </div>
        <p>
          让沈砚的对白保留一点试探，比直接解释动机更适合这次会面。林雾的反应则可以继续落在细节上。
        </p>
        <div className="studio-citation-chips">
          <button type="button" onClick={() => studio.openEntity("shen")}>
            <Icon name="people" size={13} />
            沈砚
          </button>
          <button type="button" onClick={() => studio.openEntity("lin")}>
            <Icon name="people" size={13} />
            林雾
          </button>
        </div>
        {example && (
          // 示例消息附带的出处跳转：定位到示例引用的章节并高亮 quote。
          <button
            type="button"
            className="studio-source-inline"
            onClick={() => studio.openSource(example.chapter.id, quote)}
          >
            <Icon name="link" size={13} />
            {example.chapter.title}
            <Icon name="arrow" size={13} />
          </button>
        )}
      </div>
      <button
        className="studio-demo-action"
        type="button"
        onClick={demonstrateChange}
      >
        <Icon name="layers" size={16} />
        {studio.selection ? "审阅选段替换" : "体验修改审阅"}
        <Icon name="arrow" size={15} />
      </button>
      {messages.map((message) => (
        <div key={message.id} className={`studio-message ${message.role}`}>
          <small>{message.role === "author" ? "你" : "预览状态"}</small>
          <p>{message.text}</p>
        </div>
      ))}
    </>
  );
}
