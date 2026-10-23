import { Icon } from "./Icon";

// 框架页展示的模块清单：面向协作者说明各目录职责与状态，纯静态内容。
const modules = [
  {
    path: "src/features/studio/",
    title: "小说创作前端",
    description:
      "正文优先，讨论挂在选段之后：独立草稿、引用快照、候选与会话修订。资料按需查看，预览数据独立保存。",
    status: "本轮实现",
    files: [
      "StudioApp.tsx → writing/NotebookApp.tsx · 页面组合",
      "writing/ParagraphEditor.tsx · CodeMirror 与段下区域",
      "writing/threadModel.ts · 段落线程 / 候选 / 会话修订",
      "EntityDetail.tsx + WorldMap.tsx · 故事资料",
      "previewModel.ts + previewStorage.ts · 预览契约与保存",
    ],
  },
  {
    path: "src/features/novel/",
    title: "已有小说业务",
    description:
      "保留自动保存、正稿版本、patch 审阅与设定出处。下一步把这些真实业务接入新前端。",
    status: "已有实现",
    files: [
      "state/ · 按章读取与自动保存",
      "diff/ · 版本绑定的修改审阅",
      "lore/ · 设定与出处",
      "agent/ · 外发预览与生成",
    ],
  },
  {
    path: "src/lib/ipc.ts → src-tauri/",
    title: "原生桥接",
    description:
      "前端唯一 IPC 入口。Tauri 负责窗口、权限与命令转发，界面不直接操作数据库。",
    status: "已有实现",
    files: [
      "lib/ipc.ts · 类型与原生调用",
      "src-tauri/src/commands/ · 薄命令层",
    ],
  },
  {
    path: "crates/",
    title: "可复用内核",
    description:
      "SQLite 仍是正式作品的权威存储。纯 Rust 核心保留，浏览器预览不写入旧数据库。",
    status: "已有实现",
    files: [
      "memory-core/ · SQLite、版本与出处",
      "novel-core/ · 生成上下文与安全 patch",
      "llm-core/ · DeepSeek、SSE 与外发票据",
    ],
  },
];

/** 项目框架页：当前阶段路线（现在/接下来/随后）、代码模块地图与外部界面参考链接。 */
export function ProjectFramework() {
  return (
    <article className="studio-framework">
      <div className="studio-page-heading">
        <div>
          <h1>先把创作工作台做好。</h1>
          <p>只围绕小说推进，每一步都有能操作的结果。</p>
        </div>
        <Icon name="layers" size={28} />
      </div>
      <div className="studio-milestones">
        <div>
          <strong>现在</strong>
          <h2>看得见，写得下</h2>
          <p>正文与共写已联动；先用虚构素材核对操作。</p>
        </div>
        <div>
          <strong>接下来</strong>
          <h2>接通已有内核</h2>
          <p>作品入口、SQLite 保存、真实 AI 与修改审阅。</p>
        </div>
        <div>
          <strong>随后</strong>
          <h2>让引用可追溯</h2>
          <p>人物、场景与世界规则关联到版本原文。</p>
        </div>
      </div>
      <h2 className="studio-section-heading">当前代码框架</h2>
      <div className="studio-module-list">
        {modules.map((module) => (
          <section key={module.path}>
            <div>
              <h3>{module.title}</h3>
              <span>{module.status}</span>
            </div>
            <code>{module.path}</code>
            <p>{module.description}</p>
            <ul>
              {module.files.map((file) => (
                <li key={file}>{file}</li>
              ))}
            </ul>
          </section>
        ))}
      </div>
      <div className="studio-framework-note">
        <Icon name="focus" size={19} />
        <p>
          桌宠、Python
          教学、主动提醒与复杂自动推演已退出当前开发范围。旧代码保留，旧计划不再作为本轮排期。
        </p>
      </div>
      <h2 className="studio-section-heading">界面参考</h2>
      <div className="studio-research-links">
        <a
          href="https://github.com/steven-tey/novel"
          target="_blank"
          rel="noreferrer"
        >
          Novel <span>选文与 AI 操作</span>
          <Icon name="arrow" size={16} />
        </a>
        <a
          href="https://github.com/toeverything/AFFiNE"
          target="_blank"
          rel="noreferrer"
        >
          AFFiNE <span>文档与空间资料</span>
          <Icon name="arrow" size={16} />
        </a>
        <a
          href="https://novelwriter.io/docs/usage/tags_and_references.html"
          target="_blank"
          rel="noreferrer"
        >
          novelWriter <span>小说元素与正文引用</span>
          <Icon name="arrow" size={16} />
        </a>
      </div>
    </article>
  );
}
