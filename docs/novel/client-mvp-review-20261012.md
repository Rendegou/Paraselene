# CLIENT-MVP 合并审查清单

2026-10-12。负责人：codex/client-mvp-20261012。按客户端计划第6节先完成三个只读 Agent 的四视角审查，再分配 A 实施；没有并行改共享数据状态。

数据闭环的完整8项（MVP-D01–D08，含2项P0）及B最小合同见 [数据合同](client-mvp-data-contract-20261012.md)。本文件与该合同合并构成唯一去重清单；不将复现脚本冒称已实测。

## P0：正式接线前先处理

- MVP-D01：删空正文删除working copy，重开恢复旧确认稿；删除没有revision CAS。B，代码确认，待实施。
- MVP-D02：切章清除防抖timer而未flush；迟到保存响应没有文档归属保护。B，代码确认，待实施。

完整位置、影响、建议与故障验收见数据合同。新Notebook未接旧保存hook，故当前没有把这些旧缺陷带入新正式入口。

## A 交互

### MVP-101

范围：客户端交互。证据级别：代码确认；部分原生操作。优先级：P1。对应阶段：A。

位置：NotebookManuscript.tsx / ChapterHeading.tsx / NotebookTheme.css。

复现：原实现章节标题常驻32px input，普通点击即编辑。预期：标题默认展示，明确重命名后输入；组成Enter不能提交表单，Escape取消，空名不能提交。

影响：已确认一处大caret来源；其余横条根因不能类推。

建议：展示/编辑状态分离，保留正文与编辑态caret，禁止全局隐藏。

验收：点击展示标题；重命名中文/emoji；Enter提交、Escape取消；微软拼音组成确认与选区恢复。

状态与负责人：已实施/待完整原生验收；root。原生中文emoji赋值和Enter提交已观察，输入不等于IME组成。

### MVP-102

范围：客户端交互。证据级别：代码确认。优先级：P1。对应阶段：A/B。

位置：NotebookSurface.tsx、ParagraphEditor.tsx、ReferenceCard.tsx、useSurfaceReturn.ts。

复现：展开资料卸载正文EditorView，回正文重建，原undo/选区丢失。预期：资料往返保留同章EditorState，恢复输入来源和滚动。

影响：打断创作；可避免离开正文绕过。

建议：同章正文hidden保活，独立记录滚动与输入控件范围；显式出处定位优先于普通返回；保留活动线程ID。

验收：输入两次→正文选段→共写草稿选区→编辑资料→返回，焦点/滚动/草稿/选区一致，Ctrl+Z撤销最后正文输入。

状态与负责人：已实施/待原生验收；root。不得承诺CM内存历史跨重启。

### MVP-103

范围：客户端交互。证据级别：代码确认。优先级：P1。对应阶段：A。

位置：menuDismiss.ts、useMenuNavigation.ts、useReferenceInspector.ts。

复现：菜单Escape未消费传播，window资料卡监听可同时关闭；未过滤组成事件。预期：只关闭最上层弹层，保留IME及草稿。

影响：竞争焦点回归；鼠标逐项关闭可绕过。

建议：过滤isComposing/keyCode229/defaultPrevented，消费Escape，window忽略已处理事件。

验收：卡片→菜单→Escape只关闭菜单；再Escape关闭资料卡；微软拼音选词Escape不误关。

状态与负责人：已实施/待完整原生验收；interaction_audit。单层菜单原生关闭已观察；叠层和IME未测。

### MVP-104

范围：客户端交互。证据级别：代码确认。优先级：P1。对应阶段：A/B。

位置：NotebookSidebar.tsx、NotebookManuscript.tsx、StudioApp.tsx。

复现：固定示例卷名和开发框架混入默认目录。预期：正式入口作品身份真实；无卷数据则不伪造卷名。

影响：正式/示例身份混淆。

建议：移除固定卷名；框架仅在显式design显示；B按native/preview明确隔离后正式工作区去除预览身份。

验收：正式新作品没有固定示例标题/卷名/开发框架；预览状态诚实可见。

状态与负责人：A清理已实施，正式身份仍待B；root。当前仍是示例预览，不能仅删文案伪装正式保存。

### MVP-105

范围：客户端交互。证据级别：代码确认/部分原生操作。优先级：P2。对应阶段：A。

位置：NotebookMenus.tsx、NewEntityMenu.tsx、useMenuNavigation.ts、menuKeyboard.ts。

复现：只提供Tab与点击，缺方向键/首末项/首项聚焦。预期：键盘打开、移动、选择、关闭与焦点回归。

影响：存在Tab绕过，键盘流程不完整。

建议：共用菜单最小hook；保留正常Tab；导出Promise完成后恢复触发器，避免busy禁用丢焦点。

验收：上下循环、Home/End、Enter选择、Escape触发器；原生系统对话框关闭后回导出按钮。

状态与负责人：已实施/待完整原生验收；interaction_audit/root。原生方向键焦点轮廓已观察。

### MVP-106

范围：客户端交互。证据级别：待验证假设。优先级：P1（若确认严重输入异常）。对应阶段：A/D。

位置：StudioBase.css、editorSlots.ts、NotebookTheme.css。

复现：用户报告非输入组件大小横条；除常驻标题外尚未逐组件原生复现。已确认段下root有contenteditable=false，不能当跨块caret缺陷证据。

预期：chrome不误选字，正文/只读资料/候选可选择复制，输入caret与键盘焦点清晰。

影响：待实际复现确定。

建议：仅限定chrome的user-select；保持正文及复制内容；合成窗口观察鼠标指针、caret、选字、focus分别记录。

验收：100%/125%/150%DPI点击目录/页签/工具/卡片/段下空白；同时拖选、双击、微软拼音组成、Ctrl+Z。

