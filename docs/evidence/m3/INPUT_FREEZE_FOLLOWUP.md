# 编辑器输入冻结与会话同步接续

日期：2026-10-18。当前阶段：代码已修改，用户要求后续统一测试。

## 修改范围

- EditorInputClient 在执行 document mutation 之前统一检查 UI readOnly 与同步会话 inputBlocked。覆盖原生 updateEditingValue、apply、选择/移动、替换、撤销/重做及换行；拒绝时将当前准确编辑状态回传平台，不把未接受的正文写入本地 document 或历史。
- EditorSessionAdapter 直接提供 session.inputLocked 谓词，防止锁定已经生效、Widget尚未重建时原生回调绕过冻结并令显示正文与保存会话分叉。
- 异步粘贴/剪切完成时复核冻结、当前编辑状态与输入代数；冻结转换或 load 后取消此前的待处理修改，避免旧剪贴板结果落入恢复决定之后或同文的新章节。复制只读取已选文字。
- Adapter 创建时记录当前 contentEpoch，避免第一次正常保存状态通知被误判为外部章节替换，调用 load 清空选区/撤销历史。之后仍只在真实 contentEpoch 改变时重载。

## 已运行与待统一检查

用户要求“先写代码，后面才统一测”之前已启动的批次收取完成后，不再启动测试、analyze、构建或桌面自动化。

- input-freeze-before.txt：冻结后原生正文、迟到paste、迟到cut三个回归均失败，证实缺陷。
- input-session-freeze-before.txt：会话锁定且尚未Widget重建时原生回调造成显示正文分叉，失败。
- input-freeze-after.txt：冻结修复与当时Adapter代码共10项通过。这是用户调整流程前已启动批次的结果，不覆盖随后 contentEpoch 初始化和接口注释修改，也不代表最终统一验收。

统一检查待办：format/analyze；冻结期平台状态回传、IME组合迟到值、冻结后恢复编辑、跨章节同正文的待处理剪贴板取消；首次输入后的选区/撤销保留；编辑器/保存/关闭回归；正式Release与独立bundle。原生IME、golden/完整视觉和DPI矩阵仍未提升。生产Release输出与独立复制包仍是上一轮字体修复版本，当前输入冻结修改尚未构建。

不更改作者库、不发送模型请求，不更新golden。既有源改动、失败图及合成探针保留。
