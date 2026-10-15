# M3 CodeMirror 源引擎隔离基线（2026-10-15）

状态：数值预算 **PASS**（仅隔离浏览器源引擎探针）。原生产客户端 NOT_RUN；WebView2 NOT_RUN；真 Windows IME NOT_RUN。M3 原端对照闸门未关闭。

同机：13th Gen Intel(R) Core(TM) i9-13900HX，32 logical CPUs，Windows 10.0.26200，RAM 15.70 GiB。浏览器 Chrome/155.0.8059.41；构建 Vite production minified。运行配置为headless、1280×900 CSS px、DPR1、独立profile；实际负载/电源策略未固定。

字体验证：PASS。预期原 Notebook Serif WOFF2、20px/37px=1.85；load+fonts.ready在计时前完成。实际fontStatus={"status":"loaded","loaded":true,"faces":[{"family":"Notebook Sans","status":"unloaded","weight":"400"},{"family":"Notebook Sans","status":"unloaded","weight":"500"},{"family":"Notebook Sans","status":"unloaded","weight":"600"},{"family":"Notebook Serif","status":"loaded","weight":"400"}],"waitBeforeTiming":true}；字体SHA256=39119be8a687db78da9c9f48d8df17cfc03ce9aae395225fd482484e265d1b8c。本探针装载计时排除字体冷加载成本。

版本：@codemirror/view 6.43.13；@codemirror/state 6.7.6；@codemirror/commands 6.11.1；vite 8.3.1。

数据仅合成，10k/200k中文样本按UTF-16 code units构造；Unicode fixture另记录scalar数量。输入/source/font SHA256和原始样本保存在JSON。100万字分章状态：SYNTHETIC_PARTITION_HASHED_NOT_LOADED_AS_SINGLE_CHAPTER，chapters=5；未改变schema。

预期采样：装载10次、输入60次、滚动120帧、线程关闭/打开20次、切章10次；不足样本的预算不得PASS。P50/P95在升序样本上取零基floor((n−1)×0.5)/ceil((n−1)×0.95)。计时口径：beforeinput capture → input event → double requestAnimationFrame (presentation proxy, not compositor timestamp)。insertText不能证明真实composition；每帧程序化滚动，连续≥3帧>33ms作为本探针持续超时判据。

|用例|输入P50 ms|输入P95 ms|装载P95 ms|滚动P95 ms|线程P95 ms|切章P95 ms|原文一致|
|---|---:|---:|---:|---:|---:|---:|---|
|10k|7.60|7.90|12.60|4.30|NOT_RUN|7.50|PASS|
|200k|7.70|8.00|4.30|4.40|NOT_RUN|8.60|PASS|
|single-long-line|7.70|7.90|41.90|6.70|NOT_RUN|36.40|PASS|
|100-threads|7.70|8.00|5.00|4.50|7.90|7.10|PASS|
|same-line-two|7.80|8.00|7.40|4.40|7.80|7.50|PASS|
|repeated-quote|7.60|8.00|4.50|4.50|7.90|7.20|PASS|
|unicode-lf|7.80|8.00|46.90|4.90|7.90|7.20|PASS|
|unicode-crlf|7.70|7.90|6.30|4.50|NOT_RUN|7.10|FAIL|
|empty|7.70|8.00|7.70|5.30|NOT_RUN|7.70|PASS|

数值预算：输入P95≤50ms **PASS**；20万UTF-16装载最大值≤1s **PASS**；普通滚动不持续>33ms **PASS**。总状态 **PASS**。结论由必需矩阵、budget标志和有效完整raw样本共同导出；缺测NOT_RUN，失败FAIL，不宣称完整旧端/Flutter等价或M3通过。

实际进程内存：CDP列出8个本次Chrome进程，Get-Process合计714.28 MiB working set、446.06 MiB private bytes。累计热运行末态，非逐用例增量，共享working set相加可能重复。

行为证据：同行两标记按钮数=2；全文删除为空=PASS；undo恢复=PASS；重复引文原样=PASS。

CRLF原始偏移检查：**FAIL**；原始记录={"status":"FAIL","error":"Error: page.evaluate: RangeError: Position 193974 is out of range for changeset of length 193940\n    at e.mapPos (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:3572)\n    at file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:10:94714\n    at Array.map (<anonymous>)\n    at e.update [as updateF] (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:10:94685)\n    at Object.update (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:15294)\n    at e.computeSlot (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:24126)\n    at Me (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:18351)\n    at new e (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:23322)\n    at e.applyTransaction (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:24096)\n    at get state (file:///D:/MyAgent/paraselene-flutter/spikes/codemirror_baseline/dist/assets/index-Cq52qNo0.js:4:19806)","scope":"raw CRLF body and raw UTF16 synthetic markers passed directly to original createParagraphView; parent production preprocessing NOT_RUN"}。CRLF无标记round-trip：FAIL。错误细节仅来自输入记录；该检查针对原始CRLF正文/偏移直接传入createParagraphView的隔离边界，生产上游预处理NOT_RUN，不推断完整原应用必然失败。

隔离/差异：复用原createParagraphView/editorSlots/editorMarkers/referenceExtension/history。回调和线程内容为合成替身，不包括React Portal、业务锚点映射、保存/IPC。680px内滚动容器与原外层滚动不同。早期未固定字体结果保留于baseline-unpinned-results.json；中间monospace/28px预检保留于baseline-font-preflight-results.json，均由当前结果取代。原webview2-probe依赖Tauri bridge，非独立宿主；测试使用隔离file://页面。

剩余闸门：完整旧生产客户端同机profile/release、WebView2、真实IME、DPI100/125/150/200和跨屏、实际键鼠/剪贴板/撤销、视觉/焦点、失效重开、外部rollback/业务锚点、React线程Portal、逐用例稳定内存。本探针不覆盖这些出口。

复现：pwsh下执行node .\build.mjs；node .\run.mjs；node .\summarize.mjs。报告器不推断命令退出码；运行命令状态另见执行记录。
