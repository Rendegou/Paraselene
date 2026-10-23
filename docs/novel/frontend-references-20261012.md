# 小说客户端：开源界面参考

检查日期：2026-10-12。检查方式：仓库首页/README、部分源码与许可证的公开读取；未克隆、运行或对这些项目做完整质量认证。本轮前端均自行实现，没有复制上游源码、美术或商标。

## 优先借鉴的三个项目

### steven-tey / Novel

[仓库](https://github.com/steven-tey/novel) · [实际编辑器源码](https://github.com/steven-tey/novel/blob/main/apps/web/components/tailwind/advanced-editor.tsx)

官方说明为带 AI 自动补全的 Notion 风格编辑器，仓库标明 Apache-2.0。本轮核对的编辑器文件可见生成操作菜单、选择工具、延迟保存与本机内容恢复。

借鉴：让 AI 操作围绕正在编辑的文字发生，工具层级克制、保存反馈可见。它是编辑器参考，不是长篇小说作品管理系统。我们保留已安装和历史验证过的 CodeMirror 6，不为换外观迁移至 Tiptap。

### toeverything / AFFiNE

[仓库](https://github.com/toeverything/AFFiNE) · [许可证说明](https://github.com/toeverything/AFFiNE/blob/canary/LICENSE)

官方定位把知识资料、文档与白板结合。借鉴：同一份资料能在正文与空间视图中深入查看，避免人物、地图和设定成为互不相干的表单页。

本项目只需要地点关系和资料跳转，首版不引入完整白板、多人协同或其应用底座。不同部分的权利边界须按具体文件核对，本轮没有代码复制。

### zed-industries / Zed

[仓库](https://github.com/zed-industries/zed)

借鉴：紧凑的编辑器框架、目录/主编辑区/协作区的主次关系和可收起工具区。我们的正文采用适合中文阅读的暖白纸面，不把小说段落排成代码。

不移植整个编辑器运行时。React/Tauri/Rust 现有路径继续使用。

## 补充与排除项

- [usememos / Memos](https://github.com/usememos/memos)：可参考短资料的克制阅读层级；不把备忘录信息流作为小说主导航。
- [Outline](https://github.com/outline/outline)：可参考资料与文档层级；[当前 LICENSE](https://github.com/outline/outline/blob/main/LICENSE) 明示 BSL 1.1，并写明它不是开源许可证。因此按公开界面参考处理，不把整仓当可直接复制的开源客户端。
- [Void](https://github.com/voideditor/void)：[当前 README](https://github.com/voideditor/void/blob/main/README.md) 已声明 deprecated、不再接收贡献。修改审阅与编辑服务可作机制参考，不能推荐为持续维护的底座。

## 选择结论

组合 Novel 的正文就地操作、AFFiNE 的文档/空间关联和 Zed 的工具布局，形成自己的小说工作台。首版只验证作者的创作闭环，引用正确性由现有版本与出处内核逐步接通，不用复杂图形或模型演示代替。
