# 小说前端预览

活动入口为 `StudioApp.tsx`。本轮默认浏览器与原生 studio 窗口均进入此处；旧 `Studio.tsx` 是此前未接主入口的试稿，保留且不启用。它与新预览使用不同契约和存储键。

职责：编辑器负责文本/历史/IME/选段；导航 hook 负责章/资料/精确出处；previewModel 校验数据和修改快照；previewStorage/usePreviewPersistence 保存预览；Agent 面板呈现明确标记的示例和作者指令。

预览不是正式作品库。`paraselene.studio-preview.v1` 只保存虚构预览作品，不读写 SQLite。模型尚未接入；作者指令停留在当前前端会话。正式数据接线应复用 `features/novel` 的保存、版本、patch 与出处契约，仍只经 `lib/ipc.ts` 访问原生。

引用坐标为 CodeMirror UTF-16。预览出处只允许唯一精确匹配；改掉或重复的引文失效。候选修改绑定整章快照，正文改变后拒绝采纳。它不替代正式不可变版本引用。

保存失败、损坏数据和另一个标签页的存储变化明确告知并暂停覆盖；localStorage 检查不是原生事务锁。可导出 Markdown 与完整 JSON。
