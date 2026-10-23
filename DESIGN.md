---
name: 幻月
description: 暖白正文、浅灰外框与按需展开的段落共写
colors:
  paper: "#faf9f5"
  frame: "#f3f4f6"
  toolbar: "#f8f8f9"
  ink: "#292d34"
  muted: "#616976"
  stroke: "#dfe2e7"
  accent: "#49659c"
  accent-hover: "#405b90"
  selected: "#e8edf5"
  hover: "#e9ecf1"
  selection: "#dce5f4"
  warning: "#955127"
  floating: "#ffffff"
  thread: "#f4f6fa"
typography:
  headline:
    fontFamily: '"Notebook Sans", "Microsoft YaHei UI", sans-serif'
    fontSize: "32px"
    fontWeight: 600
    lineHeight: 1.55
    letterSpacing: "0"
  body:
    fontFamily: '"Notebook Serif", "Noto Serif SC", "SimSun", serif'
    fontSize: "20px"
    fontWeight: 400
    lineHeight: 1.85
  label:
    fontFamily: '"Notebook Sans", "Microsoft YaHei UI", sans-serif'
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  small:
    fontFamily: '"Notebook Sans", "Microsoft YaHei UI", sans-serif'
    fontSize: "13px"
  caption:
    fontFamily: '"Notebook Sans", "Microsoft YaHei UI", sans-serif'
    fontSize: "12px"
rounded:
  control: "6px"
  panel: "8px"
  floating: "10px"
spacing:
  tight: "8px"
  control: "12px"
  panel: "16px"
  roomy: "24px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.floating}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "7px 14px"
  button-primary-hover:
    backgroundColor: "{colors.accent-hover}"
    textColor: "{colors.floating}"
  button-ghost:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "6px 10px"
  navigation-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.accent}"
    rounded: "{rounded.control}"
    padding: "10px 11px"
  thread-panel:
    backgroundColor: "{colors.thread}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
  reference-card:
    backgroundColor: "{colors.floating}"
    textColor: "{colors.ink}"
    rounded: "{rounded.floating}"
---

# Design System: 幻月

## Overview

**Creative North Star: "安静的写作纸面"**

正文是持续工作的中心。暖白纸面由浅中性灰目录和浅色顶栏包围，工具采用清晰的中文无衬线，小说正文采用中文衬线。默认只展开目录与正文，共写在作者选择的段落下出现，资料临时在附近打开。

本文件从活动 Notebook 界面提取，更新于 2026-10-12。沿用正文优先、作者审核和精确出处的既有原则；新的浅色外框、离线字体和段落线程替代旧深灰顶栏与常驻侧边共写布局。

**Key Characteristics:**
- 暖白正文与浅灰工具框架，以字与留白建立层级。
- 衬线正文与无衬线操作文字分工，辅助文字保持可读。
- 低饱和蓝只强调选中、焦点、引用和主要动作。
- 共写与资料按需展开，正文编辑器保持连续。

## Colors

单一低饱和蓝强调色配暖白纸面和冷中性灰框架；前置 YAML 是颜色值的权威记录。

### Primary
- **共写蓝**（accent）：主要按钮、键盘焦点、引用入口、选中章节与选中视图文字；主要按钮悬停使用 accent-hover。
- **选中浅蓝**（selected）：选中目录、版式选择与操作状态；hover 用于普通悬停，selection 用于文字选择。

### Neutral
- **暖白纸面**（paper）：正文与资料编辑主工作区。
- **浅灰框架**（frame、toolbar）：目录和顶部工具栏，与正文靠色温及细分隔线区分。
- **墨色与次文字**（ink、muted）：正文/操作文字与保存状态/字数/来源说明。
- **细分隔线**（stroke）：目录、工具栏、资料卡与分组之间的边界。
- **浮层白与线程浅灰蓝**（floating、thread）：临时资料、菜单与段落共写面板。
- **提示棕**（warning）：保存错误、过期引用等需要作者处理的提示。

**The Action Accent Rule.** 强调色用于动作、选中、焦点与引用；整块工具框架保持中性。

## Typography

**Body Font:** 本地 Noto Serif SC，以 Notebook Serif 注册；fallback 为 Noto Serif SC、SimSun、serif。
**Label Font:** 本地 Noto Sans SC，以 Notebook Sans 注册；fallback 为 Microsoft YaHei UI、sans-serif。

正文使用稳定的中文衬线纹理，工具使用无衬线降低密集操作的阅读负担。四个本地 WOFF2 分别提供正文常规体与工具常规/中等/半粗体，字体资产附 SIL OFL 许可；不依赖远程字体服务。

### Hierarchy
- **Headline**：章节标题默认阅读展示；主动重命名时才显示同字号输入，使用 headline；窄屏降为 27px。中文标题字距为 0，不使用负字距。
- **Body**：正文与桌面候选使用 body；窄屏正文仍为 20px，候选为 19px。
- **Label**：操作控件与线程主要文字使用 label；讨论内容按 1.9 行高排版。
- **Small / Caption**：次级入口与辅助信息使用 small/caption；保存、字数、来源等辅助文字最低 12px。

