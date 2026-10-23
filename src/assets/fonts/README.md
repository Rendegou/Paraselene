# 离线中文字体

2026-10-12 从 Google Fonts 官方仓库取得 Noto Sans SC / Noto Serif SC 可变字体，按 SIL OFL 1.1 打包。许可证保留在此目录，也由 `public/fonts/` 复制进发布目录。

- Sans 来源：https://github.com/google/fonts/tree/main/ofl/notosanssc
- Serif 来源：https://github.com/google/fonts/tree/main/ofl/notoserifsc
- 构建工具：fonttools 4.66.1、brotli 1.2.0，仅用于资产制作，不是应用依赖。
- 重建：`python scripts/quality/prepare-studio-fonts.py <font-tools-dir> <source-dir>`，来源目录文件名 `NotoSansSC.ttf`、`NotoSerifSC.ttf`。
- 固定 Sans 400/500/600、Serif 400；保留 Latin、标点、CJK 扩展 A/统一汉字与全角字符。每个文件覆盖 28,124 或 28,150 个码点。未覆盖的罕见汉字、emoji 使用本机 fallback，不声称覆盖所有 Unicode。
- CSS 使用内部别名 Notebook Sans / Notebook Serif；页面通过 `document.fonts.load` 检查实际加载并设置 `data-local-fonts`。界面不依赖远程字体服务。
- 四个 WOFF2 合计约 17.5 MB。宽覆盖保证离线写作，不把本轮称作字体体积优化。

SHA-256：

```text
NotoSansSC-Regular.woff2  8f08687884967709fcef6276470fab490cf9802c712e897685e04e50e1e08483
NotoSansSC-Medium.woff2   ff55877b32dce49ea40acb106d15399e45ba3e29beea4f7d8a72362bd4337c3b
NotoSansSC-Semibold.woff2 6bdf8b27e3f6fd0542e2c93c8f8f6f7d95ffd4334f38f51782ec818c389a6ad6
NotoSerifSC-Regular.woff2 39119be8a687db78da9c9f48d8df17cfc03ce9aae395225fd482484e265d1b8c
```
