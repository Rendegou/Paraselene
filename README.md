# 幻月 Flutter 迁移

实施依据：[迁移计划](../paraselene-flutter-migration/MIGRATION_PLAN.md)。独立目标，原Tauri工程只读。

当前模块：`packages/text_contract`（纯Dart），`rust/contract-oracle`（合成向量/真实BLAKE3校验）。这些是迁移基础合同，不是Flutter桌面客户端或已连接数据库的界面。

Windows PowerShell 7：

```powershell
pwsh -File scripts/check-m0.ps1
```

SDK路径可通过`-DartExecutable`覆盖；依赖先在纯Dart包内`dart pub get`，Rust校验使用锁定依赖及offline。检查入口逐项失败即非0，证据在`docs/evidence/m0`；不会执行模型、凭据或原工程examples。

多语言从Unicode合同起步：界面语言、作品/章节语言、模型输出语言分离。首批UI locale规划zh-Hans/en；当前包的语言元数据能描述其他language/script/region，并不代表对应界面已翻译/发布。

进度与环境阻塞见[进度记录](docs/progress.md)。
