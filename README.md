# 幻月 Flutter 迁移

实施依据：[迁移计划](../paraselene-flutter-migration/MIGRATION_PLAN.md)。独立目标，原Tauri工程只读。

## 当前状态（2026-10-20）

生产编辑器（自定义 raw UTF-16 排版/绘制/输入、段下讨论线程、出处装饰）已经接入工作台；视觉层按原 TS 版对齐；操作一致性整改 R01–R16 按 [整改文档](docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md) 执行，批次 A–E 完成，批次 F（文档入口整理与文件清理重建）进行中。当前工作树未提交，真实 Windows IME/桌面矩阵、生产/测试 FFI DLL、外网模型与净机安装仍为 NOT_RUN，不能据此宣称全产品替代完成。

- 进度与当前里程碑：[docs/progress.md](docs/progress.md)
- 整改证据索引：[docs/evidence/operation-parity-20261020/README.md](docs/evidence/operation-parity-20261020/README.md)
- 视觉对齐证据：[docs/evidence/UI-PARITY-20261020.md](docs/evidence/UI-PARITY-20261020.md)
- 中文注释规范与记录：[docs/engineering/comment-style-20261020.md](docs/engineering/comment-style-20261020.md)、[docs/evidence/COMMENT-PASS-20261020.md](docs/evidence/COMMENT-PASS-20261020.md)

目标测试入口（`apps/desktop` 下）：

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test bin
flutter analyze --fatal-infos
flutter test test/operation_parity
flutter test test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart test/source_marks_test.dart test/m2_locale_test.dart
```

以下 M0–M2 段落描述的是当时里程碑状态，保留为历史记录。

M0提供纯Dart Text/Locale合同；M1增加实际FRB/Rust桥接与SQLite合成验收；M2增加中英工作台、作品选择、目录、专注/宽稿及只读正文预览。默认使用真实桥接的临时合成库，作者数据库接管与正文编辑属于后续里程碑。

Windows PowerShell 7：

```powershell
pwsh -File scripts/check-m0.ps1
pwsh -File scripts/check-m1.ps1 -WindowsBuild
pwsh -File scripts/verify-m1-bundle.ps1
pwsh -File scripts/check-m2.ps1 -WindowsBuild
```

SDK路径可通过`-DartExecutable`覆盖；依赖先在纯Dart包内`dart pub get`、桌面包内`flutter pub get`，Rust校验使用锁定依赖及offline。检查入口逐项失败即非0，证据分别在`docs/evidence/m0`、`m1`、`m2`；不会执行模型、凭据或原工程examples。

多语言从Unicode合同起步：界面语言、作品/章节语言、模型输出语言分离。首批UI locale规划zh-Hans/en；当前包的语言元数据能描述其他language/script/region，并不代表对应界面已翻译/发布。

进度与环境阻塞见[进度记录](docs/progress.md)。

M1环境与验收范围见[真实验收证据](docs/evidence/M1-20261015.md)。绑定重生成入口为`pwsh -File scripts/generate-m1-bridge.ps1`，固定FRB2.11.1；运行前依赖须已恢复，Rust构建使用锁定依赖和offline。M1应用只创建受控临时合成库，不接受未知已有SQLite文件，重开合同限同一进程。

M2验收与截图见[工作台证据](docs/evidence/M2-20261015.md)。启动Release包中的`paraselene_flutter.exe`，点击“创建示例材料”体验中英切换；这些固定示例并非作者作品，仓库正常关闭时清理临时库。进程直接结束时不保证异步清理完成。`--m1-ui`保留原生诊断界面，`--m1-probe --report=<绝对路径>`保留自动验收入口。整个Release目录一起分发，或使用`build/paraselene-m2-windows-x64.zip`。
