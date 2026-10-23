# GitHub / 开源设计系统去 AI 味参考（带证据等级）

日期：2026-10-13。用途：为 `paraselene-work` Studio 工作台的样式改进提供外部参照。

> **证据等级说明（重要）**：本次调查环境**无法读取任何网页正文**（`web_fetch` 对所有域名均失败，仅 `web_search` 可用且只返回 URL 与标题）。因此每条结论都标注等级，**没有编造任何数值**：
>
> - **[V] 已验证**：事实可见于实际收到的标题或 URL 字符串。
> - **[C] 已定位**：URL 确认有效且是该规范的正确页面，但**正文未读**，故未转录具体数值。
> - **[U] 未验证**：无法确认。**不要在没有网络的环境下凭记忆引用这些数值。**
>
> 需要真实数值时，请在有外网的机器上打开下表中的 [C] 链接。本文件的价值在于**准确的落点**，不是数值转录。

---

## 1. 反 AI 味的命名模式（"套话"清单）

### 1.1 系统性目录

| 来源 | 说明 | 要点 |
|---|---|---|
| [JCarterJohnson/vibecoded-design-tells](https://github.com/JCarterJohnson/vibecoded-design-tells) | **最有价值的一份：量化排名**，从 Reddit 挖掘 vibe-coded 站点的视觉特征 | **[V]** "3.2M posts scanned across 47 subreddits, with scripts, raw data, and charts" — 唯一带数据和脚本的特征排名 |
| [Ad-Astra-Computing/ahd — SLOP_TAXONOMY.md](https://github.com/Ad-Astra-Computing/ahd/blob/main/docs/SLOP_TAXONOMY.md) | 正式**分类法**（非感受清单） | **[V]** 路径存在；内容 [C] |
| [marten-osieka/de-ai-ui](https://github.com/marten-osieka/de-ai-ui) | 专门剥离 AI 指纹的 agent skill，含特征目录 + 自审 | **[V]** 仓库描述明确列出 "purple gradients, 3-card grids, em dashes, placeholder logos" |
| [Eneryleen/ai-web-design-codex](https://github.com/Eneryleen/ai-web-design-codex/blob/428f24ef535a62782d67882191fb099bfbf20712/07-aesthetics-and-trends/avoiding-generic-ai-aesthetics.md) | 整章讲"如何避免通用 AI 审美" | [C] |
| [jikig-ai/soleur — frontend-anti-slop/anti-patterns.md](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/frontend-anti-slop/references/anti-patterns.md) | 反模式枚举 | [C] |
| [jcartu/rasputin-mantle — AI_SLOP_CHECKLIST.md](https://github.com/jcartu/rasputin-mantle/blob/main/design-system/AI_SLOP_CHECKLIST.md) | 清单形式，适合直接做评审门禁 | [C] |
| [pypi.org/project/ai-design-tells](https://pypi.org/project/ai-design-tells/) | 可安装的特征检测器 | **[V]** 包存在 |

### 1.2 设计媒体与评论

- **[V]** [Why Do Most AI-Generated Websites Look the Same?](https://shuffle.dev/blog/2026/01/why-do-most-ai-generated-websites-look-the-same/) — Shuffle
- **[V]** [Why Every Billion-Dollar AI Startup Has the Same Homepage Design](https://www.designrush.com/agency/website-design-development/trends/ai-startup-homepage-design) — DesignRush
- **[V]** [There are 3 telltale signs that you used AI to make your app](https://www.businessinsider.com/ai-coded-app-user-interface-experience-design-2026-7) — Business Insider；中文镜像：[TechOrange](https://techorange.com/2026/07/08/ai-coded-app-user-interface-experience-design/)
- **[V]** [AI Design Slop: Why AI-Generated UI Looks Generic — and the Fix](https://smoothui.dev/blog/ai-design-slop) — **"症状 → 修法"结构写得最好的一篇**；源码：[ai-design-slop.mdx](https://github.com/educlopez/smoothui/blob/main/apps/docs/content/blog/ai-design-slop.mdx)
- **[V]** [为啥我用 AI 做的网站都是蓝紫渐变色？咋解决啊](https://developer.cloud.tencent.cn/article/2687093?policyId=1004) — 中文，专讲蓝紫渐变
- **[V]** [Design Homogenization and the Loss of Situated Design](https://www.semanticscholar.org/reader/e67a8cfdbb4a25af2aefddb712a8f84df6286e30) — 学术视角
- **[V]** [When Generation Is Free, Taste Is the Whole Job](https://depix.ai/blog/taste-problem-2026-when-generation-is-free) — 关于"品味成为瓶颈"

**[U]** 无法确认"紫蓝渐变 / Inter / rounded-2xl + 软阴影 / emoji 图标 / 三栏网格 / 全居中 / Elevate-Seamless 文案"这一整串是否是**任何单一来源的正式清单**。这些特征在各来源的标题与描述中被反复提及（de-ai-ui 的描述确认了紫渐变、三栏网格、em dash、占位 logo），但**应视为综合归纳，而非引用**。

---

## 2. 成熟设计系统的 token 结构（精确落点）

### 2.1 Vercel Geist

| 内容 | 来源 |
|---|---|
| 官方字号刻度与字距 | [vercel.com/geist/typography](https://vercel.com/geist/typography) **[C]** |
| 官方色彩系统 | [vercel.com/geist/colors](https://vercel.com/geist/colors) **[C]** |
| **机器可读主题（捷径）** | [vercel-labs/native — geist.zig](https://github.com/vercel-labs/native/blob/80d1c46d3632fee4ea7bc1d95300d04a2b6c5ae2/src/primitives/canvas/themes/geist.zig) **[C]** — 整个 Geist 主题以常量形式编码，**提取真实数值最快的路径** |

**[V] 一条已确认的结构决策**：Geist 的中性色是 **100–1000 刻度**，且按色族分开管理（gray / blue / red / amber / green / teal / purple / pink），即**约 80 个中性+彩色阶**，而不是手挑的 5 色板；且**刻意不用纯 `#000`/`#fff` 作为两端**。

### 2.2 Tailwind v4 + Catalyst

全部集中在 [tailwindcss.com/docs/theme](https://tailwindcss.com/docs/theme) **[C]**，这是 `@theme` 的权威参考，列出全部默认命名空间：`--spacing-*`、`--font-*`、`--text-*`（**每个字号自带配对行高**）、`--radius-*`、`--shadow-*`、`--ease-*`、`--color-*`、`--tracking-*`、`--leading-*`、`--animate-*` 等。

| 内容 | 来源 |
|---|---|
| CSS-first 主题（`@theme` vs `@layer theme` 优先级） | [Advanced Theming](https://mintlify.wiki/tailwindlabs/tailwindcss/advanced/theming) **[C]** |
| **v3 间距刻度（`0.25rem` 基准的来源）** | [v2.tailwindcss.com/docs/customizing-spacing](https://v2.tailwindcss.com/docs/customizing-spacing) **[C]** |
| 字号刻度与配对行高 | [tailwindcss.com/docs/font-size](https://tailwindcss.com/docs/font-size) **[C]** |
| 字号默认字体栈来源 | [v2.tailwindcss.com/docs/font-family](https://v2.tailwindcss.com/docs/font-family) **[C]** |

**[U]** `--shadow-2xl` / `--radius-sm` / `--text-sm` 的**字面数值**。**特别注意 v4 重命名了阴影刻度**（`shadow-sm`→`shadow-xs` 等），凭 v3 记忆引用一定是错的。

**[C] 架构要点**：Tailwind 默认值之所以"系统化"，在于**单一间距乘数**、**每个字号自带配对行高**、**多层带色调而非纯黑的阴影刻度**。**抄这个结构比抄任何单值都有价值。**

### 2.3 shadcn/ui

| 内容 | 来源 |
|---|---|
| 主题文档（CSS 变量契约） | [ui.shadcn.com/docs/theming](https://ui.shadcn.com/docs/theming) **[C]** |
| 单篇最佳 token 约定解读 | [Latias94/fret — shadcn-style-token-conventions.md](https://github.com/Latias94/fret/blob/main/docs/shadcn-style-token-conventions.md) **[C]** |
| 色板库 | [v3.shadcn.com/colors](https://v3.shadcn.com/colors) **[C]** |

**[C] 关键决策**：shadcn 的模型是**语义变量**（`--background`/`--foreground`/`--primary`/`--muted`/`--border`/`--ring`/`--radius`），外加**单一 `--radius` 根值，用 `calc()` 派生 `--radius-sm/md/lg/xl`**。这正是 AI 生成 CSS 缺失的"一个旋钮、几何一致"性质——AI 输出往往每个组件硬编码一个不同圆角。

### 2.4 Radix Themes / Radix Colors

| 内容 | 来源 |
|---|---|
| **12 阶色标的语义契约** | [understanding-the-scale.mdx](https://github.com/zhcndoc/radix/blob/main/data/colors/docs/palette-composition/understanding-the-scale.mdx) **[C]** |
| 半径 / 间距 / 字号刻度 | [radius](https://www.radix-ui.com/themes/docs/theme/radius) · [spacing](https://www.radix-ui.com/themes/docs/theme/spacing) · [typography](https://www.radix-ui.com/themes/docs/theme/typography) **[C]** |
| 全局密度旋钮 `scaling` | [radix-ui.com/themes/docs/components/theme](https://www.radix-ui.com/themes/docs/components/theme) **[C]** |
| 中文版（更易读） | [radix-ui.com.cn](https://radix-ui.com.cn/themes/docs/theme/radius) **[C]** |

**[C] 本报告最值得直接照搬的一个理念**：Radix 的 **12 阶色标每一阶有固定语义职责** —— 1–2 应用底色、3–5 组件底、6–8 描边、9–10 实心/强调填充、**11–12 可访问文字色**。因为 11/12 被定义为"文字色"，**对比度成为结构性保证，而不是逐组件碰运气**。

### 2.5 IBM Carbon

| 内容 | 来源 |
|---|---|
| **间距（8px 网格，4px 最小单位）** | [spacing overview](https://www.carbondesignsystem.com/building-blocks/foundations/spacing/overview) **[C]** |
| 字号体系 | [type-sets](https://www.carbondesignsystem.com/building-blocks/foundations/typography/type-sets) **[C]** |
| **动效时长与缓动** | [motion overview](https://carbondesignsystem.com/elements/motion/overview) · [motion code](https://carbondesignsystem.com/elements/motion/code) **[C]** |
| **精确 Sass token 源** | [packages/layout/docs/sass.md](https://raw.githubusercontent.com/carbon-design-system/carbon/refs/heads/main/packages/layout/docs/sass.md) **[C]** — `$spacing-*` 数值在此 |
| 焦点环 Sass | [components/docs/sass.md](https://raw.githubusercontent.com/carbon-design-system/carbon/73a5b7177554eb7eb606844f13f1ffcf9a3466e7/packages/components/docs/sass.md) **[C]** |

**[V]** 4px 最小单位 / 8px 网格的说法有独立来源佐证（explainx.ai 的 IBM DESIGN.md 称 "Carbon uses precise alignment to a 4-pixel grid as its whitespace system"）。**[U]** 各 `$spacing-01…12` 的具体数值与动效毫秒表。

### 2.6 GitHub Primer

| 内容 | 来源 |
|---|---|
| token 入口 | [primer.style/foundations/primitives/getting-started](https://primer.style/foundations/primitives/getting-started) **[C]** |
| **间距（`--base-size-*`，4px 基准）** | [primer/css — spacing.md](https://github.com/primer/css/blob/714a01d5449721132ef59cdf9af26567e65c5807/docs/content/support/spacing.md) **[C]** |
| token 真实来源 | [primer/primitives](https://github.com/primer/primitives) **[C]** |
| 半径/阴影 token 转述 | [explainx.ai GitHub DESIGN.md](https://explainx.ai/designs/whyashthakker-design-md-templates-skills/github/design-md) **[C]** |

Primer 值得照搬的是 **`--base-size-N` 间距**、`--borderRadius-*`，以及**按"角色"而非"大小"划分的阴影三元组**：`--shadow-resting-*`（静置）/ `--shadow-floating-*`（悬浮）/ `--shadow-inset-*`（内嵌）。**[C]**

### 2.7 Ant Design v5

| 内容 | 来源 |
|---|---|
| token 架构（seed → map → alias） | [deepwiki — design token and theming](https://deepwiki.com/ant-design/ant-design/3.2-design-token-and-theming-system) **[C]** |
| 官方主题定制 | [ant.design/docs/react/customize-theme](https://ant.design/docs/react/customize-theme.md) · [中文](https://ant.design/docs/react/customize-theme-cn.md) **[C]** |
| **含字面阴影值的 DESIGN.md** | [gitee.com/ant-design/ant-design/blob/master/DESIGN.md](https://gitee.com/ant-design/ant-design/blob/master/DESIGN.md) **[V]** |
| 动效规范 | [1x.ant.design/docs/spec/motion](https://1x.ant.design/docs/spec/motion) **[C]** |

**[V] 本次唯一确认到字面值的 token** —— Ant 的三级（tertiary）抬高面阴影为：

```
boxShadowTertiary: 0 1px 2px 0 rgba(0,0,0,0.05), 0 1px 6px -1px rgba(0,0,0,0.03)
```

这条很有价值：**两层、极低透明（5% / 3%）、偏移很近、第二层带负 spread**。这与 AI 默认那种单层大范围 `0 10px 15px -3px rgba(0,0,0,0.1)` 完全不同 —— **这就是"被调过的阴影"与"默认阴影"在形状上的区别**。

**[U]** `borderRadius: 6`、`fontSize: 14`、`sizeUnit: 4`、`motionDurationFast/Mid/Slow` 的数值（流传甚广但本次无法从正文确认）。

### 2.8 Linear 与 Stripe（重要提醒）

**[V] 两者都没有公开发布正式数值化的设计系统。** Linear 的设计文章在 [linear.app/method](https://linear.app/method)；社区逆向工程见 [ConardLi/garden-skills — linear.md](https://github.com/ConardLi/garden-skills/blob/main/skills/web-design-engineer/references/style-recipes/linear.md) **[C]**、中文译本 [flanker/linear-method-zh-cn](https://github.com/flanker/linear-method-zh-cn) **[C]**。Stripe 只有第三方提取：[styles.refero.design](https://styles.refero.design/style/48e5de76-05d5-4c4e-a269-c7c245b291ec) **[C]**、[design-bites — stripe DESIGN.md](https://github.com/educlopez/design-bites/blob/main/design-mds/bfcm.stripe.com/DESIGN.md) **[C]**。

**因此：网上流传的一切"Linear 的数值"都是逆向推测，必须按推测对待。**

**真正可靠的公开产物是 DESIGN.md 语料库** —— [VoltAgent/awesome-design-md](https://raw.githubusercontent.com/VoltAgent/awesome-design-md/main/design-md/ibm/DESIGN.md) **[C]**、[中文版](https://fchangjun.github.io/awesome-design-md-cn/design-md/ibm/preview.html) **[C]** —— 它把上述系统重述为可复制的 token 表。**有网络后，这是投入产出比最高的一次性抓取。**

---

## 3. "怎么让 AI 产出不像 AI" 的权威材料

### 3.1 第一方权威材料（最高价值）

| 来源 | 为什么重要 |
|---|---|
| [**anthropics/claude-plugins-official — frontend-design SKILL.md**](https://github.com/anthropics/claude-plugins-official/blob/b392f51899343f35a203260a4b344803de236d13/plugins/frontend-design/skills/frontend-design/SKILL.md) | **[V] 本节最有价值的产物** —— 官方发布的"如何阻止模型回退到默认审美"指令集。**建议直接把它的约束结构搬进本项目 `AGENTS.md`，而不是转述** |
| [Improving frontend design through Skills](https://claude.com/blog/improving-frontend-design-through-skills) | **[V]** 官方博客，解释该 skill 的设计动机 |
| [**Prompting for frontend aesthetics** — Claude Cookbook](https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics) | **[V]** 正对这个问题的配方 |
| [OpenAI prompting tips for frontend designers](https://the-decoder.de/openai-veroeffentlicht-prompting-tipps-fuer-frontend-designer-mit-gpt-5-4/) | **[V]** 另一家实验室的同类指导 |

### 3.2 流程与"注入约束"的工具

- **[V]** [用 Skills 根治 AI 审美趋同：Claude 前端设计进化全解析](https://blog.csdn.net/wojiushiwo987/article/details/159257471)
- **[V]** [Taste-Skill：为 AI 生成界面注入"审美基因"的前端技能框架](https://cloud.tencent.com.cn/developer/article/2705446)
- **[V]** [garden-skills：25 种风格配方让 AI 前端审美直接拉满](https://cloud.tencent.cn/developer/article/2676247) — [源码](https://github.com/ConardLi/garden-skills)
- **[V]** [You Ask, I Answer: High-Quality Design in Vibe Coding](https://www.christopherspenn.com/2026/04/you-ask-i-answer-high-quality-design-in-vibe-coding/) — 怀疑视角

### 3.3 模型为什么会趋同

**[C]/[U]** 各来源的解释方向一致，但**没有一篇给出了带证据的因果论证**，故机制部分按"合理推断"对待：指令微调把模型推向**训练分布中最高频的网页审美**；无约束时它必然回归均值，而均值由少数模板库外观主导。所有来源给出的解法形状相同：**用明确、不可协商的约束 + 一个具体参照物，替换掉默认值**。

**最有效的一步操作**：打开 Anthropic 的 `frontend-design` SKILL.md，**把它的约束结构原样搬进 `AGENTS.md`/系统提示**，并**附上一张真实的参照截图**。所有讨论流程的来源都收敛到"对着真实参照图迭代"，而不是"要求它好看一点"。

---

## 4. 中英混排桌面应用的字体

### 4.1 Windows 上真正可用的中文字体栈

| 来源 | 说明 |
|---|---|
| [**W3C clreq — 通用中文字体族的系统字体映射**](https://w3c.github.io/clreq/others/system-font-mappings.html) | **[V] 权威页面**：把通用族（serif/sans-serif/cursive）映射到**各平台实际字体名**。**字体栈应从这里抄。** |
| [pltuwen/cn-css-font-family](https://github.com/pluwen/cn-css-font-family) | **[V]** 最经典的中文站点 `font-family` 设置 |
| [joeseesun/qiaomu-design — chinese-typography.md](https://github.com/joeseesun/qiaomu-design/blob/main/references/chinese-typography.md) | **[V]** 完整的中文排版与配色规范 |
| [W3C clreq — 中文排版需求（规范本体）](https://www.w3.org/TR/2023/DNOTE-clreq-20230301/) | **[V]** 规范性文档 |

**Windows 上必须列入栈的真实族名** **[C]**：`Microsoft YaHei UI`、`Microsoft YaHei`、`SimSun`/宋体、`SimHei`、`Source Han Sans SC`/思源黑体、`Noto Sans SC`、`HarmonyOS Sans SC`、`MiSans`。

**[U] 未能验证** Windows 默认中文 UI 字体究竟是 `Microsoft YaHei UI` 还是 `Microsoft YaHei`，也未能验证"应当内置还是依赖系统字体"。**在没有一手引用前，不要把 `Microsoft YaHei UI` 当既定事实。**

### 4.2 CJK webfont 体积与性能

| 来源 | 说明 |
|---|---|
| [**W3C webfonts-wg — Unicode Range Blocking Algorithm**](https://lists.w3.org/Archives/Public/public-webfonts-wg/2020May/0007.html) | **[V] Google Fonts 的 CJK 切片算法原始来源** —— `unicode-range` 技巧的权威依据 |
| [PrinOrange/cn-font-split](https://github.com/PrinOrange/cn-font-split) | **[V]** 当前最好的 CJK 子集化工具 |
| **真实切片证据** | **[V]** `@fontsource/noto-sans-sc` 切片为编号分片（见 CDN 目录中的 `noto-sans-sc-55-400-normal`）→ **确证 Noto Sans SC 是几十个 `unicode-range` 分片，而非单文件** |
| `unicode-range` 回退的真实 bug | [nuxt-modules/og-image#554](https://github.com/nuxt-modules/og-image/pull/554) **[V]** — "fix: fall back across unicode-range font subsets for CJK rendering" |

**[C] 架构建议（推论）**：Tauri 桌面应用**不要**用 Google Fonts CDN。应 (a) 为**界面外壳**内置**子集化**字体（只需几百字形，几十 KB），(b) 为**用户正文**依赖系统字体 —— 因为小说可能包含两万多个汉字。这是唯一既小又正确的方案。

**[U]** 无法验证 Source Han Sans / Noto Sans SC 完整 woff2 的具体 MB 数，也无法验证 Google Fonts 具体切成多少片。

### 4.3 中文正文衬线选项（均为 OFL 系开源）

| 字体 | 适合 | 备注 |
|---|---|---|
| **思源宋体 / Source Han Serif / Noto Serif SC** | 屏显优化，正文安全默认 | [Adobe 新闻稿](https://www.adobe.com/content/dam/acom/hk_en/about-adobe/newsroom/pdfs/Adobe%20introduces%20Source%20Han%20Serif%20fonts%20for%20Asian%20users.pdf) **[V]** |
| **霞鹜文楷 / LXGW WenKai** | 楷体书写感，阅读/写作应用很受欢迎 | [使用说明](https://bupt-scss-insight.github.io/blog/websitebeauty/mkdocsfont/) **[V]** |
| 宋体 / SimSun | 印刷传统；**小字号屏显效果差** | Windows 系统字体 |

**许可证要当心**：**[V]** HarmonyOS Sans 的可商用条款在华为开发者社区有专门讨论帖，说明它**并非简单的 "OFL 随便用"**；MiSans / HarmonyOS Sans 进安装包前必须核实。参考 [免费可商用字体授权核查指南（2026）](https://www.aflaw.cn/zzq/3194.html) **[V]**。

**[U]** 无法验证"思源黑体的拉丁部分基于 Source Sans、思源宋体基于 Source Serif"这一流传说法。

### 4.4 中文排版指标

| 主题 | 来源 |
|---|---|
| 规范本体 | [W3C clreq](https://www.w3.org/TR/2023/DNOTE-clreq-20230301/) **[V]** |
| **字距/行距/段距怎么取** | [中文排版字距行距段落間距：怎麼抓才對？](https://www.pongo.com.tw/chinese-typography-spacing/) **[V]** — 直接对口 |
| 中文文案排版指北 | [sparanoid/chinese-copywriting-guidelines](https://github.com/sparanoid/chinese-copywriting-guidelines) **[V]** |

**中文标点/间距的 CSS 新特性（Chromium 已实现，因此 WebView2 可用）：**

| 特性 | 来源 | 状态 |
|---|---|---|
| `text-autospace` | [MDN: text-autospace](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-autospace) **[V]** | 参考页存在；iOS Safari 兼容性见 [bcd#26696](https://github.com/mdn/browser-compat-data/issues/26696) |
| `text-spacing-trim` | [MDN 源文件](https://raw.githubusercontent.com/mdn/content/46208a9448a1f51e40b3ee1dfe8dc8a657a74ccd/files/en-us/web/css/text-spacing-trim/index.md) **[V]** | 参考页存在 |
| 两者随 Chrome i18n CSS 工作上线 | [**CSS に 4 つの新しい国際化機能を導入** — Chrome for Developers](https://developer.chrome.com/blog/css-i18n-features) **[V]** / [中文版](https://developer.chrome.google.cn/blog/css-i18n-features?hl=zh_cn) **[V]** | **[V] 权威发布** |
| 规范仍在演进 | [CSSWG 讨论](https://lists.w3.org/Archives/Public/public-css-archive/2026Mar/0485.html) **[V]** | 2026 年仍在改 → **必须特性检测** |
| 真实采用案例 | [multica 提交](https://github.com/multica-ai/multica/commit/70e4f44860f7cdc77d80cb4c89cebe2bfa93e568) **[V]** | 生产使用 |

**[U]** 无法验证中文 `line-height`（常被引用的"中文 1.5–1.8 vs 拉丁 1.4–1.5"）、中文正文正字距、`2em` 首行缩进在 clreq 中的地位等具体数值。也 **[U]** `palt`/`halt`/`vhal`/`vpal` 在 WebView2 中是否安全，以及中文每行推荐字数。

**可自信陈述的（作为推论而非引用）**：汉字为全宽、字面无升降部差异，因此**同样的字号下中文需要比拉丁更多的行距才舒适**，且**中文标题不使用拉丁式的负字距**。

---

## 5. 动效 / 层级 / 交互的数值落点

### 5.1 时长与缓动

| 系统 | 来源 |
|---|---|
| **Material 3 缓动与时长 token** | [m3.material.io — tokens-specs](https://m3.material.io/styles/motion/easing-and-duration/tokens-specs) **[C]** |
| **M3 token 的真实代码（最佳提取路径）** | [androidx `MotionTokens.kt`](https://android.googleid.googlesource.com/platform/frameworks/support/+/78929c1b1cdb3ce6deec04b74da5a8cbb30d9360/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/MotionTokens.kt) **[C]** — **字面 cubic-bezier 控制点与毫秒值在此** |
| M3 状态层透明度 | [androidx `StateTokens.kt`](https://android.googleid.googlesource.com/platform/frameworks/support/+/78929c1b1cdb3ce6deec04b74da5a8cbb30d9360/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/StateTokens.kt) **[C]** |
| **Carbon 动效** | [overview](https://carbondesignsystem.com/elements/motion/overview) · [code](https://carbondesignsystem.com/elements/motion/code) **[C]**；可读镜像 [openbmc webui-vue motion.md](https://grok.openbmc.org/raw/openbmc/webui-vue/docs/guide/guidelines/motion.md) **[V]** |
| Tailwind 默认缓动 | `--ease-*`、`--default-transition-duration`，见 [tailwindcss.com/docs/theme](https://tailwindcss.com/docs/theme) **[C]** |
| 经验规则 | [Animation Standards Reference](https://raw.githubusercontent.com/nexu-io/open-design/01169bcd990bf508cf919f6d56ca78240279eabf/skills/review-animations/STANDARDS.md) **[C]**、[200ms 规则](https://www.appypie.com/blog/mobile-app-animation-guide) **[V]** |
| Emil Kowalski 的动效原则（转录） | [emil-kowalski.md](https://github.com/kylezantos/design-motion-principles/blob/HEAD/skills/design-motion-principles/references/emil-kowalski.md) **[V]** |

**[U]** 所有具体毫秒值与 cubic-bezier 控制点。**androidx 与 openbmc 的代码镜像是读取精确数值最可靠的地方。**

### 5.2 弹簧 vs 缓动

| 来源 | 说明 |
|---|---|
| [**Motion (motion.dev) — spring**](https://motion.dev/docs/spring) **[V]** | `bounce` / `duration` / `visualDuration` 模型 |
| [Framer Motion 弹簧实现](https://cdn.jsdelivr.net/npm/motion-dom@12.40.0/dist/es/animation/generators/spring.mjs) **[V]** | 真实实现，可读 |
| [Apple — `Spring`](https://developer.apple.com/cn/documentation/swiftui/spring) **[V]** | `response` / `dampingFraction` |
| **反方观点：最高的工艺往往是"看不见的、无缓动"** | [invisible-no-easing.md](https://github.com/pproenca/dot-skills/blob/master/skills/.experimental/ios-ui-refactor/references/invisible-no-easing.md) **[V]** |

**[V] 反方观点值得一提**：该来源认为最高工艺的界面在状态变化上**常常没有任何可感知的缓动** —— 这恰好是"过度动画、弹跳感"（读起来像 AI 生成）的解药。

### 5.3 焦点环、状态差量与减弱动效

| 项目 | 来源 |
|---|---|
| **WCAG 2.2 SC 2.4.11 焦点外观 — 官方理解文档** | [understanding/22/focus-appearance-minimum.html](https://raw.githubusercontent.com/w3c/wcag/8784b479fe9da7fe406c24b1d6adf2ce71d9b006/understanding/22/focus-appearance-minimum.html) **[V]** |
| `prefers-reduced-motion` 的 WCAG 技法 | [W3C WAI SCR40](https://www.w3.org/WAI/WCAG21/Techniques/client-side-script/SCR40) **[V]** |
| 焦点可见性的现代 CSS 改进 | [Stephanie Eckles, axe-con (PDF)](https://www.deque.com/axe-con/wp-content/uploads/2021/12/ModernCSSUpgradesToImproveAccessibility_StephanieEckles.pdf) **[V]** |
| shadcn ring token 约定 | [fret — token conventions](https://github.com/Latias94/fret/blob/main/docs/shadcn-style-token-conventions.md) **[C]** |

**[U]** 所有具体焦点环数值、Material 状态层透明度（0.08/0.12/0.16）、Radix 的 9→10 hover 规则、Carbon 的 `$hover-*` 覆盖百分比。**本次唯一确认的阴影字面值是 Ant 的两层 5%/3% 阴影** **[V]**；焦点环按 WCAG 数值 **[C]** 作为合规下限去读。

**[U]** 另：`scale(0.97)` 这类按下缩放，**未找到权威系统推荐或反对**。

---

## 6. 有网络后优先打开的 10 个链接

1. [anthropics/claude-plugins-official — frontend-design SKILL.md](https://github.com/anthropics/claude-plugins-official/blob/b392f51899343f35a203260a4b344803de236d13/plugins/frontend-design/skills/frontend-design/SKILL.md) — §3
2. [Claude Cookbook — Prompting for frontend aesthetics](https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics) — §3
3. [W3C clreq — system-font-mappings](https://w3c.github.io/clreq/others/system-font-mappings.html) — §4.1
4. [JCarterJohnson/vibecoded-design-tells](https://github.com/JCarterJohnson/vibecoded-design-tells) — §1，唯一量化特征排名
5. [tailwindcss.com/docs/theme](https://tailwindcss.com/docs/theme) — §2.2，整个 `@theme` 命名空间
6. [Radix Colors — understanding-the-scale](https://github.com/zhcndoc/radix/blob/main/data/colors/docs/palette-composition/understanding-the-scale.mdx) — §2.4，12 阶语义契约
7. [androidx `MotionTokens.kt`](https://android.googleid.googlesource.com/platform/frameworks/support/+/78929c1b1cdb3ce6deec04b74da5a8cbb30d9360/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/MotionTokens.kt) — §5.1，M3 字面 cubic-bezier
8. [Chrome for Developers — CSS i18n features](https://developer.chrome.com/blog/css-i18n-features) + [MDN text-autospace](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-autospace) — §4.4
9. [smoothui.dev/blog/ai-design-slop](https://smoothui.dev/blog/ai-design-slop) — §1.2，最佳"症状→修法"文
10. [VoltAgent/awesome-design-md](https://raw.githubusercontent.com/VoltAgent/awesome-design-md/main/design-md/ibm/DESIGN.md) — DESIGN.md 语料库，批量提取 token

---

## 7. 对幻月的直接可用结论

1. **可直接照搬的结构（不依赖未读数值）**：
   - Radix 的 **12 阶语义色标**（11/12 阶专用于文字 → 对比度结构化）。
   - shadcn 的**单一 `--radius` 根值 + `calc()` 派生**。
   - Primer 的**按角色分阴影**（resting / floating / inset），而非按大小。
   - Tailwind 的**每个字号自带配对行高**、**单一间距乘数**。
2. **本项目的实际缺陷正对应这份清单**：它缺的正是"一个旋钮派生一切"的 token 层（当前 136 处硬编码颜色、仅 11 处用了变量）。
3. **阴影形状的判据（已确认字面值）**：crafted 阴影 = 多层、低透明（5%/3%）、近偏移、可带负 spread；AI 默认 = 单层、大范围、较高透明。本项目当前是**单层纯黑 `#0004`**，属于后者。
4. **动效的反直觉要点**：最高工艺往往是"看不见的"，重点是**状态反馈的确定性**（每个可点元素都有 hover/active/focus），不是时长与弹跳。本项目当前是**全站 1 处 transition**，属于另一个极端。
5. **中文字体结论**：界面外壳用子集化内置字体（几十 KB），正文依赖系统字体（汉字量不可控）；`text-autospace` / `text-spacing-trim` 可用但**必须特性检测**。
6. **需要网络才能落地的事**：读取上述 [C] 页面的字面数值、以及核实 HarmonyOS Sans / MiSans 的商用许可条款。
