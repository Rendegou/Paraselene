# CLIENT-MVP B：隔离SQLite原生恢复验收

日期：2026-10-13。负责人：a_native_validation；工作副本 `D:\MyAgent\paraselene-work`。

状态：**B_NATIVE_PARTIAL / FINAL_REBUILD_PENDING**。以下明确区分初版B编译与最终修正，不把自动测试、未测边界或源码存在当原生PASS。

## 隔离与构建身份

使用 `src-tauri/examples/native_workspace_probe.rs`；唯一测试DB `D:\MyAgent\paraselene-work\.client-mvp-tests\native-b.db`，只注册正式作品/章节/资料/线程/保存/导出IPC，无Key/model命令。未访问appdata或作者库，未执行网络模型请求。

初版B example binary SHA256 `52698F017075291DF1D7D2DFF2BE761AFC441FF8BD94675A45F8A6E93B4DA2E6`；本次启动前dist主资产 `index-Bpk4JaOD.js` SHA256 `B9C0F65747173BCE30BDD0FBD93ADE94CFD17E6FD70AD0D94EE5D689A8E5E7F4`。开发example，不是安装产物。

PowerShell7启动方式：

```powershell
$env:PATH='D:\MyAgent\.cargo-target\debug;C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
Start-Process -FilePath 'D:\MyAgent\.cargo-target\debug\examples\native_workspace_probe.exe' -ArgumentList 'D:\MyAgent\paraselene-work\.client-mvp-tests\native-b.db' -WorkingDirectory 'D:\MyAgent\paraselene-work' -WindowStyle Hidden
```

启动/重开退出0；stdout为 `.client-mvp-tests/native-b.log` 和 `native-b-reopen.log`；数据库/日志为本机测试材料，不提交合成作品库。原生scale1.5、物理客户区1920×1200（150%DPI）。

Computer Use经node_repl `@oai/sky` 操作精确唯一标题 `幻月 · B阶段合成验收`。初次工具报 `Computer Use app approval timed out`，轻量list_windows恢复成功；未把它视为用户Stop或产品FAIL。之后先激活目标并刷新再操作。AX/截图常晚一拍，必要时只刷新确认结果、不重复提交。

## 初版B真实流程

1. 空库首次启动显示“新作品名称”“新建作品”“打开作品/还没有作品”，没有示例作品或design选择器。
2. 新建合成作品，先显示“作品还没有活动章节”；点击新建第一章，再新建第二章；正式目录显示2章/0资料、“本机作品 · SQLite”，正文均空。
3. 在第2章CodeMirror输入17字中文/emoji合成标记，下一动作切第1章；第1章仍空。输入不同17字合成标记后下一动作返回第2章，截图及AX精确Value断言确认第2章正文匹配，不混第1章。
4. Alt+F4正常关闭，刷新list_windows确认唯一B标题窗口为[]；同一DB重新启动，入口显示合成作品“最近打开”。打开后恢复上次第2章，AX精确正文Value断言PASS；回第1章AX精确Value断言PASS，均包括中文emoji。正文没有日志全文记录，仅此合成断言材料。
5. “输入后下一动作切章”不等于证明700ms以内flush边界：Computer Use截图/roundtrip有耗时，输入后的首次截图一度显示未保存，切章截图显示已恢复；未有精确输入→切换计时。因此即时切章保存竞态原生验证仍PARTIAL。
6. 创建人物资料→编辑名称/body（set_value合成Unicode）→保存并确认；截图/AX显示“已确认设定”与合成正文。正文出处为空且绑定按钮禁用，没有猜测出处。
7. 返回正文→打开第1章全章讨论→输入合成未发送草稿（set_value）；截图显示正文仍原值，草稿在明确textarea。未点“记录要求”，未发模型请求。随后正常Alt+F4关闭，刷新窗口=[]。

此时父Agent要重编最终修正，按要求释放唯一B窗口、不编译共用target。合成资料/草稿持久性尚需在最终build同DB重开断言；初版保存反馈不单独算重启恢复PASS。

## 原生尚未验证

- 最终构建重开、资料/线程草稿恢复：待下一段补充。
- 保存冲突、保存失败切章/关闭取消/重试与导出、线程保存故障：NOT_RUN。
- 异常退出后恢复、未提交字符实际边界：NOT_RUN。
- 章节归档恢复/排序/查找、确认版本/回退、出处版本失效、高亮定位：NOT_RUN。
- 正文IME完整中文候选/标点、选择/拖选/undo、资料返回焦点与叠层：NOT_RUN。
- 100/125%DPI、最小/最大化、安装离线/升级：NOT_RUN。
- C真实DeepSeek与D安装：NOT_RUN，不因B保存流程通过宣称CLIENT_MVP_PASS。
