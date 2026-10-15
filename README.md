# 幻月 Flutter 迁移

实施依据：[迁移计划](../paraselene-flutter-migration/MIGRATION_PLAN.md)。独立目标，原Tauri工程只读。

M0提供纯Dart Text/Locale合同；M1增加`apps/desktop` Windows诊断客户端、真实FRB/Rust桥接与SQLite合成验收。当前客户端是基础设施验收界面，作品工作台、多语言翻译和作者数据库接管在后续里程碑实施。

Windows PowerShell 7：

```powershell
pwsh -File scripts/check-m0.ps1
pwsh -File scripts/check-m1.ps1 -WindowsBuild
pwsh -File scripts/verify-m1-bundle.ps1
```

SDK路径可通过`-DartExecutable`覆盖；依赖先在纯Dart包内`dart pub get`，Rust校验使用锁定依赖及offline。检查入口逐项失败即非0，证据在`docs/evidence/m0`；不会执行模型、凭据或原工程examples。

多语言从Unicode合同起步：界面语言、作品/章节语言、模型输出语言分离。首批UI locale规划zh-Hans/en；当前包的语言元数据能描述其他language/script/region，并不代表对应界面已翻译/发布。

进度与环境阻塞见[进度记录](docs/progress.md)。

M1环境与验收范围见[真实验收证据](docs/evidence/M1-20261015.md)。绑定重生成入口为`pwsh -File scripts/generate-m1-bridge.ps1`，固定FRB2.11.1；运行前依赖须已恢复，Rust构建使用锁定依赖和offline。M1应用只创建受控临时合成库，不接受未知已有SQLite文件，重开合同限同一进程。
