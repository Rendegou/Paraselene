# M4-3 保存协调器实施合同

依据原端 `src/features/studio/native/saveCoordinator.ts` 及其 8 组行为测试，应用于新的 Rust repository。原端只读，不搬运作者数据。

## 必须保留的行为

- 以 `(workId, documentId)` 无歧义组合键隔离槽位，正文只在当前已加载槽位内持有；不会把整部作品正文装进全局状态。
- hydrate 只接收干净、无在途写入的槽位；每次成功 hydrate 增加 generation。
- edit 同步记录原始正文（包括空字符串）与 editSequence。相同文本不重复增加序号。保存中的编辑不被回执覆盖。
- 350ms 防抖；提交快照携带原 CAS revision。单槽位串行 drain，await 期间多次编辑合并成下一次最新提交。
- 回执只推进对应槽位的 revision/savedSequence。新输入仍 dirty，继续 drain，不能把旧 body 写回编辑器。
- flushDocument 等到该槽位既不 dirty、也无 flight；flushAll 在所有槽位完成后再次检查，捕获等待期间新增编辑。
- 明确 dirty/saving/saved/conflict/error 状态。冲突按稳定错误码识别；失败保留正文与原 revision，阻断切换/关闭，直到显式 retry。
- retry 不刷新 revision、不自动覆盖远端；失败中的新输入保留错误状态，等待重试。
- release 要求干净、无 flight、无订阅；重新 hydrate 获得新 generation。
- Timer、订阅、future 错误均有归属；无未处理的异步异常。不得在 dispose 中悄悄清掉 dirty 文本。
- repository 回执必须匹配提交的作品/章节、正文和有效 revision；错误身份不能污染其他槽位。

## 测试

复刻上述原端 8 组场景，并覆盖防抖时间、flush 重入、相同 chapterId 不同 workId、保存失败后继续输入、最后回执时仍处于 flight、不允许过早 release、无声 future 错误检查。控制后端完成时机以证明竞态，不用 sleep 猜测顺序。

测试替身证明状态机；真实 SQLite/FFI 已由 M4-1/M4-2 验证，M4-6 再组合真实 repository 跑 Windows 流程。不能把替身结果称作磁盘或原生输入验收。

## 与后续切片的接缝

确认版本会保留并 rebase 编辑稿、推进 revision。确认或回滚后必须在干净槽位重新 hydrate 原生 snapshot；不能把旧 revision 留给下次保存。

M4-4 控制器负责切章/切作品 busy 屏障；M4-5 在实际关闭请求中等待所有正文与 UI 偏好保存完成。`durable_save_failed` 表示后续 owned-store 会话已毒化，需保留内存稿、导出和重新打开，不得自动刷新 CAS 掩盖失败。
