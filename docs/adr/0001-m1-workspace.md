# M1 独立工作区与桥接版本

2026-10-15，实施中的决定。

- 原工程只读；五个core crate的Cargo.toml/src/tests逐文件复制到rust/core，哈希与原文件一致。原examples不复制、不运行；原领域测试及SQL按源码快照保留。
- crates成员采用独立rust workspace，原Cargo.lock作为初始依赖版本参考；M1新依赖写入新workspace锁，不修改原lock或toolchain默认值。
- Flutter runner位于apps/desktop，引用packages/text_contract；隔离M0纯Dart包而非把Flutter依赖引入其domain。目录调整仅改变工程组织，不改变计划的业务层责任。
- FRB固定2.11.1，Dart、Rust库和生成器同版。pub.dev当前2.13.0要求Dart>=3.9.2，而本机Dart3.8.1；2.11.1声明Dart>=3.4.0。暂不全局升级Flutter SDK，也不采用beta生成器。
- FRB生成器来自维护者GitHub v2.11.1 Windows x64 release，下载归档与发布sha256核验；不使用社区安装脚本。生成文件由该工具生成，禁止手工仿造绑定。
- Visual Studio Build Tools安装已获用户授权，安装主目录与下载缓存放D盘；禁自动重启。工具链真实检查完成前不能称Windows可构建。
- M1仅合成数据/禁云与凭据，未来作者库接管仍须单写者/备份闸门。
