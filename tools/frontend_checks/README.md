# 自有前端检查工具

此开发工具不进入应用运行依赖。使用锁文件固定 analyzer AST 与测试运行器；首次仅从现有缓存恢复：

```powershell
pwsh -NoProfile -File scripts/check-frontend.ps1 -RestoreTools
```

在仓库根目录单独扫描某个目录：

```powershell
dart --packages=tools/frontend_checks/.dart_tool/package_config.json tools/frontend_checks/bin/check_frontend.dart --root . --scope apps/desktop/lib/workspace/ --output build/workspace-metrics.json
```

默认范围是 `apps/desktop/lib/` 与 `packages/text_contract/lib/`，仅排除 `lib/native/generated/` 和 `lib/l10n/generated/` 两个真实生成目录；不会因自有文件被命名为 `.g.dart` 而跳过检查。递归扫描不跟随目录链接，空范围返回退出码 2。

有效行由非注释 AST token 实际覆盖的源代码行计算，字符串中的跨行内容计入。文件上限 400；普通函数、方法、具身构造与匿名回调的函数体上限 60，嵌套回调同时计入自身和外层。参数和构造初始化列表只计入文件行数。门禁配合 formatter 阻止压行；不使用历史违规基线。

主题边界检查涵盖显式/隐式颜色和 TextStyle 构造、Colors 引用及裸字体族，允许主题内定义和业务消费角色。所有普通 `Widget`/`Widget?` 返回辅助方法必须改用命名 Widget；`@override build` 和框架 builder 回调正常保留。文字字号常量不得小于 12；空错误回调与 `.ignore()` 作为可直接确认的静默失败报告。

`check_arb.dart` 不依赖 analyzer，可由 `scripts/check-m2-l10n.ps1` 独立调用。它汇总键、description、类型和嵌套 ICU 占位符错误，遵守项目 `use-escaping: true`。它不替代 Flutter gen-l10n 对完整 ICU 语法与生成结果的验证。

工具负向测试固定在统一静态门禁中执行；直接通过锁定 package_config 调用已缓存的 test 入口，不执行隐式 pub 网络恢复。测试临时文件位于当前检查 run 的 build 子目录。

完整工程规则见 [前端规范](../../docs/engineering/frontend-standards.md)。
