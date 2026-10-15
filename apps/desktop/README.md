# 幻月 M2 Windows 工作台

默认打开中英工作台，以真实Rust DLL读取临时合成作品目录。作品选择、专注与宽稿模式可用；正文目前只读。切换界面语言不改标题、正文或语言元数据；云接口始终返回`cloud_disabled`。

从仓库根目录执行`pwsh -File scripts/check-m1.ps1 -WindowsBuild`；Release包位于`apps/desktop/build/windows/x64/runner/Release`，整个目录一起分发。复制包的`--m1-probe --report=<绝对路径>`用于自动验收，退出0表示全部合同通过。

M2检查入口为`pwsh -File scripts/check-m2.ps1 -WindowsBuild`，依赖已完成的M1原生构建。完整范围、版本和实际截图见根目录`docs/evidence/M2-20261015.md`；`--m1-ui`保留已本地化的原生验收界面。
