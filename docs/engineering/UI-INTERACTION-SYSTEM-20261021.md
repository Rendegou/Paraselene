# 幻月交互外观约束与实施交接 · 2026-10-21

## 用户真正希望解决的问题

保留当前已经协调的工作台、纸面、目录与配色，不重设计品牌。问题在于交互时露出了另一套外观：

1. “讨论这段”展开后的输入框/面板，其遮罩、底色或覆盖边界与纸面割裂。
2. 一些按钮静态看起来小，悬停、点击、聚焦、选中时却出现过大、不协调的色块。
3. 需要全局可执行的控件规则，统一尺寸、距离、边界和状态，防止后来添加的组件再次变粗糙。

前两项是用户的实际反馈，必须优先复现，不能被上一轮的图标/字体文案问题替代。“遮罩”暂不锁定成 ModalBarrier：需分别检查卡片填色、Material surfaceTint、输入框 focus/hover fill、裁剪/叠层及真正的模态遮罩。

用户明确要求：先总结，然后开新对话实施前端修改；已授权直接修改与验证，无需再问是否开始。

## 已保存的版本和边界

- 仓库：`D:\MyAgent\paraselene-flutter`。
- 分支：`codex/flutter-migration-20261015`。
- 已推送基线：`19d12c98ee8d333da8391c22f01ef82d25b491a7`，远端 `https://github.com/Rendegou/Paraselene.git`。
- 当前本地仍有八张历史 golden failure 差异图修改；不能 reset、删除、重批或混入本次产品改动。另有 `docs/evidence/UI-DETAIL-20261021.md` 和本交接文档未提交。
- 基线验证：583 普通回归、2 owned DLL、analyze、Release、独立 bundle 已通过；这些是基线证据，修改后须重新做适当检查。
- 只在 Flutter 仓库改动，原 `D:\MyAgent\paraselene-work` 只读。Windows / pwsh。不得读取 Key、env、认证、作者 DB，不发模型或付费请求。
- 本轮不是迁移到 Web：Flutter 原生控件用 ThemeData/组件样式；只有既有学习窗口等 WebView 内页面才有 CSS，不要给原生控件虚构 CSS 层。

## DSH Claude Code 外观参考，已核对真实文件

已安装插件为 `dsh-claude-style` **0.17.0**，MIT，作者 Nwflower：

- 本机目录：`C:\Users\HP\.dsh\profiles\desktop\node_modules\dsh-claude-style`。
- `docs\STYLE.md`：配色、形状、输入焦点、浮层、状态、动效规范。
- `lib\client.js`：实际构建产物，已核对共享 popover CSS 确有 min-height:32px、padding:2px 7px、radius:6px、gap:8px；不是只看说明书。
- 官方仓库：`https://github.com/Nwflower/dsh-claude-style`。
- 发布标签 v0.17.0（`ff58bcfa719fe96df8b234aa93e13e3aad766f79`）只含发布构建；只读副本在 `build\ui-reference-20261021\dsh-claude-style`。
- 实际模块源码从 master 稀疏克隆，固定本次读取提交 **484ece039400ab45a97e935abb5bc47245845a96**，目录 `build\ui-reference-20261021\dsh-claude-style-source`。这是上游源码快照，不冒充已安装标签逐字相同。
- 源码已读：`packages/client/src/shared/popover.css`、`popover.ts`；语义令牌在 `packages/client/src/theme/tokens.json`，动效在 shared/motion.css、motion.ts。仅参考，不执行其脚本、不修改本机插件、不把整个第三方仓库提交到幻月。

可借鉴的机制：

- 共享浮层外壳负责底色、边线、圆角、阴影、内边距，各业务只决定位置/宽度；共享行组件负责高度、图标、文字与状态。
- 以 4px 为主要间距节奏，允许有理由的局部光学修正。原插件菜单壳 12px 圆角、6px 内边距；行最小高度 32px、6px 圆角、16px 图标、8px 图文间距，长文本可增高，不能固定高度裁字。
- hover 只改对应控件底色，不改几何；selected 用明确标记；disabled 有独立状态。
- 关闭的浮层同时退出绘制、命中与 Tab 导航，不能只是透明。浮层开启互斥与锚点定位有统一逻辑。
- 输入区域区分承载表面、边线、焦点线和下方托盘，不能用一大片背景色阴影掩盖层次；焦点保留在控件自身边界。
- 动效使用按角色统一的令牌，并支持减少动态效果。

不照搬插件的品牌橙色、悬浮磨砂、z-index 数字或所有几何值。保留幻月的暖纸面、冷灰工具区、蓝灰强调和原有排版。

## 幻月当前代码证据与待证实根因

