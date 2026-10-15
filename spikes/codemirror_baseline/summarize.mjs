import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

const expected=['10k','200k','single-long-line','100-threads','same-line-two','repeated-quote','unicode-lf','unicode-crlf','empty'];
const finite=n=>typeof n==='number'&&Number.isFinite(n)&&n>=0;
const combine=statuses=>statuses.includes('FAIL')?'FAIL':statuses.length&&statuses.every(s=>s==='PASS')?'PASS':'NOT_RUN';
function samples(metric,minimum) {
  const raw=metric?.raw;
  return Array.isArray(raw)&&raw.length>=minimum&&raw.every(finite)&&metric.n===raw.length?raw:null;
}
function inputStatus(c) {
  const raw=samples(c?.inputToDoubleRafMs,60);
  if(c?.budget?.inputP95AtMost50ms===false)return 'FAIL';
  if(!raw)return 'NOT_RUN';
  const sorted=[...raw].sort((a,b)=>a-b),p95=sorted[Math.ceil((sorted.length-1)*.95)];
  return p95>50?'FAIL':c?.budget?.inputP95AtMost50ms===true?'PASS':'NOT_RUN';
}
function loadStatus(c) {
  if(c?.budget?.load200kAtMost1000ms===false)return 'FAIL';
  const raw=samples(c?.loadMs,10);
  if(!raw||c?.inputUtf16!==200000)return 'NOT_RUN';
  return Math.max(...raw)>1000?'FAIL':c?.budget?.load200kAtMost1000ms===true?'PASS':'NOT_RUN';
}
function scrollStatus(c) {
  if(c?.budget?.scrollSustainedOver33ms===true)return 'FAIL';
  const raw=samples(c?.scrollFrameMs,120);
  if(!raw)return 'NOT_RUN';
  let streak=0;for(const n of raw){streak=n>33?streak+1:0;if(streak>=3)return 'FAIL';}
  return c?.budget?.scrollSustainedOver33ms===false?'PASS':'NOT_RUN';
}
export function evaluateBudget(r={}) {
  const cases=Array.isArray(r.cases)?r.cases:[];
  const find=name=>cases.find(c=>c.name===name);
  const input=combine(expected.map(name=>inputStatus(find(name))));
  const load=combine(['200k','single-long-line','100-threads','repeated-quote','unicode-lf','unicode-crlf'].map(name=>loadStatus(find(name))));
  const scroll=combine(expected.map(name=>scrollStatus(find(name))));
  return {input,load,scroll,overall:combine([input,load,scroll])};
}
const f=n=>finite(n)?n.toFixed(2):'NOT_RUN';
const value=n=>n===undefined||n===null?'NOT_RUN':String(n);
const exact=n=>n===true?'PASS':n===false?'FAIL':'NOT_RUN';
export function renderReport(r={}) {
  const cases=Array.isArray(r.cases)?r.cases:[],b=evaluateBudget(r),m=r.machine??{};
  const font=r.fontStatus?.loaded===true&&r.fontStatus?.waitBeforeTiming===true&&cases.length>0&&cases.every(c=>c.details?.font?.loaded===true&&c.details.font.family?.startsWith('"Notebook Serif"')&&c.details.font.size==='20px'&&c.details.font.lineHeight==='37px')?'PASS':'NOT_RUN';
  let out=`# M3 CodeMirror 源引擎隔离基线（2026-10-15）

状态：数值预算 **${b.overall}**（仅隔离浏览器源引擎探针）。原生产客户端 ${value(r.originalProductionClient)}；WebView2 ${value(r.webView2Host)}；真 Windows IME NOT_RUN。M3 原端对照闸门未关闭。

同机：${value(m.cpu)}，${value(m.logicalCpu)} logical CPUs，Windows ${value(m.os)}，RAM ${finite(m.totalMemoryBytes)?(m.totalMemoryBytes/2**30).toFixed(2):'NOT_RUN'} GiB。浏览器 ${value(r.browserVersion?.product)}；构建 ${value(r.build)}。运行配置为headless、1280×900 CSS px、DPR1、独立profile；实际负载/电源策略未固定。

字体验证：${font}。预期原 Notebook Serif WOFF2、20px/37px=1.85；load+fonts.ready在计时前完成。实际fontStatus=${JSON.stringify(r.fontStatus??null)}；字体SHA256=${value(r.fontSha256)}。本探针装载计时排除字体冷加载成本。

版本：${Object.entries(r.versions??{}).map(([k,v])=>k+' '+v).join('；')||'NOT_RUN'}。

数据仅合成，10k/200k中文样本按UTF-16 code units构造；Unicode fixture另记录scalar数量。输入/source/font SHA256和原始样本保存在JSON。100万字分章状态：${value(r.millionWordWork?.status)}，chapters=${value(r.millionWordWork?.chapters)}；未改变schema。

预期采样：装载10次、输入60次、滚动120帧、线程关闭/打开20次、切章10次；不足样本的预算不得PASS。P50/P95在升序样本上取零基floor((n−1)×0.5)/ceil((n−1)×0.95)。计时口径：${value(r.clock)}。insertText不能证明真实composition；每帧程序化滚动，连续≥3帧>33ms作为本探针持续超时判据。

|用例|输入P50 ms|输入P95 ms|装载P95 ms|滚动P95 ms|线程P95 ms|切章P95 ms|原文一致|
|---|---:|---:|---:|---:|---:|---:|---|
`;
  for(const c of cases)out+=`|${c.name}|${f(c.inputToDoubleRafMs?.p50)}|${f(c.inputToDoubleRafMs?.p95)}|${f(c.loadMs?.p95)}|${f(c.scrollFrameMs?.p95)}|${f(c.threadToggleMs?.p95)}|${f(c.chapterSwitchMs?.p95)}|${exact(c.inputRoundTripExact)}|\n`;
  out+=`\n数值预算：输入P95≤50ms **${b.input}**；20万UTF-16装载最大值≤1s **${b.load}**；普通滚动不持续>33ms **${b.scroll}**。总状态 **${b.overall}**。结论由必需矩阵、budget标志和有效完整raw样本共同导出；缺测NOT_RUN，失败FAIL，不宣称完整旧端/Flutter等价或M3通过。\n`;
  const mem=r.processMemory?.processes;
  if(r.processMemory?.status==='MEASURED_END_OF_MATRIX'&&Array.isArray(mem)&&mem.length&&mem.every(p=>finite(p.WorkingSet64)&&finite(p.PrivateMemorySize64)))out+=`\n实际进程内存：CDP列出${mem.length}个本次Chrome进程，Get-Process合计${(mem.reduce((a,p)=>a+p.WorkingSet64,0)/2**20).toFixed(2)} MiB working set、${(mem.reduce((a,p)=>a+p.PrivateMemorySize64,0)/2**20).toFixed(2)} MiB private bytes。累计热运行末态，非逐用例增量，共享working set相加可能重复。\n`;
  else out+=`\n实际进程内存：NOT_RUN / NOT_AVAILABLE，记录=${JSON.stringify(r.processMemory??null)}。\n`;
  const behavior=r.behavior??{},crlf=behavior.crlfRawOffsets;
  out+=`\n行为证据：同行两标记按钮数=${value(behavior.sameLineTwo)}；全文删除为空=${exact(behavior.fullDeleteUndo?.empty)}；undo恢复=${exact(behavior.fullDeleteUndo?.restored)}；重复引文原样=${exact(behavior.repeatedQuoteExact)}。\n`;
  const crlfState=crlf?.status==='FAIL'?'FAIL':crlf?.status==='PASS'?'PASS':'NOT_RUN';
  out+=`\nCRLF原始偏移检查：**${crlfState}**；原始记录=${JSON.stringify(crlf??null)}。CRLF无标记round-trip：${exact(cases.find(c=>c.name==='unicode-crlf')?.inputRoundTripExact)}。错误细节仅来自输入记录；该检查针对原始CRLF正文/偏移直接传入createParagraphView的隔离边界，生产上游预处理NOT_RUN，不推断完整原应用必然失败。\n`;
  out+=`\n隔离/差异：复用原createParagraphView/editorSlots/editorMarkers/referenceExtension/history。回调和线程内容为合成替身，不包括React Portal、业务锚点映射、保存/IPC。680px内滚动容器与原外层滚动不同。早期未固定字体结果保留于baseline-unpinned-results.json；中间monospace/28px预检保留于baseline-font-preflight-results.json，均由当前结果取代。原webview2-probe依赖Tauri bridge，非独立宿主；测试使用隔离file://页面。\n\n剩余闸门：完整旧生产客户端同机profile/release、WebView2、真实IME、DPI100/125/150/200和跨屏、实际键鼠/剪贴板/撤销、视觉/焦点、失效重开、外部rollback/业务锚点、React线程Portal、逐用例稳定内存。本探针不覆盖这些出口。\n\n复现：pwsh下执行node .\\build.mjs；node .\\run.mjs；node .\\summarize.mjs。报告器不推断命令退出码；运行命令状态另见执行记录。\n`;
  return out;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const path=new URL('../../docs/evidence/m3/',import.meta.url);
  const r=JSON.parse(await readFile(new URL('baseline-results.json',path),'utf8'));
  await writeFile(new URL('baseline.md',path),renderReport(r));
}
