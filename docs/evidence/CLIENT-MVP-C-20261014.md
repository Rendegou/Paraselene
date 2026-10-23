# 真实共写接线（进行中）

Owner: 01a13583；仅使用工作副本及合成数据。没有读取作者 Key 或发起真实模型请求。

## 原子采纳基础

旧 `novel_apply_patch` 先保存 working copy，再另开事务更新候选状态。后一步失败会留下正文已变、候选仍 pending 的不一致。

新增 memory-core `commit_novel_patch`：同一事务重核完整候选快照、确认头版本、编辑稿 revision 和正文 hash，再写编辑稿与全部/部分采纳状态。候选状态写失败整体回滚；重复或迟到请求拒绝而不再次改正文。采纳不确认正式版本，不改变 head。Tauri 复用 novel-core 差异校验和计算，最终通过该原子入口提交。

验证：

- 针对测试 5/5 PASS：完整采纳与重复请求、状态写故障整体回滚、部分采纳绑定更新与迟到结果、作者竞争保存/头漂移、相同 revision 的正文 hash 不一致。
- `cargo test -p paraselene-memory-core -p paraselene-novel-core ... --offline --quiet` 退出 0：memory-core 107+6+6+6=125 PASS，novel-core 34 PASS，0 filtered/ignored。
- Tauri `cargo check -p paraselene ... --offline` 退出 0。
- Rust AST 指标 36/36，无新增，PASS；保留既有警告和基线。

## 共写接线与合成验证

已接入当前 working copy 的外发预览与一次消费许可，绑定作品、章节、线程、operation、UTF-16 选段、完整正文 hash/revision 与显式确认资料版本。预览仅含选段前后各最多 2000 字及作者带入的确认资料。发送按钮明确显示官方 DeepSeek、模型及 BYOK 费用提示；没有自动发送。

生成操作与作者可编辑线程分开持久化（schema v12）；完整结果和候选块在同一事务提交。取消会丢弃网络 future，迟到结果不落候选；重启后未完成操作显示 interrupted，不自动重发。HTTP 连接、总时长、读空闲分别设上限。采纳重核正文、版本、资料绑定并原子更新编辑稿/候选状态，不确认正式 head。

前端按原章节/线程合并结果，不覆盖未发草稿。修正了取消后旧请求报错关闭新预览、最新候选解决后旧 pending 候选重新出现的竞争问题。

最新检查：

- TypeScript 类型检查 PASS；Web 行为测试 **95/95 PASS**（无过滤/跳过）。包括预览不发送、双击只消费一次、切章响应归属、过期采纳保留稿、取消迟到错误、新旧候选状态。
- memory-core 全量 **130 PASS**（107+6+5+6+6）；之后新增 v12 失败回滚/重开测试，定向 **1/1 PASS**（107 filtered，不能计为全量 131）。novel-core **43 PASS**（34+9，无过滤/跳过），包括完成→跨章拒绝→原子采纳→重复拒绝和后续改稿/拒绝保护。
- llm-core **35/35 PASS**，网络测试只用本机 127.0.0.1 合成响应/假 Key；沙箱网络受限导致初次失败，授权后本机重跑通过。没有请求 DeepSeek。
- Tauri `cargo check` PASS；Vite build PASS。主包 569.13 kB（gzip 184.56 kB），保留 >500 kB 提示。
- TS 指标 7/7、Rust 指标 36/36 均无新增，IPC boundary PASS，未修改基线。
- v12 迁移失败保留 v11 及既有编辑稿，移除合成阻挡表后成功重试并重开。

原生预览验收：合成例子 SHA256 `343A10F24DB66E47A102BFCA3A4FECEE77B014644E841BAA4C6DEAA8DC4B089E`；嵌入 `index-Cv9p7L14.js` SHA256 `266F43AA183F52F3A58AB8418C6C20A339B70EBB747DE9F8EB6A7BFF2DF3BA3A`。打开现有合成作品/选段讨论，草稿恢复；点击“查看外发内容”显示完整 system/user 消息、DeepSeek 模型、费用提示和显式发送按钮；Escape 取消预览，正文和未发草稿保持。正常关闭。例子只注册预览/取消/列表/采纳/拒绝，**不注册真实发送或凭证接口**，所以这不是模型端到端验收。

## 待完成

独立代码审查进行中。真实 Key、付费请求、真实流取消和模型结果原生采纳尚未授权/验证，C 保持 PARTIAL。D 独立标识的合成验收安装包正在构建，不能据 example 宣称安装成功或 CLIENT_MVP_PASS。
