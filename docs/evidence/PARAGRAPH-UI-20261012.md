# UI-01C：安静写作，段落共写

2026-10-12。工作副本 `D:\MyAgent\paraselene-work`。状态 **FRONTEND_PASS / NATIVE_INPUT_NOT_RUN**。按用户明确批准方案实施，不读写正式 SQLite，不接真实模型，不向原仓库同步。

## 交付与入口

先交付同一 React / CodeMirror 6 编辑器的三个独立可操作场景，经 fresh Impeccable finish reviewer 复核并修正资料卡越界和文字对比度，再迁移默认工作台。

- 默认：`http://127.0.0.1:1422/`，`StudioApp.tsx → writing/NotebookApp.tsx`。
- 独立评审：`http://127.0.0.1:1422/?design=paragraph`，20 章、长标题、4,040 字合成章节、人物与讨论记录。初始化克隆固定 fixture，不访问现有预览存储，不注册跨窗口存储监听，保存明确标注会话有效。
- 原侧栏界面完整保留为 `SidebarWorkbench.tsx`，退出活动导入链；旧试稿与已有业务组件保留。

## 视觉与交互

浅灰外框、暖白正文、单一墨蓝；240px 目录、760/920px 阅读宽度；顶栏只保留作品名与一个保存状态、版式、专注、全章讨论、导出。正文 Noto Serif SC 20px / 1.85，工具 Noto Sans SC 14px，辅助文字至少 12px，标题桌面32px、窄屏27px。四个本地 WOFF2、OFL 许可证与资产来源说明均已打包。

默认没有常驻共写区。一次只在目标最后一个段落之后展开线程；每处保存草稿、资料快照、请求、候选和会话修订。讨论不进入正文；候选下方阅读、对比按需开启。采纳要求整章正文快照精确匹配，作者决定采纳或拒绝；CodeMirror 历史支持撤销。全章任务及失效选段使用主动打开的底部抽屉。

块级 Decoration 由 StateField 直接提供，React Portal 使用稳定挂载点；草稿输入不会重建编辑器。不可变生成快照与事务映射显示锚点分开，删除后保留历史，不搜索相似句补位置。资料卡桌面就近浮出，统一高度和定位上限，中部滚动、底部动作固定；窄屏在共写区域内展开。关闭恢复草稿光标，出处只允许唯一精确匹配。

## 实际视觉检查

九图均来自最终真实 React 构建，DOM 视口分别为1440×900、1280×800、414×681；页面缩放1、实际字体状态 `data-local-fonts=ready`。曾遇浏览器缩放110%造成截图白边，已恢复100%并重新导出。

- [安静写作：1440](PARAGRAPH-20261012-quiet-desktop.jpg)、[1280](PARAGRAPH-20261012-quiet-1280.jpg)、[414](PARAGRAPH-20261012-quiet-narrow.jpg)
- [段落共写：1440](PARAGRAPH-20261012-cowrite-desktop.jpg)、[1280](PARAGRAPH-20261012-cowrite-1280.jpg)、[414](PARAGRAPH-20261012-cowrite-narrow.jpg)
- [资料引用：1440](PARAGRAPH-20261012-reference-desktop.jpg)、[1280](PARAGRAPH-20261012-reference-1280.jpg)、[414](PARAGRAPH-20261012-reference-narrow.jpg)
- [实际交付预览](PARAGRAPH-20261012-delivered.jpg)

以用户批准的排版与文档中心布局为裁定合同。第一方参考为 [OpenWriter](https://openwriter.io/) 与 [Novelcrafter 写作界面](https://www.novelcrafter.com/help/docs/write/the-write-interface)。独立 reviewer 查看九图，确认正文拓扑、文字层级、目录密度和控件比例成立，未要求重建布局；其两项视觉必修已复验解决：桌面卡片 footer 可达，选中文字对比度合格。`#49659c / #e8edf5` 4.928:1，白色主按钮文字 5.793:1。

检测器按技能执行一次，结果 `[]`，没有把它当视觉验收。最终文档由 fresh documenter 更新 DESIGN.md、PRODUCT.md 与 `.impeccable/design.json`；文档完成后的额外 reviewer 收尾尝试因模型容量未运行，不冒称该额外轮次通过。

## 命令验证

PowerShell 7、已安装工具直接执行，全部下列检查退出0：

```powershell
node node_modules/typescript/bin/tsc --noEmit
node node_modules/vite/bin/vite.js build --configLoader runner
node scripts/quality/run-web-tests.mjs
node scripts/quality/code-metrics.mjs --verify docs/engineering/code-metrics-baseline.json --json
node scripts/quality/code-metrics.mjs --ipc-boundary
git diff --check
```

- 最终构建170模块，活动JS495.44KB、gzip162.48KB，无原先>500KB chunk警告；旧窗口仍按需加载。
- 前端行为 **30/30 PASS**；新增5个领域测试覆盖UTF-16/emoji事务映射、删除/撤销锚点、整章过期检查、最小替换及采纳记录/导出隔离。
- TS metrics 基线7、当前7、新增0；没有增加豁免。
- IPC boundary 无违规，仍只允许 `src/lib/ipc.ts` 直接原生调用。
- 字体资产每个覆盖28,124或28,150码点，展示中文样本无缺字；DOM实测加载ready、正文scroller为Notebook Serif。OFL文件存在于 `dist/fonts/`。总字体约17.5MB，罕见汉字/emoji依赖系统fallback，不声称全Unicode覆盖。

## 浏览器行为证据

使用独立1423测试服务与合成内容，未修改1422已有预览的正文。测试服务已停止。

- 中文连续输入和emoji保持线程textarea焦点，草稿不因每次更新卸载；引用卡Escape后回到相同textarea及原光标。
- 两处线程互切只挂载一个panel，各自未发草稿分别恢复；跨段74字选择挂在最后段落之后。
- 候选可编辑、按需显示diff；采纳只改变绑定正文，Ctrl+Z恢复原文，版本保留原稿与采纳记录。拒绝返回讨论；撤销后定位字数读映射的当前原文。
- 在其它正文位置新增文字时旧候选禁用并显示过期说明；撤销该编辑后重新可采纳。
- 10轮讨论panel实测420px，中部clientHeight152 / scrollHeight1442，长记录不拉长整章。
- 原段落稳定性使用实际坐标点击验证：原文top482.958px、paper scrollTop57.333px，收起和重新展开均保持相同。此前locator.click自动将按钮滚到视口中央，造成验收工具假象；实际鼠标操作没有该移动。CodeMirror负责滚动锚点，浏览器自动锚定关闭；选文条随滚动/resize更新，离开视口隐藏。
- 正常默认工作台新章、改名、含emoji正文在刷新后恢复；章节讨论刷新清空。下载Markdown包含已保存章与正文，不包含会话讨论草稿。
- 版式宽稿切换、资料目录、地图地点和完整资料编辑入口可操作；独立设计页面保持无存储覆盖。

## 未运行与交付边界

Windows 原生 Tauri / WebView2 中文IME组成、候选窗、焦点回切与安装后离线完整运行为 **NOT_RUN**；当前工具只可控制浏览器，中文字符串输入不等同系统IME。正式作品、DeepSeek、SQLite接线及正式版本系统仍按原计划留待下一阶段。Rust未变更，未把历史Rust/Tauri通过记录当成本轮端到端验收。共写记录仍为会话级，刷新不恢复。
