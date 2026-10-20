# M6 正文出处标记与跳转（2026-10-19）

状态：实现和合成回归已通过；不据此提升M5–M9原生系统矩阵为完成。

## 当前行为

- Rust只读接口 `chapter_source_marks` 校验作品/章节归属、当前确认稿的逐字正文及来源片段BLAKE3；只返回当前head、未拒绝资料的来源。UTF-16显示坐标由Rust从原始Unicode标量边界转换，保留BOM、CRLF、组合字符与emoji，不在Dart重算正文hash。
- 正文下划线和Ctrl点击使用同一帧的排版矩形。单字右半侧及RTL边界不再依赖最近caret位置。重叠出处逐项选择；工具栏提供相同动作的键盘/屏幕阅读器入口。
- 编辑、切作品/章节、确认头变化、异步结果迟到和dispose不会把旧出处坐标套用到新正文。编辑后下一帧前的点击也须通过原文精确匹配，父级再过滤当前有效标记。
- 资料可打开对应条目，并从出处详情返回来源章；跳回编辑器前重载章节、复核head和正文。历史版本继续可读，但不装饰新版本。
- 加载失败可见并可刷新，新增/修改资料或绑定出处后刷新。没有改变作者正文、采纳状态或自动发送模型请求。

## 验证

- Rust真实合成数据库专项3/3：`m5/rust-source-marks.txt`，覆盖BOM/CRLF/UTF16、跨作品、脏正文、旧head、拒绝资料和损坏hash。
- 最终普通Flutter及生产DLL回归482/482：`m5/flutter-regression-source-complete.txt`；包含出处异步归属、帧间失效、单字X/Arabic/emoji两侧点击、重叠资料、键盘入口、资料到章节导航与真实DLL。
- Dart无问题：`m5/dart-analyze-source-complete.txt`；Dart格式、Rust格式及严格Clippy见 `m5/dart-format-source-complete.txt`、`m5/rust-format-source-complete.txt`、`m5/rust-clippy-source-complete.txt`。
- 原与目标core的79份快照共158个文件SHA256一致：`m5/core-source-integrity-marks.json`。
- 只读复审发现的“单字右半侧命中失败”已修正，补回归后末次审查无新增确定缺陷。首轮编译/静态失败日志保留，没有删除断言或更新golden。

截至本节2026-10-19验证时，学习Python执行与隔离攻击、桌宠/quiet、IME/DPI/多屏、净机安装仍NOT_RUN。学习执行及部分原生隔离已于2026-10-20补测并修复，详见 `M9-LEARNING-NATIVE-20261020.md`。未恢复已停止的Computer Use、未读取作者库/凭据、未调用真实模型或发布。

## 2026-10-20 收尾验证

- Windows Release通过：`m5/windows-release-source-marks.txt`。
- 独立包通过：`m5/bundle-source-marks.txt`，复制目录 `build/m1-distribution-8c5c1da0f2eb4453b851d337b55258bd`；移除SDK PATH后退出0，缺复制DLL退出1。
- 最新test-support DLL的隔离加密持久库2/2通过：`m5/flutter-owned-source-marks.txt`。
- 后续新增真实工作台UI回归，验证生产repository加载标记并打开关联资料详情；该文件2/2通过：`m5/flutter-source-ui-real.txt`。普通全量482在此新增用例前运行，不将其计作全量483。
- 补充用例后的最终Dart分析无问题：`m5/dart-analyze-source-ui-final.txt`。
