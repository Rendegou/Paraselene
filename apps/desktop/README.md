# 幻月 M1 Windows 合成验收客户端

此界面运行真实Rust DLL与SQLite合同探针；只使用临时合成数据，云接口始终返回`cloud_disabled`。

从仓库根目录执行`pwsh -File scripts/check-m1.ps1 -WindowsBuild`；Release包位于`apps/desktop/build/windows/x64/runner/Release`，整个目录一起分发。复制包的`--m1-probe --report=<绝对路径>`用于自动验收，退出0表示全部合同通过。

完整范围、版本和限制见根目录`docs/evidence/M1-20261015.md`。多语言产品界面属于M2，当前诊断文案尚未接ARB。
