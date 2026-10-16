# ADR-004：M4 合成工作区的持久化边界

2026-10-16。状态：设计已选定，待实现和真实跨进程验证，不代表功能通过。

## 问题

M1 的 `open_synthetic` 只接受排他创建的空库或本进程已登记的文件身份；它不能跨进程重新打开已有库。M4 需要重开恢复最近成功提交稿，但尚未授权作者库接管。不能把任意路径加 marker 后当作可信合成库，也不能删除原有来源防护。

## 决定

新增独立、固定位置的 owned-synthetic 入口。旧入口与其未知文件拒绝规则保持。

持久状态采用 Windows 当前用户 DPAPI 保护的完整 SQLite 快照。每次启动先验证、解封 owned-store，创建全新的受来源防护约束的合成 fixture，将受保护快照恢复到新建文件，再打开 SQLite。没有原始作者库导入入口。

SQLite backup API 将连接的逻辑状态复制到内存库，再序列化，避免假定 WAL 文件的裸序列化可以独立恢复。每次成功的应用层变更在会话锁内完成 core 提交、快照、保护、刷新和原子发布，发布成功后才向 Dart 返回成功。

发布失败返回 `durable_save_failed` 并毒化本次会话；拒绝继续用已经推进、却未持久化的 revision 写入。UI 保留内存稿并提供恢复导出。关闭不得把毒化会话重新发布为成功。下次启动恢复最后完整发布的状态。

owned-store 使用排他进程锁；路径和文件拒绝 reparse/hardlink。已有存储损坏必须显示错误，不能默默替换为空库。DPAPI 是当前 Windows 用户下的数据保护，不宣称抵御同用户主动伪造的进程。

## 代价与验证

全量快照增加写入成本，本决策限于 M4 合成工作区；不据此宣称作者大库性能通过。核心源码快照不变。

必须验证两个独立 native 进程的保存/恢复、强制中止后恢复最后成功稿、发布故障与毒化、篡改拒绝及第二写者拒绝。未完成这些验证前，跨进程恢复保持 NOT_RUN。M8 的作者数据接管与安装位置仍单独处理。

## Windows 关闭接缝核查

固定 SDK 的 engine revision 为 `109150893958777c8f2215f6cfd3e89e984e8dea`。本地 runner 已把顶层消息交给 `HandleTopLevelWindowProc`。对应 [engine 注册代码](https://github.com/flutter/flutter/blob/109150893958777c8f2215f6cfd3e89e984e8dea/engine/src/flutter/shell/platform/windows/flutter_windows_engine.cc#L187) 注册了 lifecycle delegate；[关闭分支](https://github.com/flutter/flutter/blob/109150893958777c8f2215f6cfd3e89e984e8dea/engine/src/flutter/shell/platform/windows/windows_lifecycle_manager.cc#L36) 向 framework 请求可取消退出。因此优先使用 `AppLifecycleListener.onExitRequested` 等待保存与 repository close，再返回退出许可。固定 SDK 文档中仍有仅限 macOS/Linux 的旧注释，不能据此代替真实 Windows 验证。

实现后必须用实际 Windows 关闭请求验证成功/失败两路，不能只用调用 Dart 回调的单元测试代替。程序被强制结束不经过此屏障，恢复依据是前述每次已发布的快照。
