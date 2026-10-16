# M4 独立审查记录

2026-10-16。本文件记录各切片的审查结论，不替代测试日志，也不代表 M4 整体完成。

## M4-1 Rust 业务层

审查者：独立代理 `m4_rust_review`。

首次结论：spec 未完成、quality 要求修改。发现建章/排序分次提交、确认未绑定先前核对的上下文、UI session 字段类型缺失；迁移计数和部分真实故障测试欠缺。

修正后复审：上述问题已解决；另发现作品选择与最近记录分次持有 Session 锁可能交错。

最终修正：作品选择和工作区快照分别持有单个 State guard；增加六线程快照一致性、触发器失败保留旧选择、关闭后拒绝调用测试。

最终结论：**spec PASS，quality PASS**。审查只读，未重复运行 SDK。运行证据见 `checks/m4-1-hardening-*.txt`、`checks/m4-1-selection-*.txt`。

## M4-2 Repository 与桥接

审查者：独立代理 `m4_repository_review`。

首次发现合成/真实 UI session 数字规则不一致。依据原端有限 number 合同统一为 schemaVersion 数值 1、有限小数滚动坐标、出现时拒绝 null；共用真实 DLL/合成测试。

确认接口已改为先获取精确正文和不透明核对令牌，再原样传回令牌；移除直接 head/revision 确认入口。

最终结论：**spec PASS，quality PASS**。审查只读，未重复运行 SDK。运行证据见 `checks/m4-2-*.txt` 和新接口后的 `checks/m4-1-hardening-dart-ffi.txt`。较早日志对应较早接口，不能作为最终接口唯一依据。

## M4-3 保存协调器

审查者：独立代理 `m4_save_review`。

首次发现双监听器重入时，新状态嵌套发布后旧广播仍继续，后一个监听器可能收到倒退正文。修正后发布会检查状态与槽位身份，停止过期广播，跳过已取消订阅者。

新增双监听器精确通知顺序回归；19/19 定向测试、analyze、format 通过。最终结论：**spec PASS，quality PASS**。审查只读未重复 SDK；完整报告见 `SAVE_COORDINATOR_REVIEW.md`。此结果只验证状态机，真实 Windows 关闭组合尚未验收。

## M4 全量变更（owned 持久化 + 控制器 + UI + 关闭/导出）

审查者：独立代理（Kimi Code 会话内 explore 代理，2026-10-16）。

结论：**可交付**。五条设计合同机制级验证均满足：350ms 防抖与 do-while 复查、CAS 冲突不推进 revision、owned store 会话锁内发布与毒化、编辑器仅外部重置重写、确认令牌绑定精确正文与上下文、两阶段关闭与导出读回校验。

低危发现与处置：
1. 偏好 flush 丢失更新竞态（await 期间新偏好被无条件清脏覆盖）→ 已修（版本号比对，仅值未变才清脏），补回归测试 `a scroll during an in-flight prefs write still lands`。
2. restoreSession 不在 `_busy` 屏障内，编程式并发可致 editing 与 controller 章节不一致；当前 UI 在 loading 期禁用全部动作，生产不可达 → 记录为已知问题（M5 编辑器落地前关闭）。
3. 脏稿 dispose 链跳过原生资源释放（teardown/热重载场景）→ 已修（捕获后继续释放，脏稿仍留在 loadedStates 可见，不静默丢弃），补回归测试 `dispose with dirty text completes without skipping release`。
4. 强杀残留 `paraselene-m1-owned-*` 临时目录无清扫 → 记录为已知问题（资源累积，不影响正确性）。
5. `_busy` 期间的关闭请求被误报为"关闭失败"提示 → 记录为已知问题（无数据损失，仅提示语义）。

审查只读，未重复 SDK。运行证据见 `checks/m4-commands.json`。
