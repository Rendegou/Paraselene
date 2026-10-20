# 中文代码注释规范（Google 风格口径，2026-10-20）

适用范围：`apps/desktop/lib/**`、`apps/desktop/windows/runner/**`、`rust/application/src/**`、
`rust/bridge/src/api/**` 与 `rust/bridge/src/{api,lib}.rs`、`packages/text_contract/lib/**`。
测试、`integration_test`、`scripts` 只补文件头注释。

## 一、原则（对齐 Google 代码文档惯例）

1. 注释解释**契约、边界、原因与取舍**，不复述代码字面。
2. 文件头说明模块职责、所在层、外部依赖与关键不变量。
3. 公开类型/函数/字段必须有文档注释；私有实现只在“为什么这样”不明显时加注释。
4. 完整句子，中文句号结尾；不写作者、日期、变更流水、感叹号或 emoji。
5. 不写无用注释（`// 自增`）、不保留注释掉的代码、不堆 TODO 清单。
6. 新增注释用中文；**已有英文注释保留**，除非与代码事实冲突（冲突时改为中文并说明原因）。

## 二、Dart

- 文件头统一用 `//` 中文注释（避免 `part of` 文件出现悬空 library doc comment）。
  内容：模块职责、读写边界、是否依赖 Flutter/IO、关键不变量。
- 公开 class / mixin / 扩展 / 顶层函数 / 公开 getter / 公开方法：`///` 文档注释。
- 首行一句话概述；空一行后可补充契约：单位、错误码、异步/取消、所有权、线程、
  是否写库、是否触碰作者正文等。
- 命名参数较多时用散文说明用途，不使用 `@param` 标签。
- 示例：

```dart
/// 作品目录与当前章节的只读视图快照。
///
/// 仅缓存标题与顺序；正文按章按需读取，禁止把整部作品常驻内存。
/// 读取失败统一抛出 [WorkspaceFailure]，错误码保持稳定以支持本地化。
```

## 三、Rust

- 模块文件顶部 `//!` 中文模块说明（若已有 `//!` 英文说明，保留英文并补一段中文契约）。
- `pub` 类型/函数/常量使用 `///`；需要时使用以下小节：
  - `# 参数`：逐项说明单位与约束（ID 为 UUID、revision 为 CAS 版本等）。
  - `# 返回`：返回值的所有权/JSON 形状/空值语义。
  - `# 错误`：稳定错误码与触发条件。
  - `# 并发`/`# 事务`：锁、事务、取消、跨 await 约束。
- 测试模块文件头用 `//!` 说明覆盖范围与“不代表什么”。
- 禁止修改 `rust/core/**`（固定快照哈希）与 `rust/bridge/src/frb_generated.rs`（生成物）。

## 四、C++（Windows runner）

- 文件头 `//`：类/窗口职责、线程模型（UI 线程/COM）、生命周期、失败策略。
- 类与成员函数前 `//` 注释契约；涉及 HWND/COM/WebView2/句柄所有权、关闭顺序、
  错误码（HRESULT）与安全边界时必须说明。
- 不添加 Doxygen 专属标签；沿用 Google C++ 注释风格。

## 五、禁止项

- 修改逻辑、字符串、资源、格式化以外的代码；删除断言或测试。
- 触碰 `lib/l10n/generated/**`、`lib/native/generated/**`、`rust/bridge/src/frb_generated.rs`。
- 在注释中写作者姓名、日期、私人路径、Key、作者数据示例。
- 用注释解释明显的实现细节，制造噪音。

## 六、验收

- Dart：`dart format` 后 `dart analyze` 无新增问题。
- Rust：`cargo check` 通过；不运行会重排生成文件的全局 `cargo fmt`。
- 全部完成后由 Lead 统一跑 format / analyze / 测试 / Release 构建，确认只有注释变化。
