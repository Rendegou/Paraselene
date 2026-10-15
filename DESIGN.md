# 幻月 · Flutter 工作台

视觉基准来自原工程 DESIGN（2026-10-12），本次迁移沿用“安静的写作纸面”，不重做品牌。

| 语义 | 值 |
| --- | --- |
| 正文纸面 | `#faf9f5` |
| 目录外框 / 顶栏 | `#f3f4f6` / `#f8f8f9` |
| 正文 / 次文字 | `#292d34` / `#616976` |
| 强调 / 选中 / 边线 | `#49659c` / `#e8edf5` / `#dfe2e7` |
| 目录 / 顶栏最小高度 | 240 / 56 logical px |
| 舒适 / 宽稿正文上限 | 760 / 920 logical px |
| 正文 / 工具字号 | 20（行高1.85）/ 14（行高1.5） |

权威实现为 `apps/desktop/lib/theme/workbench_theme.dart`。正文使用本地 Notebook Serif，工具使用 Notebook Sans；两者均含 Latin 字形，正文后备为 Notebook Sans、Noto Arabic。四个原有 WOFF2 经 FontTools 转为桌面支持的 TTF，保留字重400/500/600与OFL；Arabic字体独立本地打包。字体来源、SHA256与实际cmap检查见 `docs/evidence/m2/font-provenance.json`。

布局依可用约束：900px以上且字号允许时显示目录，小窗口或大字号使用抽屉；不按设备型号判断。顶栏控件可换行与滚动，不截断译文、不缩小文字。专注模式只收起目录，退出入口持续可达；宽稿只调整阅读宽度。

界面以 Directional 几何镜像，RTL只作为验证 harness，未发布阿拉伯语翻译。当前示例正文以中英开头，阅读区明确LTR，避免UI镜像改变稿件阅读方向。正文/标题从仓库直接显示，伪本地化只扩展界面文案。正式多段落编辑、逐段方向与IME验证属于M3。

M2正文是只读预览。REAL表示实际Rust桥接，旁边持续说明临时合成库、无作者资料、云关闭；SYNTHETIC表示内存替身。不得把fixture验收画面描述成作者库或编辑器已迁移。
