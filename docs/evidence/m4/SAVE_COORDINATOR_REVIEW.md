# M4-3 SaveCoordinator 审查

审查范围：SAVE_COORDINATOR_BRIEF.md、SAVE_COORDINATOR_REPORT.md、build/reviews/m4-3-save-coordinator.diff、当前生产文件和测试，以及现有定向检查日志。未运行 SDK、测试或格式化；未修改实现。未审查后续 UI、原生持久化或窗口关闭接线。

## Spec verdict: FAIL — 1 actionable finding

### [P2] 重入通知会把旧正文再次发给后续订阅者

位置：apps/desktop/lib/domain/editing/save_coordinator.dart:266–270（_publish）。

_publish 在进入监听器循环前捕获 slot.state。设两个监听器 A、B 按此顺序订阅；保存 first 的最后 saved 通知到达 A 时，A 同步 edit(..., 'latest')。edit 触发嵌套通知，B 先收到 latest 的状态；嵌套通知返回后，外层循环继续把捕获的 first/saved 状态发给 B。于是同一订阅者收到的正文与 editSequence 倒退，且此刻 getState 已经是 latest。消费通知更新编辑器或视图状态的 B 会被旧回执正文覆盖，违反保存中的新输入不被旧回执覆盖的合同。即使后续 drain 再发送 latest，该 API 仍已向观察者交付旧正文；最终一致不能保证编辑器输入安全。

建议：明确串行化通知语义，保证每个监听器看到的 generation/editSequence 不倒退；例如把重入发布排队，或在每次回调前检测当前状态/槽位仍匹配本轮快照并停止过期轮次。补充两个监听器的确定性测试：A 在最后 saved 回调 edit 新正文，B 记录全部正文与序号；断言 B 从未在见到新正文后又收到旧正文。保留现有错误隔离和保存 flight 屏障。

## Quality verdict: CHANGES REQUESTED

单槽位串行写入、组合身份键、快照 CAS、失败保留正文和 revision、显式 retry、final notification 时禁止 release/hydrate、flushAll 重查、回执身份/正文/revision 验证均有清晰实现与定向覆盖。生产文件分别为 284/49 行，函数规模符合本切片限制；依赖保持 dart:async 和既有 repository 合同，没有引入框架或 DI 迁移。正文直接保存，没有 Unicode 或换行规范化；失败采用稳定机器码。

上述 P2 属于可观察 API 正确性问题，应在本切片完成前修正。现有“edit during final saved notification”仅有一个监听器，只证明内部 state/drain 保留新输入，未验证其他观察者的通知顺序。

## 证据与边界

现有 checks/m4-3-tests.txt 显示 18/18 PASS；checks/m4-3-analyze.txt 显示 No issues found；checks/m4-3-format.txt 显示 5 files、0 changed。报告对替身状态机测试与真实磁盘/FFI/Windows UI 验收的界限描述准确。本审查采用静态控制流推导上述确定性重入序列，没有重跑测试，也没有声称原生组合验收通过。

## P2 修正复审 — 最终结论

Spec verdict: PASS。

Quality verdict: PASS。此前 P2 已关闭，本次修正范围没有新增 actionable finding。

已检查 _publish 的状态对象及当前槽位身份检查：监听器 A 重入 edit/hydrate 后，外层循环在调用 B 前停止，因此不会在嵌套新状态通知之后交付旧状态。退订检查同时避免调用本轮期间已移除的监听器。异常隔离和 flight 所有权保持不变。

新增双监听器回归测试逐项断言 B 的正文、editSequence、status 通知序列，并在第二次保存完成后检查最终 saved 与 listenerErrors 为空，直接覆盖初审反例。现有日志已更新为 19/19 tests PASS、analyze 无问题、format 5 files 0 changed。复审未运行 SDK/测试，仅检查修正、回归及既有日志。真实数据库/FFI/Windows UI 组合验收仍属于后续切片。
