# 幻月 Flutter 迁移工程

- Windows only，PowerShell 7 `pwsh`；禁止 Bash/powershell.exe。
- 工作仅在本独立目标目录。原 `D:\MyAgent\paraselene-work` 只读；不 reset/清理/修改其源码或作者数据。
- 计划：`D:\MyAgent\paraselene-flutter-migration\MIGRATION_PLAN.md`；逐模块记录 `docs/progress.md` 与 `docs/evidence`。
- 前端开工必读：[前端规范](docs/engineering/frontend-standards.md) → [设计系统](DESIGN.md) → [当前进度](docs/progress.md)。前端规则以这两个现行规范为准；日期化交接、研究方案与 evidence 记录历史或结果，不覆盖当前规则。
- 纯文本保留原 UTF-16/Unicode 标量/BLAKE3 合同；不得归一化或翻译作者正文。
- UI locale、作品/章节语言和输出语言独立。当前 UI 支持规划为 zh-Hans/en；其他 locale 不能伪称已发布。
- Rust 是数据库、业务采纳和正文 hash 的权威。纯 Dart 包不依赖 Flutter、IO或数据库；可执行 probes/tests 允许本地合成文件。
- 不读取 Key、env、认证或作者 DB/作品；不发模型/付费请求。未来仅官方 DeepSeek BYOK，完整材料预览与明确确认。
- 每模块 format/analyze/真实行为测试/可执行验证；mock 不代表 FFI/IME/Windows 通过。NOT_RUN/FAIL 不冒充 PASS。
- 普通函数目标40有效行、上限60，生产模块≤400；公开接口说明单位/错误/副作用。禁止吞错/忽略检查/删功能换编译。
- 自有生产 Dart 代码全量接受 AST 长度/主题边界检查，无历史违规基线；Widget 用命名类组合，不用返回 Widget 的页面构建助手。生成文件与固定第三方快照按规范明确排除，不手改。
- 统一检查入口：`pwsh -NoProfile -File scripts/check-frontend.ps1`；普通全量回归加 `-Test`。检查失败或环境不可用必须非零退出，golden 与原生系统验收单独报告。
- 每新任务立即按 `YYMMDD | [幻月] 动作 + 具体目标` 更新会话标题。