**The Manuscript Type Rule.** 正文按作者换行，不自动缩进或两端对齐；工具字号不用于小说正文。

## Layout

默认桌面为 240px 目录和可滚动正文。顶栏与目录品牌区等高（56px），顶栏提供作品名、保存状态、版式、专注、章节讨论与导出。正文舒适宽度为 760px，宽稿为 920px；桌面外容器分别为 856px/1016px，包含左右各 48px 内边距。桌面正文上留白为 60px，章节标题与正文间隔为 42px。

1100px 以下正文内边距收为 40px，顶部留白为 42px。900px 以下目录默认收起，可展开为 260px 抽屉；保存状态移至作品名下。760px 以下正文左右内边距为 28px、顶部为 34px，工具标签适当收起，保存状态与“版式”仍可见。

有效选段的共写面板在段下展开，一次只显示一个活动线程，高度上限为 `min(420px, 50vh)`，内容内部滚动。章节讨论和失效选段使用底部抽屉，高度为 `min(360px, 45vh)`。专注隐藏目录和共写。讨论内容不参与正文排版或导出。

资料浮卡桌面宽度最多 380px，高度上限为 520px/72vh，并受窗口可用高度限制；位置以入口附近为起点，收敛在视口内。窄屏已有活动线程时，资料在该线程内部展示。保留卡片头部和底部动作，长资料由中间内容区滚动。

**The One Active Thread Rule.** 活动段落共写只有一处展开，关闭后保留线程状态，以页边标记重新打开。

## Elevation & Depth

正文、目录与线程以色面和细线建立深度，不使用常驻投影。投影仅用于临时选段操作、菜单、资料浮卡与窄屏目录抽屉；菜单和卡片的阴影应柔和且不偏移成装饰边框。实际阴影、160ms 状态过渡、断点与可直接渲染的组件见 `.impeccable/design.json`。

## Shapes

控件和输入使用轻微圆角（control），菜单与线程面板使用 panel，资料浮卡使用 floating。页边线程标记为小圆形，选中标签以背景与文字/底线强调。SVG 图标沿用已有笔画系统，细边框用于明确交互边界。

## Components

### Buttons

主要按钮使用共写蓝与白字，常规操作以透明背景呈现。按钮悬停、选中、禁用和焦点分别处理；键盘焦点为强调色 2px 外轮廓、偏移 3px。禁用主按钮使用分隔线灰背景和次文字。选中目录悬停仍保留选中背景。

### Inputs / Fields

线程输入为白底、细描边和 control 圆角；章节标题默认h1，重命名后用无框输入并提供完成/取消。目录搜索以浅灰填充、整体 focus-within 轮廓提示焦点。输入继承本地工具字体，正文光标与文字选择使用主题色。操作chrome限制误选字，正文、只读资料与候选保留复制。

### Navigation

目录支持章节/资料两类索引、搜索和新增；当前章节使用浅蓝背景、共写蓝文字及中等字重。索引视图与共写视图采用底线选中。版式和导出为临时菜单，Escape 或焦点移出关闭。

### Paragraph Collaboration

真实 CodeMirror 6 编辑器用 StateField 块 Decoration 提供段下插槽，以稳定 React Portal 挂载线程面板；面板包含讨论、候选和版本。候选与原文可比较，由作者采纳或拒绝；正文变更后明确显示失效，不能靠相似文字猜测新的目标。讨论和未发草稿保持在线程内，不能混入正文。

### Reference Card

同一资料卡从目录、正文引用或线程打开。白底浮卡包含标题、描述、原文出处和相关资料；底部“引用/展开编辑”动作位于滚动区之外。关闭返回原输入焦点与选择范围。完整资料和地图复用既有功能组件，继承新的主题和工具字体。

## Do's and Don'ts

### Do:
- **Do** 让正文使用本地衬线、工具使用本地无衬线，辅助文字保持至少 12px。
- **Do** 让活动段下线程单处展开，长内容内部滚动。
- **Do** 保留窄屏保存状态、版式入口及资料卡底部动作。
- **Do** 区分文字选择、普通悬停、控件选中、焦点与禁用状态。

### Don't:
- **Don't** 恢复深灰顶栏、旧 220px 目录或常驻侧边 Agent 作为默认布局。
- **Don't** 将讨论、请求或候选插入正文或正文导出。
- **Don't** 隐藏失效来源，或以相似匹配替作者猜测出处。
- **Don't** 把合成场景切换栏当成产品导航，或将会话版本视图扩展为另一套正式版本系统。

提取依据：`writing/Notebook{Theme,Chrome,Threads,References,Fonts}.css` 与活动组件。最新交付边界见 [PRODUCT.md](PRODUCT.md)，操作证据见 [PARAGRAPH-UI-20261012](docs/evidence/PARAGRAPH-UI-20261012.md)。设计场景专用导航没有固化为产品组件规则；视觉评审意见不替代行为或原生验收。
