# 客户端最低可用计划：文档交付

2026-10-12。仅修改工作副本的计划、索引和看板，未实施产品接线。

交付：[client-mvp-plan-20261012](../novel/client-mvp-plan-20261012.md)。包含当前代码确认缺口、异常caret专项、四个交付出口、Agent缺陷模板/提示词和安装版验收脚本。

核查活动 `writing/` 界面、预览保存/导出、线程/候选、旧 `features/novel/state/` 与IPC、Tauri窗口配置及Key存储代码。确认当前为localStorage正文、内存讨论、示例候选与网页下载；异常横条除常驻标题输入外仍待原生复现，不声称根因已确定。

文档检查（pwsh）：

- 用 `Get-Content -Encoding utf8` 与 `[regex]::Matches` 检查文内本地Markdown链接，再以 `Test-Path` 验证；8节完整，187行，坏链0，Agent模板/原生IME脚本均存在，退出0。
- `git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol diff --check -- README.md docs/novel/README.md docs/progress-checkpoint.md`：退出0。
- 计划文件已请求在Codex文件面板打开，工具返回queued。

本轮未运行UI、模型、数据库迁移、原生IME或安装包验证；未发消息给其他用户线程，也未自动派发实现任务。下一步由用户安排其他Agent补充缺陷清单，再认领实施。
