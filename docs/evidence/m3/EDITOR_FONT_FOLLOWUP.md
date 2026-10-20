# 编辑器多语言字体接续验证

日期：2026-10-18。范围：已存在的 M3 编辑器接线之离线字形缺陷；不新增讨论功能、不接作者库或模型。

## 发现与修复

旧 test/failures/m2_windows_chinese_testImage.png 中阿拉伯文整段不可见，而原正文精确保留。ManuscriptEditor 的独立 TextStyle 只指定 Notebook Serif，漏掉主题已有 Notebook Sans/Noto Arabic 回退链。只补该回退链，未调整正文、排版几何或 golden 基线。

新增 test/editor/editor_multilingual_rendering_test.dart 加载项目真实离线字体，从完整工作台取得实际编辑器 layout/painter，并对阿拉伯文栅格 alpha 墨迹检查；同时断言正文与混排 CRLF fixture 完全一致。单独测排版宽度无法检出问题，首版宽度测试即通过，已保留证据。新增墨迹断言修复前失败，修复后通过。

## 证据与边界

- 日志暂存 ../m2-window/editor-arabic-before.txt（宽度断言通过）、editor-arabic-ink-before-final.txt（墨迹断言失败）、editor-arabic-ink-after.txt（补回退链后通过）。首次栅格读取在 fake async 等待，精确中断本次测试并改为 tester.runAsync；该次日志保留，不计通过。
- ../m2-window/editor-font-regression.txt：83项编辑器/窗口/关闭生命周期 PASS。
- 独立 review_window_shell 只读审查无阻断发现。测试使用实际工作台样式，image/picture/painter 清理正确。其覆盖仅限指定阿拉伯文有可见墨迹，缺字方框可能满足断言，不代表准确连写、BiDi或完整混排视觉通过。
- 旧 golden 与8张失败图均保留，未 rebaseline。旧图还显示标题/正文对齐与临时说明行变化，未把它们当作全部预期差异。
- M3完整输入/IME、长文生产化及视觉验收仍未完成；M4/M5不由这一项自动提升。下一步仍是当前编辑器前置缺口核验。
- 最新静态分析 No issues found/退出0（editor-font-analyze.txt），正式 main Release 退出0（editor-font-production-build.txt），独立包校验 PASS（editor-font-production-bundle-check.txt）：移除SDK PATH合成11项退出0、缺DLL退出1。最新目录 build/m1-distribution-ca7b88da67224c0aa4cb0d9538ddb584。
