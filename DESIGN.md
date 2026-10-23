# 幻月 · Flutter 工作台设计系统

更新：2026-10-22。当前 Windows Flutter 客户端沿用原版“安静的写作纸面”：正文持续居中，工具按需出现，不重做品牌。工程和验收规则见 [前端规范](docs/engineering/frontend-standards.md)，实现进度见 [当前记录](docs/progress.md)。本文件定义当前设计要求，不用旧 M2 只读预览描述当前编辑器。

## 令牌与实现职责

`apps/desktop/lib/theme/workbench_tokens.dart` 集中颜色、尺寸和字体角色；`workbench_controls.dart` 集中按钮状态/可视底板/命中规则；`workbench_component_themes.dart` 组合原生组件主题，`workbench_theme.dart` 是装配入口。业务从主题入口导入令牌，不重建颜色或 TextStyle。调整共同角色必须同步本文件和相应合同测试。

| 语义 | 值 / 用途 |
| --- | --- |
| paper | `#faf9f5`，作者正文和段下讨论 |
| frame / toolbar | `#f3f4f6` / `#f8f8f9`，目录与工具区 |
| ink / muted | `#292d34` / `#616976`，主要与辅助文字 |
| accent / selected | `#49659c` / `#e8edf5`，动作、焦点与选中 |
| stroke | `#dfe2e7`，装饰分隔线，不承担控件唯一识别 |
| floating / inverseSurface | 白色浮层 / `#2f3640` 深色提示 |
| warning / saved | `#955127` / `#647f70`，同时提供文字或形状信息 |
| selection / source | `#dce5f4` / `#2c5c83`，正文选区与出处标记 |
| placeholder | `#eaecf0`，搜索外壳及中性占位表面 |

文字与必要状态对比度遵守前端规范 F07，禁用内容与纯装饰细线按适用例外处理。透明命中留白不染色，不越界覆盖邻近操作。

## 排版角色

| 角色 | 字号 / 行高 / 字重 | 使用位置 |
| --- | --- | --- |
| body | 20 / 1.85 / 400，Notebook Serif | 作者正文与稿件预览，显式消费 |
| ui / input | 14 / 1.6 / 400，Notebook Sans | 工具说明、表单、讨论草稿 |
| button / search | 13 / 1.6 / 400 | 动作标签、工具搜索 |
| caption | 最低 12 / 1.6 / 400 | 保存、字数、来源、辅助信息 |
| task title | 15 / 1.6 / 500 | 任务型 AlertDialog |
| browse title | 18 / 1.6 / 600 | 浏览型 Dialog |
| chapter title | 32 / 1.55 / 600；紧凑 27 | 章节阅读标题与同角色重命名 |

主题 bodyLarge/bodyMedium 都是工具角色，避免未显式指定样式的表单继承 20px 衬线。正文始终显式使用 body；行内 diff/出处仅加装饰，不覆盖原有字体或改写内容。不同角色是有意层级，不要求所有文字一样大。

字体本地打包：正文 Notebook Serif；工具 Notebook Sans；Arabic 回退 Noto Arabic，正文另有 Notebook Sans 回退。保留字重 400/500/600 与 OFL，来源/SHA/cmap 记录见 `docs/evidence/m2/font-provenance.json`；不请求远程字体。

## 布局与内容方向

- 目录常规宽 240 logical px，顶栏最小高 56。正文舒适/宽稿上限 760/920，外容器 856/1016 含左右留白。
- 可用宽度至少 900 且文字缩放允许时常驻目录；更窄或大字号使用抽屉。工具按空间折叠，保存恢复、版式、讨论索引及退出专注始终可达。
- 专注收起目录，宽稿只调整阅读宽度；偏好来自同一 controller，不新增第二份局部宽稿状态。
- 界面起止方向使用 Directional 几何；作者正文独立决定段落方向，不能因为 UI 镜像改变稿件含义或 Unicode 控制字符。
- 中英为当前 UI 资源范围；RTL/伪长文本是测试 harness，不声称已发布阿拉伯语翻译。系统对话框文字受 Windows 语言控制。
- 文本随 200% 字号自然增高，窄窗可换行或滚动；核心译文不省略、不缩字。作者标题或摘要需要紧凑投影时保留完整可访问名称与明确的全文查看出口。

## 控件几何与状态

| 角色 | 可视几何 | 命中 / 状态责任 |
| --- | --- | --- |
| 文字动作、章末、顶栏 | 最小 32px 高、6px 圆角、水平 8/垂直 4 内距，文字可增高 | 原生透明 padding 保留至少 48px 命中 |
| 图标入口 | 32px 底板、18px 图标 | 至少 48px 命中，有本地化名称、焦点和 tooltip |
| 既有菜单触发器 | 保留 40px 布局、6px 圆角 | 菜单行保留原生至少 48px，并随长文本增高 |
| 普通输入 | 工具字体、局部 1px 边线 | 聚焦 2px accent，无大片 focus fill |
| Checkbox / Switch | 原生勾选或轨道形状 | 48px 命中、selected/toggled 语义，局部焦点 |
| 通用间距 | 4/8/12/16/24px 节奏 | 图文/操作组 8，面板内 12，嵌入上下 8 |

默认、hover、pressed、keyboard-focus、selected、disabled 保持相同几何。hover 使用 `0x12` accent 叠色，pressed 使用 `0x24`；primary 使用白色局部叠色。focus 为始终预留的 2px 局部轮廓，selected 为浅蓝底加勾选/箭头/语义，disabled 优先且无交互叠色。文字选区不充当控件焦点。

顶栏按当前译文、文字缩放与编辑能力测量动作宽度，预留作品标题和保存状态空间；标题/状态不得被挤成逐字换行。长作者标题的单行投影保留完整可访问文字和 tooltip。顶栏常规高度56px，文字放大时可增高；菜单用实际消费共享状态样式的原生按钮分支。

即时状态不强制动画；滚动或展开新增动效必须尊重减少动态效果。关闭面板同时退出绘制、命中和 Tab，讨论运行态与草稿继续由 Registry 持有。

## 表面与临时层级

- 段下讨论由 DiscussionSurface 唯一绘制暖纸面、1px 装饰边和 8px 圆角，无阴影、无全屏暗幕。画布槽位只提供布局，不能另画不同底色。
- 菜单与资料浮卡是轻浮层；真正阻断操作的 Dialog 才使用统一约 32% 灰幕。Dialog 内讨论不再叠 Card，边框/阴影每层只绘制一次。
- 一次只展开一个活动段下线程；收起保留草稿、引用和运行态，索引可重开失效或整章线程。讨论不混入正文或导出。
- 整章讨论短内容自适应、长内容有界滚动，尺寸扣除视口内缩，不固定 560px 高。浏览面板头部/底部动作持续可达。
- 关闭、Escape、点击外侧与焦点归还匹配层级；键盘快捷键不穿透模态输入或 IME composing。

## 有限例外与验收

正文选段浮动工具与 24px 段末标记保留原锚点几何，不把 48px 透明命中侵入正文或相邻标记；这不构成普通按钮、表单或导航入口的尺寸豁免。画布/原生窗口的物理坐标计算不改成界面 Directional。

共享控件合同和主题对比度由测试约束；常规、窄窗、200% 和中英/伪长文案集中复看。截图、普通回归、golden 比较和真实 Windows 系统矩阵分别报告。历史记录见 [交互实施](docs/evidence/ui-interaction-20261021/README.md) 和 [页面覆盖](docs/evidence/ui-completion-20261021/README.md)；它们不自动证明之后的工作树已验收。
