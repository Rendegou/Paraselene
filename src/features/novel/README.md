# 小说工作台（src/features/novel）

T05A 从 `src/NovelEditor.tsx`（491 行集中组件）拆分而来。每个模块只承担一个
职责；组合根只做状态编排，不含检索/生成算法（project-map §2）。

## 职责与公开入口

- `NovelWorkbench.tsx`（组合根，默认导出）：三栏布局与未保存保护；不写业务规则。
- `contracts.ts`：领域类型与 IPC 函数的唯一汇聚点；组件禁止绕过它 import `lib/ipc`。
- `chapters/`：作品目录侧栏。`DocumentShelf.tsx`（目录+新建）、`OpenQuestionsPanel.tsx`
  （待决议题看板）、`documentGroups.ts`（纯函数：分组/排序/插入）。
- `editor/`：正文与试写。`CanonPane.tsx`（正稿、选段修改、历史版本）、
  `DraftPane.tsx`（试写编辑、保存、待确认列表）、`selection.ts`（UTF-16↔字符
  坐标换算，契约见 context-and-storage §4）、`textDiff.ts`（前后缀裁切差异，T05C 升级）。
- `agent/`：AI 入口。`AiDraftPanel.tsx`（整章试写）、`RpgPanel.tsx`（两阶段跑团）、
  `PreviewCard.tsx`（外发预览，只展示后端签发的真实内容，不可伪造）。
- `diff/`：`DraftReview.tsx`（试写核对、逐条冲突覆盖、采纳/丢弃；采纳前校验全通过）。
- `state/`：React 状态编排。`useNovelWorkspace.ts`（作品/文档/选题）、
  `useDocumentDetails.ts`（试写列表/版本树/正文/采纳回滚动作）、
  `useDraftConflicts.ts`（人物冲突候选核对）。
- `format.ts`：展示格式化（compactDate）。

## 不变量

1. 未确认试写永不直接改正稿；采纳必须经版本与冲突核对（G09/G10/G11 契约不变）。
2. 切作品/切文档丢弃上一个异步结果（effect 清理），旧响应不污染新页面。
3. 未保存手写修改离开前必须经用户确认（guard 注入到目录与试写列表）。
4. 选段坐标以"字符序号"对接后端；textarea 的 UTF-16 偏移只在 `selection.ts` 换算。
5. 外发预览只读展示后端 `IssuedPreview`；组件不得拼装或截断拟发送内容。

## 依赖

仅 `../../lib/ipc`（经 contracts）与 React。纯函数模块（selection/textDiff/
documentGroups/format）禁止依赖 React、IPC 与 Tauri API，行为由 `*.test.ts` 锁定。

## 对应验收

T05A 拆分基线；N01–N04 在 T05B/T05C 验收时回到本目录扩展。
