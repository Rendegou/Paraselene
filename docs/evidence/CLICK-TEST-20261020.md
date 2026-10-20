# 真实点击测试（Computer Use，2026-10-20）

状态：在本机会话内通过独立 MCP 模式驱动 Windows UIA/截图/点击完成一轮真实应用测试。仅操作合成示例库；未读取作者数据/凭据/Key，未发起真实模型请求，未安装或修改 DSH profile。

## 工具调研

目标：在不重启 DSH、不重开会话的前提下，让当前 agent 能真实观察并点击 Windows 应用。

| 候选插件 | 结论 |
|---|---|
| **dsh-computer-use-win 0.5.0** | **采用**。Windows 原生：UIA 树、OCR、截图、鼠标/键盘、窗口管理；peer 依赖与当前 DSH `0.1.0-rc.6` 匹配；支持独立 MCP stdio 模式（无需装进 profile）。 |
| @crazy_th/dsh-computer-use 0.2.4 | 明确兼容 DSH 0.1.0-rc.6，Cordis 原生工具；但需安装进 profile 并重启 DSH，且 `computer_observe` 依赖另配视觉模型。备选。 |
| dsh-plugin-computer-use 2.5.0 | 基于 Cua Driver，跨平台；偏 Ubuntu/Wayland 说明，且依赖较新 dsh 工具层。备选。 |
| @deepseek-ai/dsh-computer-use 系列 | 官方 alpha provider/实验 MCP；需要额外 driver 或 profile 配置。未采用。 |

采用的运行方式：`npx -y dsh-computer-use-win` 作为 MCP stdio 服务，由本会话的本地脚本发送 JSON-RPC；共 24 个工具（health / list_windows / snapshot / accessibility_tree / find / click / type_text / keypress / screenshot / ocr / wait_for / invoke / set_value / window 管理 / tools）。本会话脚本位于 `D:\MyAgent\.computer-use-probe\mcp_drive.mjs`、`mcp_batch.mjs`，已复制到本目录。

health 返回：`platform=Windows`、`uiAutomation=true`、`screenshot=true`、`sendInput=true`；控制期间界面显示插件自带的“DSH 正在控制电脑 · Esc 停止”提示。

## 测试对象与环境

- 产物：`apps/desktop/build/windows/x64/runner/Release/paraselene_flutter.exe`（当前工作树最终 Release，PID 3648）。
- 数据：应用默认的 owned synthetic 示例库（非作者库），首次启动为空，点击“创建示例材料”生成示例作品/章节。
- 环境：Windows 11（build 26100/26200 系列）、2560×1440、应用窗口 1920×1080、语言中文（后续切英文）；DSH Desktop 0.1.0-rc.6。

## 已验证的真实交互

| # | 交互 | 结果 | 证据 |
|---|---|---|---|
| 1 | 启动应用、空库态、点击“创建示例材料” | PASS：示例作品/第一章出现，工具栏/侧栏/编辑器正常 | `01-workbench-seeded.png` |
| 2 | 点击“查找正文”，输入“书店”，按 Enter | PASS：定位到第 4 字，正文选中高亮，状态文字正确，循环语义由按钮驱动 | `02-find-match.png` |
| 3 | 章节标题区 | PASS：显示“本章 78 字”；下方语言/保存状态正常 | `01`、`02` |
| 4 | 点击标题旁铅笔“重命名章节” | PASS：对话框打开、输入并 Enter 提交后标题与目录同步更新（输入方式为追加，见问题 5） | `07-rename-applied.png` |
| 5 | 侧栏“搜索章节”输入不存在的词 | PASS：显示“没有匹配的章节。”；清空后章节恢复 | `03-filter-no-match.png` |
| 6 | 点击“章节讨论” | PASS：打开全章讨论对话框（未发草稿、保持正文语言、引用资料(0)、预览完整外发消息禁用、对比、历史记录）；点击遮罩关闭 | `04-chapter-discussion-dialog.png` |
| 7 | 关闭后点击“讨论记录 · 1” | PASS：弹出索引项“全章讨论 / 可继续讨论” | `05-discussion-index.png` |
| 8 | 点击“导出正文与资料” | PASS：真实 Windows“另存为”对话框打开，建议文件名 `雨后的书店_正文与资料.md`；Esc 取消后回到应用且无错误弹窗 | `06-export-save-dialog.png` |
| 9 | 点击“界面语言”→“English” | PASS：全部界面文案切换为英文（Writing workspace / Confirm chapter / Find in chapter / Discussions · 1 / Chapter · 78 characters / Export manuscript and lore 等），正文与标题不被翻译 | `08-wide-english-ui.png` |
| 10 | 点击窗口关闭按钮 | PASS：保存屏障后进程正常退出（PID 3648 结束），无失败提示 | 进程检查 `NO_APP_PROCESS` |

未覆盖：系统保存对话框的实际写入/覆盖/读回（本次只验证取消）、Ctrl+S 的真实效果、IME 组合输入、DPI/多屏、真实模型、作者库。

## 发现的问题与建议

1. **章节讨论对话框缺少可见关闭按钮/标题**：目前只能点击遮罩关闭，键鼠用户（尤其键盘/读屏）没有明确关闭入口。建议在对话框模式加标题“章节讨论/全章讨论”和关闭按钮。
2. **重命名对话框按钮文案是“创建”**：`_TitlePromptDialog` 复用新建文案；重命名场景应为“保存/完成”。建议按用途传按钮文案。
3. **Ctrl+F / Ctrl+A 经 SendKeys 注入未生效**：本次自动化中 Enter、Backspace、普通字符均生效，但 Ctrl+F（打开查找）与 Ctrl+A（全选）没有触发；而 Flutter widget 测试中的 Ctrl+F 路径通过。可能是 SendKeys 与 Flutter 自定义焦点/文本输入桥的注入限制，**不能据此认定功能缺陷**，需要真实键盘人工复验；建议后续用原生插件模式（DSH 内建审批/停止）再验一次。
4. **英文界面 1920 宽时工具栏换行**：语言入口被挤到第二行；中文正常。属可接受的自适应，但可微调工具栏间距或标签。
5. **重命名字段打开时未全选原文本**：自动化输入会追加到原标题后（本次合成库标题因此变长，仅合成数据）。建议打开时 select-all，减少误操作。
6. 测试后示例库保留本轮改动的标题；不影响作者库，可通过新建示例库或后续清理恢复。

## 复现方式

```powershell
# 1) 启动 Release 应用
Start-Process 'D:\MyAgent\paraselene-flutter\apps\desktop\build\windows\x64\runner\Release\paraselene_flutter.exe'
# 2) 用本目录 mcp_batch.mjs 调用独立 MCP（示例 step JSON 见 .computer-use-probe）
node mcp_batch.mjs step-01-snapshot.json
```

如需在 DSH 会话内直接获得桌面工具（而非独立 MCP）：`dsh plugin --profile desktop add dsh-computer-use-win`，完整重启 DSH Desktop，新会话即可使用（带审批与 Esc 停止）。本次为不改动宿主，未执行安装。
