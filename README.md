# 幻月 / Paraselene

更新：2026-10-12。当前产品：Windows 小说创作客户端。桌宠不再是默认入口，其他功能线暂停排期。

2026-10-13 接线更新：原生默认入口已使用 SQLite 正式作品，支持新建/切章、正文与资料保存、持久讨论草稿和版本操作；浏览器仍为独立预览。当前 B 原生恢复验收进行中，真实模型与安装版未完成，不宣称最低可用通过。详见 [B证据](docs/evidence/CLIENT-MVP-B-20261013.md)，下列2026-10-12预览说明为此前界面能力。

目标是把 AI 写小说和 Agent 编辑器的工作方式结合：章节与设定目录、中央正文、段落下的讨论与修订；从人物、地点、世界规则一路点击回到原文。

## 现在可以看什么

- 默认前端 `src/features/studio/StudioApp.tsx → writing/NotebookApp.tsx`：浅灰外框、暖白正文、本地中文字体；章节编辑/新建/改名、预览自动保存、人物与世界设定编辑、地图位置调整、出处跳转、专注与目录折叠、Markdown/JSON 导出。
- 共写贴在目标段落之后，一次展开一处；讨论、候选、版本可切换，每处独立保留草稿与引用快照。原稿留在正文，候选可对比、采纳、拒绝、撤销；资料用临时卡片深入。全章讨论由作者打开底部抽屉。
- 独立设计入口 `?design=paragraph`：20 章合成作品、长标题和长章节，安静写作／段落共写／资料引用三个可操作场景，不读写现有预览。
- 目录底部“项目框架与进度”：展示当前模块与接下来的三步；完整说明见 [项目框架](docs/engineering/project-map.md)。
- 预览使用虚构的《雾海来信》，数据只写入独立 localStorage。AI 指令暂存在当前会话，回复与修改示例不是模型生成。正式 SQLite 作品尚未接入新界面。
- 已有小说内核保留：按章目录、working copy、确认稿版本树、patch、设定/出处与外发预览。历史测试见看板，本次没有把它们重新宣称为完整验收。

## 本机预览

在 `D:\MyAgent\paraselene-work`，使用 PowerShell 7：

```powershell
pnpm dev
```

默认浏览器入口就是小说工作台。若 pnpm 因 node_modules junction 的 realpath 权限失败，可直接运行已安装工具：

```powershell
node node_modules/vite/bin/vite.js --configLoader runner --host 127.0.0.1
```

本轮构建产物预览：`http://127.0.0.1:1422/`（仅本机；服务停止后需重新启动）。

```powershell
node node_modules/vite/bin/vite.js build --configLoader runner
node node_modules/vite/bin/vite.js preview --host 127.0.0.1 --port 1422
```

## 接下来只做三步

下一轮按 [客户端最低可用计划](docs/novel/client-mvp-plan-20261012.md) 收口：先审查具体缺陷，再依次完成原生交互、正式保存、真实共写与安装版验收。当前合成场景的前端通过不等于客户端最低可用。

1. 前端体验：本轮交付可操作预览；根据实际创作反馈修正信息布局。
2. 接已有内核：作品选择/新建、SQLite 编辑稿、真实 DeepSeek、外发预览、候选 patch 与明确确认稿。
3. 引用闭环：人物/世界规则/地点与原文版本绑定，引用失效可见，Agent 使用作者选定的资料。

桌宠、Python 教学、主动提醒、复杂自动推演和百万字最终性能验收退出当前排期。旧实现与资料保留。

新 Agent 先读 [AGENTS.md](AGENTS.md)、[当前方向](docs/development-direction.md)、[进度看板](docs/progress-checkpoint.md)、[项目地图](docs/engineering/project-map.md)、[代码规范](docs/engineering/code-standards.md)。参考见 [开源客户端研究](docs/novel/frontend-references-20261012.md)与[文档中心设计](docs/design-concepts/正文与Agent联动设计.md)，当前验证见 [段落共写交付](docs/evidence/PARAGRAPH-UI-20261012.md)。Windows 原生 IME 完整操作尚未验收。

仅修改工作副本；未向 `D:\paraselene` 同步，未发布或提交私人作品。
