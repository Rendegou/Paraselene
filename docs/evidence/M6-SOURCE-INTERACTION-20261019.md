# M6 正文出处交互收尾证据（2026-10-19）

范围：核对并验证正文出处装饰、Ctrl 点击、重叠出处菜单入口与从出处定位回正文。原工程只读；未访问作者库、真实凭据或真实模型。

## 实际变更

- `apps/desktop/lib/editor/editor_basic_controller.dart`：修正测试控制器宽度更新在构建期 `notifyListeners()` 导致 `EditorViewport` 构建期 `setState` 的问题；现在与生产 `EditorInputClient.width()` 一致，仅更新布局，由当前构建直接读取新布局。
- `apps/desktop/lib/lore/source_mark_controller.dart`、`apps/desktop/lib/workspace/presentation/manuscript_editor.dart`、`apps/desktop/lib/workspace/presentation/source_navigation.dart`：补齐项目门禁要求的控制流花括号，无逻辑变更。
- `apps/desktop/test/source_marks_test.dart`：新增出处定位回归，覆盖跨章节重载后 Unicode 标量 anchor → UTF-16 选区（`A👩‍💻B` 中 `1..4` 标量映射为 UTF-16 `1..6`）、旧 head 拒绝定位、脏正文拒绝定位。

## 命令与结果

| 检查 | 命令摘要 | 结果 |
| --- | --- | --- |
| Dart 格式 | `dart format`（相关 5 个文件） | 退出 0；141 个文件全目录检查 0 changed |
| 静态检查 | `flutter analyze --fatal-infos` | 退出 0，No issues found |
| 出处定向 | `flutter test test/source_marks_test.dart test/source_marks_real_ffi_test.dart test/editor/editor_scene_viewport_test.dart test/editor/editor_input_client_test.dart` | 退出 0，32/32 PASS |
| Rust 出处 | `cargo +stable-x86_64-pc-windows-msvc test -p paraselene-application source_mark_tests --locked --offline` | 退出 0，3/3 PASS |
| 普通 Flutter 全量 | 所有 `test/**/*_test.dart`，排除 owned-store 专用 test-support DLL，排除 2 个既有 golden | 退出 0，478/478 PASS |
| Golden 全量 | 同上但包含 `m2_golden_test.dart` | 2 个既有 golden 差异失败；未重写基线，其余 478 PASS |
| Release | `flutter build windows --release` | 退出 0，产出 `apps/desktop/build/windows/x64/runner/Release/paraselene_flutter.exe` |
| 独立包 | `scripts/verify-m1-bundle.ps1` | PASS；移除 SDK PATH 后 probe 退出 0，缺 `paraselene_bridge.dll` 退出 1 |

## 日志与产物

- 格式：`docs/evidence/m5/m6-source-format-20261019.txt`、`docs/evidence/m5/m6-source-format-check-20261019.txt`
- 静态检查：`docs/evidence/m5/m6-source-analyze-20261019.txt`
- 定向出处与编辑器：`docs/evidence/m5/m6-source-interaction-20261019.txt`
- Rust 出处：`docs/evidence/m5/m6-rust-source-marks-20261019.txt`
- 普通全量回归：`docs/evidence/m5/m6-flutter-regression-nogolden-20261019.txt`
- 含既有 golden 的全量差异：`docs/evidence/m5/m6-flutter-regression-20261019.txt`
- Release：`docs/evidence/m5/m6-windows-release-20261019.txt`
- 独立包：`docs/evidence/m5/bundle-20261019/copied-bundle-status.json`

## 边界

本次只完成 M6 正文出处装饰/Ctrl 点击及出处定位的代码面与合成/真实 DLL 验收。实际 Windows 原生交互矩阵、净机安装、真实模型、作者数据接管仍未执行；两个 golden 差异是既有基线问题，未在本次范围内更新。
