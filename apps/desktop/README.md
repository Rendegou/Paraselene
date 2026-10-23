# 幻月 Windows Flutter 应用

本包是当前写作工作台，生产编辑器支持 raw UTF-16 排版/输入、原位讨论与出处装饰，包含资料、版本、恢复和既有辅助模块入口。产品范围、最新失败/未测项分别见[产品目标](../../docs/product-scope.md)和[当前状态](../../docs/progress.md)。

## 运行与数据边界

[main.dart](lib/main.dart) 默认启动工作台并装配自绘窗口外壳；`--system-title-bar` 保留系统标题栏回退。默认仓库是 Rust 真实桥接的应用自有持久合成库，按当前 Windows 用户 DPAPI 密封，关闭不删除；与临时 fixture 区分，详见[架构合同](../../docs/engineering/architecture-contracts.md)。不能据此打开任意作者数据库。

`--m1-ui` 打开诊断验收界面；`--m1-probe --report=<绝对路径>` 运行 M1 合成探针并写报告，退出 0 仅表示该探针合同通过，不代表整个应用验收。模型预览/设置/发送接缝已实现；日常开发不读取真实 Key、不外发模型请求，真实模型仍未验收。

Release 构建目录为 `apps/desktop/build/windows/x64/runner/Release`，分发须包含整个目录及依赖 DLL/data/fonts，不能只复制 EXE。干净系统、IME/DPI/多屏与发布认证独立记录。

## 开发与验证

从仓库根目录读取 [AGENTS](../../AGENTS.md)、[前端规范](../../docs/engineering/frontend-standards.md)、[DESIGN](../../DESIGN.md)与[Agent 工作流](../../docs/engineering/agent-workflow.md)，按任务选择相关部分。

```powershell
pwsh -NoProfile -File scripts/check-docs.ps1
pwsh -NoProfile -File scripts/check-frontend.ps1
pwsh -NoProfile -File scripts/check-frontend.ps1 -Test
```

运行目录为仓库根，依赖须按锁文件恢复，原生测试使用正确的生产/test-support DLL。M1/M2/M4 专项脚本和旧证据保留用于其范围验收；旧 M2 的“只读正文”状态不描述当前工作台。各项实际结果只在当前进度维护。
