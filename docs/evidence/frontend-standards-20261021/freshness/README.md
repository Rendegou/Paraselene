# 本地化生成物 freshness 门禁（2026-10-21）

修补默认前端门禁只检查 ARB 元数据、格式和 analyze、不能发现“仅修改现有文案但保留旧生成物”的缺口。新增 `scripts/check-l10n-freshness.ps1`，并将 `l10n-freshness` 设为 `scripts/check-frontend.ps1` 的默认必选项；入口已有参数保持不变。

## 隔离生成与比较

- 使用本机已缓存的 Flutter 3.32.1 / Dart 3.8.1，framework revision `b25305a8832cfc6ba632a7f87ad455e319dccce8`。
- `FlutterExecutable` 定位同一 SDK，直接通过 Dart 运行其 `flutter_tools.snapshot` 和现有 `package_config.json`；不执行 bat 引导、pub get 或依赖下载。缺可执行文件、快照或包配置退出 3。
- 在仓库 `build/l10n-freshness/<随机 GUID>/project` 中按原始字节复制 pubspec、l10n.yaml、ARB（配置需要时也复制 header）。SDK 的 YAML/path 包解释文件选项，并在生成前拒绝绝对路径、父目录逃逸和与输入混用的输出目录。
- 工作目录和 `gen-l10n --project-dir` 都指向临时项目。SDK 官方帮助支持该参数；当前 SDK 的 `packages/flutter_tools/lib/src/localizations/gen_l10n.dart` 第 50 行说明输出换行随 pubspec 字节变化，因此不能用手写的简化 pubspec 替代真实输入。
- 比较临时输出与真实 `apps/desktop/lib/l10n/generated` 的相对路径全集，包括非 Dart 文件；共同路径读取原始字节比较。缺失、多余或字节不同均退出 1，不使用 git diff。
- 每次真实生成记录源输入/生成物的前后 SHA-256 清单，发现变化也失败。真实应用配置与生成物不被写入；临时项目及日志保留在 build，便于排查。

官方配置说明：[`synthetic-package: false` / `output-dir`](https://github.com/flutter/website/blob/main/sites/docs/src/content/ui/internationalization/index.md)。

## 实际命令与退出码

在仓库根目录以 PowerShell 7 执行。官方 Flutter 工具需要写 SDK 缓存锁，验证已通过相应沙箱权限；未恢复依赖。

| 命令 | 退出码 | 结果 |
| --- | ---: | --- |
| `pwsh -NoProfile -File scripts/check-l10n-freshness.ps1 -ReportDirectory docs/evidence/frontend-standards-20261021/freshness/current` | 0 | 当前 3 个生成文件路径、字节一致；输入/生成物哈希一致 |
| `pwsh -NoProfile -File tools/frontend_checks/test/l10n_freshness_test.ps1 -ReportDirectory docs/evidence/frontend-standards-20261021/freshness/fixtures` | 0 | 9 个真实 SDK 样本符合预期 |
| 单独门禁指定不存在的 `-FlutterExecutable`，报告目录 `missing-tool` | 3 | NOT_RUN，未伪称 PASS |
| 默认入口指定不存在的 Dart/Flutter，报告目录 `missing-tools-default-gate` | 3 | `l10n-freshness` 仍被选中，记录 NOT_RUN/3；所有已选检查不可用 |
| `pwsh -NoProfile -File scripts/check-frontend.ps1 -ReportDirectory docs/evidence/frontend-standards-20261021/freshness/default-gate` | 1 | 新 freshness 必选项 PASS/0；其他结果见下段 |

默认入口本轮：AST 139 文件、0 违规；既有 Dart 工具测试 21；ARB 336 键 × 3；工具/应用/text analyze 均 PASS。唯一失败为并行任务新增 `test/cowrite/deepseek_settings_test.dart` 的 app-format（`--output=none`，未修改该文件）。该次完整入口如实记录 FAIL，不能据此声称所有前端检查通过。产品普通回归、golden、Release 与真实系统验收不属于本次选中项。

## 永久合成样本

`tools/frontend_checks/test/l10n_freshness_test.ps1` 在 build 下创建独立合成应用，由官方 gen-l10n 生成初始文件，再逐个改动样本；不依赖产品生成物作为成功基线。

| 样本 | 被测脚本实际退出码 | 断言 |
| --- | ---: | --- |
| fresh-output | 0 | 相同输入/输出通过 |
| existing-message-changed | 1 | 只改现有消息文本，`Changed` 非空 |
| generated-file-missing | 1 | 删除生成文件，`Missing` 非空 |
| extra-nondart-file | 1 | 添加嵌套 `.bin` 文件，`Extra` 非空 |
| raw-byte-only-change | 1 | 仅追加换行字节，`Changed` 非空 |
| generator-failure | 1 | 无效 ARB，官方生成器自身退出 1 |
| escaping-output-rejected | 1 | 配置输出父目录逃逸被拒绝，无逃逸目录 |
| missing-flutter-tool | 3 | 缺 Flutter 不运行生成，不通过 |
| missing-dart-tool | 3 | 缺 Dart 不运行生成，不通过 |

`fixtures/summary.json` 记录 9/9 PASS；生成失败样本中 `GeneratorExitCode: 1`、`SourceUnchanged: true`。缺工具样本在报告初始化调整后单独复验，仍均退出 3 并写入 NOT_RUN 报告。3 个 PowerShell 文件均经当前 PowerShell parser 验证，无语法错误。

`fixtures/original-app-before.json` 与 `fixtures/original-app-after.json` 的 8 个路径/SHA-256 完全相同，覆盖 pubspec、l10n.yaml、3 个 ARB 和 3 个真实生成文件。既有 dirty 内容（包括历史 golden 差异）保留，未提交或推送。
