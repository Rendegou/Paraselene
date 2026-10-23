# UI-01B 正文与共写联动验收

日期：2026-10-12。负责人：codex/document-cowrite-20261012。状态：FRONTEND_PASS。用户认可 document-agent-linkage 草图并授权改活动前端；工作仅在 D:\MyAgent\paraselene-work。

## 完成范围

- 默认 StudioApp React 工作台替换为一个浅色目录、暖白正文、浅色本章共写及深灰顶部工具栏。
- 当前章节的讨论、未发指令、引用资料与候选隔离。作者显式固定选段；引用保留章节/UTF-16 范围/原文/完整正文快照。
- 资料旁看保持编辑器挂载与滚动位置；相关资料可继续点击深入，带入时在请求中保存资料快照。
- 编辑器内讨论标记、原文划线与候选文字；候选 Decoration 不属于正文内容。采纳/拒绝、正文撤销、过期保护。
- 窄窗口上下布局；审阅原文与候选并列、决策按钮固定底部；目录在进入中等/窄窗口时收起。
- 搜索、新章、改名、新人物/规则/地点、完整资料编辑、地图、导出、专注和折叠保留。菜单 Escape/焦点移出关闭。

主要修改：src/features/studio/{StudioApp,Sidebar,StudioTopbar,AgentPane,AgentComposer,ProjectFramework,NewEntityMenu}.tsx、useStudio.ts、useStudioNavigation.ts、menuDismiss.ts、cowrite/、editor/{ManuscriptEditor,cowriteAnnotations}.ts(x)、三个活动 CSS 文件。没有新增依赖或改 Rust/IPC。

## 命令与结果

均使用 PowerShell 7，在工作副本执行。

- node node_modules/typescript/bin/tsc --noEmit：退出 0。
- node node_modules/vite/bin/vite.js build --configLoader runner：最终退出 0，149 modules transformed。node_modules 为既有 junction，沙箱构建首次因 CJS require 解析失败；正常权限下同命令构建成功。未改依赖或配置绕过。
- node scripts/quality/run-web-tests.mjs：退出 0，25/25。新增 4 项针对冻结范围、UTF-16、伪造/过期引用、资料快照与候选绑定；原有保存冲突/损坏、出处歧义、精确采纳与导出测试通过。新增用例首次因测试字符串长度写错失败，改成 body.length 后通过。
- node scripts/quality/code-metrics.mjs --verify docs/engineering/code-metrics-baseline.json：退出 0，基线 7/当前 7，无新增债务。共写视图 hook 单独拆分，未放宽阈值。
- node scripts/quality/code-metrics.mjs --ipc-boundary：退出 0，无越界调用。
- Prettier 3.6.2 格式化本轮源码；未改变依赖锁。
- 本轮未改原生代码，未重复原生编译/全量 Rust 测试。Windows 原生 WebView2 的本轮交互验收 NOT_RUN。

## 浏览器行为

使用独立本机 1423 端口合成作品执行写入验收，避开用户 1422 预览的保存空间。生产构建由 Vite preview 服务。

- 人物“沈砚”在页边区打开；正文文本与滚动位置未变化。带入讨论后原指令仍在；记录请求包含冻结选段和 1 项资料快照。
- 准备示例：原位同时显示“你还是来了。”与“我猜你会来。”。正文输入一个新字后采纳禁用、候选 Decoration 为 0；撤销该字后候选恢复可采纳。
- 采纳只替换目标句；正文撤销回原句，其余段落保持。
- 定位请求原文 → 讨论这段 → 移动光标：共写目标仍为第5段/8字。
- 第三章草稿“第三章未发草稿”与候选保留；第二章显示自己的全章讨论，没有第三章请求/候选；第二章输入独立草稿后回第三章，其草稿恢复。
- 新建设定菜单可 Escape 关闭，新建规则进入可编辑资料；新章/改名/中文编辑保留。待保存状态变成“已保存到此设备 · 预览”后刷新，重新打开“验收章 · 独立测试”，正文仍为“这是独立预览的保存验收。”；未改变 1422 用户预览。
- 最终构建回归：从宽窗口切到 414px 自动收起目录；拒绝后候选 Decoration 为 0；共写折叠后正文宽 414px，页边区 display:none。所有临时视口覆盖已恢复。
- Ctrl + 点击正文“沈砚”打开页边资料，正文编辑器数量仍为 1。独立 QA 页与 1423 服务已关闭；新版 1422 工作台单独打开并保留供用户体验，未重载原有未发草稿页面。[实际打开页](NOVEL-COWRITE-20261012-live.jpg)。
- 1280 × 800：三栏，无横向溢出；414 × 681：正文 y=52..376.73，共写 y=376.73..653.33，无重叠和横向溢出；定位后原句 y=245..262，采纳固定在底部 y=604.67..653.33，均可见。
- 截图为实际 JPEG：[宽窗口](NOVEL-COWRITE-20261012-desktop.jpg)、[窄窗口](NOVEL-COWRITE-20261012-narrow.jpg)。

## 限制与下一动作

REAL：前端编辑、独立预览保存、旁看与引用、章级会话隔离、原位候选与手工采纳撤销。
SIMULATED：固定对白的示例候选；未生成 AI 回复，也未调用模型。
PLANNED：当前 UI 接正式 SQLite 作品、working copy/确认版本、真实 DeepSeek 外发预览和 patch。

共写草稿/请求/候选仅当前会话有效，刷新不恢复；正文与设定独立预览保存照常。长篇/原生 IME/安装包不在本轮验收。下一动作沿用 UI-02，不新增路线图。