状态与负责人：待确认；root。电脑操作被用户实体Escape终止，不报告此项关闭。

## B/C/D 去重后额外缺口

### MVP-AR01

范围：Agent。证据级别：代码确认。优先级：P1。对应阶段：C。

位置：src-tauri/src/commands/novel.rs，NovelPreviewBinding与novel_generate_edit_patch；crates/novel-core/src/generation.rs。

复现：预览后生成期间修改选段外正文，完成时重新读最新working copy绑定patch。预期：候选绑定发起时不可变revision，旧上下文生成不得重新绑定最新稿。

影响：CAS采纳不能识别这种重新绑定。

建议：绑定work/document/thread/operation、workingRevision及正文hash，按原快照保留过期候选。

验收：延迟流中修改选段外文字；输出过期，采纳拒绝。状态与负责人：待实施；C负责人待认领。

### MVP-AR02

范围：保存/Agent。证据级别：代码确认。优先级：P1。对应阶段：B/C。

位置：novel.rs 的novel_apply_patch；memory-core/novel/working_copies.rs与patches.rs。

复现：先提交正文，另一次提交patch终态/剩余块；第二次失败可出现正文修改但命令报错。

预期：一事务完成采纳，重复采纳幂等。影响：异常退出与重试状态分裂。

建议：内核统一pending/head/revision检查与两项写入；返回幂等结果。

验收：故障注入、重开库、重复采纳及并发拒绝；正文和候选一致。状态与负责人：待实施；B/C负责人待认领。

### MVP-AR03

范围：Agent。证据级别：代码确认。优先级：P1。对应阶段：C。

位置：useThreadRequests.ts、useThreadCandidates.ts、ThreadComposer.tsx。

复现：要求加入内存、makeSuggestion产生示例/手工候选；活动UI未接Key设置。预期：明确记录要求与外发预览/真实发送，并返回真实候选。

影响：AI闭环不可达；目前“模型未连接”文案准确。

建议：经适配器复用keyring布尔查询、预览票据与patch，先关闭AR01/02。

验收：无Key/无效Key/存储失败/离线/429各可恢复，授权合成作品真实生成。状态与负责人：待实施；C负责人待认领。

### MVP-AR04

范围：Agent。证据级别：代码确认。优先级：P1。对应阶段：C。

位置：novel生成IPC、novel-core/stream.rs、llm-core/client.rs。

复现：接口仅previewId，无operationId/取消命令；只有连接超时，已连接停滞流没有有限等待。

预期：取消阻止后续落候选，超时可重试，旧输出正确归属。影响：长期等待或跨请求污染风险。

建议：最小operation注册表/取消token/总时限与空闲时限；保留错误分类。

验收：延迟/停滞SSE、切章/作品、重复发送/重试/取消后无候选。状态与负责人：待实施；C负责人待认领。

### MVP-AR05

范围：引用/Agent。证据级别：代码确认。优先级：P1。对应阶段：B/C。

位置：useThreadRequests.ts、novelEditPreview IPC、generation.rs。

复现：资料引用快照只进UI记录；旧预览无资料ID/版本字段。预期：添加/移除资料实际改变可见外发上下文。

影响：直接接旧接口可忽略作者选资料。建议：后端按所选已持久资料ID/版本/scope解析，预览消息与manifest同源，不把任意正文塞instruction绕过边界。

验收：加/移引用逐条核对预览；签发后资料修改不改变票据；失效版本拒绝。状态与负责人：待实施；C负责人待认领。

### MVP-AR06

范围：引用。证据级别：代码确认。优先级：P1。对应阶段：B/C。

位置：studio/types.ts、ReferenceCard.tsx、previewModel.ts、旧selection.ts及SourceAnchor接口。

复现：出处仅chapterId+quote，缺不可变版本；CM UTF-16与Rust Unicode标量范围不同。

预期：绑定作品/文档/版本/range，旧版可查看，当前稿定位单独动作。影响：长期出处缺失，直接传坐标可错范围。

建议：复用SourceAnchor/版本合同及旧坐标转换，不以相似匹配代替绑定。

验收：emoji/CRLF/重复原句/删改/重启；旧出处不乱跳。状态与负责人：正式出处待实施；C负责人待认领。A已补空出处文案。

### MVP-AR07

范围：发布。证据级别：代码确认/原生待验收。优先级：P1。对应阶段：D。

位置：tauri.conf.json、check-quality.ps1、当前evidence。

复现：自动门不安装、不测升级/离线/关闭/Key/IME；窗口仍明确前端预览。预期：同一Windows x64安装构建完成计划最终脚本。

影响：CLIENT_MVP_PASS不可成立。建议：B/C出口后固定产物hash，在安装版复跑；保持identifier与资源边界。

验收：离线冷启、重启/异常退出/旧库升级、系统导出、IME、DPI、授权真实生成。状态与负责人：待实施/验收；D负责人待认领。

## 最短顺序与认领

1. A：101/102/103/105实现、104默认chrome清理、D08原生导出基线；root协调，interaction_audit菜单，agent_release_audit导出（额度中断后root接手）。
2. A：106与IME/焦点/DPI原生出口；用户停止电脑操作，仍待完整验收。
3. B：D01/02/04保存风险→独立作品/按章适配→章节/地点/出处最小迁移→线程与UI会话→正式导出与故障/重启。
4. C：AR02原子采纳→AR01快照绑定→AR04取消/有限等待→AR03/05真实请求与资料→AR06版本出处。
5. D：同一安装版复跑最终脚本。

阶段证据见 [CLIENT-MVP-A](../evidence/CLIENT-MVP-A-20261012.md)。未接B、C、D；没有真实生成、安装版或最低可用通过声明。