- `apps/desktop/lib/theme/workbench_theme.dart:131` 起的 flat 样式给共用文字按钮 `minimumSize: Size(48,48)`，`overlayColor` 是同一个固定色；IconButton 又有36px最小尺寸及框架密度/命中规则。优先核对可视底板、布局盒和命中盒的差异，不能简单全改成更小。
- 同文件没有显式统一 CardTheme；`cowrite/discussion_panel.dart:130` 使用默认 Card，内部 TextField 使用全局 inputDecorationTheme，可能暴露 Material 默认 surfaceTint/fill/focus 效果。这只是待验证候选，不是已复现的结论。
- 同一个 DiscussionPanel 同时用于段下嵌入和 Dialog 中；`manuscript_editor.dart:675` 的 showDialog 未显式指定讨论专用 barrier，Dialog 内再放 Card。应明确 presentation 语义，避免双层卡片或把模态样式漏到段下。
- `manuscript_editor.dart:913` 起 discussionBuilder 将面板放进真实正文布局槽位。修复外观时保持高度测量、阅读位置、选段锚点、焦点和生成运行态。
- 纸面 `_TextAction` 是自定义 Material/InkWell，小内边距；其他区域是 TextButton/IconButton/PopupMenuButton/DropdownButton，实际存在多套控件实现。

## 实施规则：先测量，再确定有限的角色

1. **尺寸与盒模型**：分开定义图标大小、可视底板、布局占位、命中区。桌面紧凑控件可从28/32/36px角色中选有限集合，文字按钮随内容与文字缩放增高；不要让所有按钮继承48px可视方块。不得为了精致牺牲键盘焦点、触控可达性或大字号；透明命中留白不得染色或侵入邻居。
2. **距离**：采用4/8/12/16/24主节奏；同组图标/按钮间距、图文间距、面板内边距、输入框与操作行距离各有语义令牌。不要给每个页面独立猜数字，也不要机械改动正文的既有字号/行高/纸面留白。
3. **状态矩阵**：rest/hover/pressed/keyboard-focus/selected/disabled 每个角色有明确表现；hover/pressed/selected 的可视边界一致、不改变布局、不造成位移。focus 用清楚但克制的轮廓，不用大色块替代；disabled 优先于可交互状态。键盘焦点与正文选区不能混为一谈。
4. **层级**：段下讨论属于纸面上的嵌入式编辑区，不加全屏暗幕；菜单属于轻浮层；真正阻断操作的对话框才使用统一模态遮罩。每个层级只有一套边线/圆角/阴影责任，避免 Card 嵌套 Dialog 叠加表面效果。关闭方式、Escape、点击外侧和焦点归还要匹配层级。
5. **组件接缝**：沿用现有 tokens/theme，提取确实复用的按钮、图标入口、菜单行、讨论表面；不要搭建庞大组件框架。入口通过角色/variant 使用规范，组件内部显式消费主题，减少直接默认 Material 控件导致的风格泄漏。
6. **约束能执行**：DESIGN.md记录角色与例外理由；选少量有价值的状态/几何测试验证 hover盒不变、不溢出、disabled语义、焦点与展开关闭行为；必要时加局部回归截图。不要只写一份无法约束实现的规范。

## 新对话工作顺序与验收

1. 读本文件、AGENTS.md、DESIGN.md、上轮 UI-DETAIL 与 review-fixes 证据；检查当前 diff，避免覆盖已有修改。按最新 Impeccable skill 加载上下文，UI 编辑前读 craft-floor。
2. 以合成场景打开“讨论这段”，观察空输入、聚焦、输入后、收起重开。核对遮罩具体来自哪层；同批观察按钮默认/hover/pressed/focus/selected/disabled，获得至少一组修改前证据。无法操作时先用真实组件测试渲染同样的状态，明确区别于原生系统实测。
3. 写下实际尺寸和状态责任，补充 DESIGN.md，再把共享样式与关键讨论表面一次改到位；随后迁移顶栏、章末、讨论操作、菜单与弹窗的同类入口，避免只修一个输入框。
4. 同一批截图验证讨论与按钮状态，覆盖一档常规宽度、一档窄窗和大字号。新图不能靠改 golden 旧基线掩盖问题。
5. 保留前次修复：IME快捷键守卫、讨论生成收起重开仍可取消、资料冻结讨论目标、bundle验证不删除历史。跑必要的组件测试、format、analyze；有逻辑变更跑相关回归。构建 Windows Release 并验证 bundle，再打开新客户端给用户查看。
6. 写清实际PASS/NOT_RUN，不宣称自动化操作失败的状态已通过；不调用真实模型。不自动合并或推送新UI改动，用户之前“先push”已由基线提交完成。

## 工具与已知限制

- 本机 Impeccable **4.7.0**。新入口是 `C:\Users\HP\.agents\skills\impeccable\scripts\impeccable.cmd`，不是旧版 context.mjs/detect.mjs。本轮 context 已成功读取；新对话按其会话规则读取。
- Flutter SDK `D:\flutter_sdk\flutter`。此前 flutter.bat 在沙箱缓存锁上不稳定，成功入口为 `D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=D:\flutter_sdk\flutter\packages\flutter_tools\.dart_tool\package_config.json D:\flutter_sdk\flutter\bin\cache\flutter_tools.snapshot --no-version-check --suppress-analytics ...`；访问工作区外SDK缓存需获准的执行权限。
- Windows UI 使用 computer-use skill 的 @oai/sky。本轮截图曾遇到用户输入/窗口位置变化、控件索引失效和输入无预期反馈，不能把截图未到达当成应用缺陷。用户已授权操作截图，但不要干扰用户正在操作的窗口。
- 上轮图片目录：`C:\Users\HP\.codex\visualizations\2026\10\20\01a15850-0003-7931-9901-df51f9347729\ui-detail-20261021`；上轮只有工作台与菜单可靠画面，尚无讨论遮罩的可靠复现截图。
