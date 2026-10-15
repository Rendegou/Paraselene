import {chromium} from 'file:///C:/Users/HP/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {cpus,totalmem,release,hostname} from 'node:os';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('.',import.meta.url));
const evidence=fileURLToPath(new URL('../../docs/evidence/m3/',import.meta.url));
const hash=s=>createHash('sha256').update(s,'utf8').digest('hex');
const fill=(unit,n)=>unit.repeat(Math.ceil(n/unit.length)).slice(0,n);
const normal=n=>fill('月光落在窗边，远处传来缓慢的钟声。故事中的人物转身望向河岸。\n',n);
const cases=[['10k',normal(10000),0,false],['200k',normal(200000),0,false],['single-long-line',fill('月光落在窗边，远处传来钟声。',200000),0,false],['100-threads',normal(200000),100,false],['same-line-two',normal(10000),2,true],['repeated-quote',fill('相同引文。相同引文。相同引文。\n',200000),100,false],['unicode-lf',fill('中文 👩‍👩‍👧‍👦 e\u0301 العربية עברית\n',200000),100,false],['unicode-crlf',fill('中文 👩‍👩‍👧‍👦 e\u0301 العربية עברית\r\n',200000),0,false],['empty','',0,false]];
const profile=root+'browser-profile';await mkdir(profile,{recursive:true});
const context=await chromium.launchPersistentContext(profile,{channel:'chrome',headless:true,viewport:{width:1280,height:900},deviceScaleFactor:1,args:['--allow-file-access-from-files','--disable-background-timer-throttling','--disable-renderer-backgrounding'],serviceWorkers:'block'});
const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(String(e)));
await page.goto(new URL('./dist/index.html',import.meta.url).href);await page.waitForFunction(()=>!!window.baseline);
const fontStatus=await page.evaluate(async()=>{await document.fonts.load('20px "Notebook Serif"','月光落在窗边');await document.fonts.ready;return {status:document.fonts.status,loaded:document.fonts.check('20px "Notebook Serif"','月光落在窗边'),faces:[...document.fonts].map(f=>({family:f.family,status:f.status,weight:f.weight})),waitBeforeTiming:true};});
if(!fontStatus.loaded || !fontStatus.faces.some(f=>f.family==='Notebook Serif'&&f.status==='loaded'))throw new Error('Pinned Notebook Serif font not loaded');
const stats=a=>{const b=[...a].sort((x,y)=>x-y);return{n:b.length,p50:b[Math.floor((b.length-1)*.5)],p95:b[Math.ceil((b.length-1)*.95)],max:b.at(-1),raw:a};};
const result={scope:'ISOLATED_SOURCE_ENGINE_BROWSER_BASELINE',originalProductionClient:'NOT_RUN',webView2Host:'NOT_RUN',build:'Vite production minified',fontStatus,clock:'beforeinput capture → input event → double requestAnimationFrame (presentation proxy, not compositor timestamp)',machine:{hostname:hostname(),os:release(),cpu:cpus()[0].model,logicalCpu:cpus().length,totalMemoryBytes:totalmem()},cases:[],errors};
try{
  const browserSession=await context.newCDPSession(page);result.browserVersion=await browserSession.send('Browser.getVersion');
  const sources=['src/features/studio/writing/editorSetup.ts','src/features/studio/writing/editorSlots.ts','src/features/studio/writing/editorMarkers.ts','src/features/studio/editor/referenceExtension.ts','src/features/studio/writing/ParagraphEditor.tsx','src/features/studio/writing/useEditorEffects.ts','DESIGN.md'];
  result.sourceHashes={};for(const name of sources)result.sourceHashes[name]=hash(await readFile('D:/MyAgent/paraselene-work/'+name,'utf8'));
  result.fontSha256=createHash('sha256').update(await readFile('D:/MyAgent/paraselene-work/src/assets/fonts/NotoSerifSC-Regular.woff2')).digest('hex');
  result.versions={};for(const name of ['@codemirror/view','@codemirror/state','@codemirror/commands','vite'])result.versions[name]=JSON.parse(await readFile('D:/MyAgent/paraselene-work/node_modules/'+name+'/package.json','utf8')).version;
  for(const [name,body,count,sameLine] of cases){
    console.log('Running '+name);const loads=[];
    for(let i=0;i<10;i++) loads.push(await page.evaluate(async a=>window.baseline.load(...a),[body,count,sameLine]));
    const initial=await page.evaluate(()=>window.baseline.text());
    await page.evaluate(()=>window.baseline.focus());
    for(let i=0;i<60;i++){await page.keyboard.insertText('测');await page.waitForFunction(n=>window.baseline.inputs().length>=n,i+1);}
    const input=await page.evaluate(()=>window.baseline.inputs());
    const scrolling=await page.evaluate(()=>window.baseline.scroll());
    await page.evaluate(()=>window.baseline.top());
    const toggles=[];if(count)for(let i=0;i<20;i++)toggles.push(await page.evaluate(id=>window.baseline.toggle(id),i%2?'thread-0':null));
    const switches=[];for(let i=0;i<10;i++)switches.push(await page.evaluate(body=>window.baseline.switchChapter(body),i%2?body:normal(10000)));
    const item={name,inputUtf16:body.length,inputScalars:[...body].length,inputUtf8Sha256:hash(body),threads:count,sameLine,inputRoundTripExact:initial===body,roundTripUtf8Sha256:hash(initial),loadMs:stats(loads),inputToDoubleRafMs:stats(input),scrollFrameMs:stats(scrolling),scrollConsecutiveOver33ms:0,threadToggleMs:stats(toggles),chapterSwitchMs:stats(switches),details:await page.evaluate(()=>window.baseline.details())};
    if(!item.details.font.family.startsWith('"Notebook Serif"') || item.details.font.size!=='20px' || item.details.font.lineHeight!=='37px')throw new Error('Pinned body typography mismatch: '+JSON.stringify(item.details.font));
    let streak=0;for(const x of scrolling){streak=x>33?streak+1:0;item.scrollConsecutiveOver33ms=Math.max(streak,item.scrollConsecutiveOver33ms);}
    item.budget={inputP95AtMost50ms:item.inputToDoubleRafMs.p95<=50,load200kAtMost1000ms:body.length===200000?item.loadMs.max<=1000:null,scrollSustainedOver33ms:item.scrollConsecutiveOver33ms>=3};result.cases.push(item);
    await writeFile(evidence+'baseline-results.json',JSON.stringify(result,null,2));
  }
  result.millionWordWork={chapters:5,chapterUtf16:200000,totalUtf16:1000000,hashes:Array.from({length:5},()=>hash(normal(200000))),status:'SYNTHETIC_PARTITION_HASHED_NOT_LOADED_AS_SINGLE_CHAPTER'};
  result.behavior={};await page.evaluate(body=>window.baseline.load(body,2,true),normal(10000));
  result.behavior.sameLineTwo=await page.locator('.paragraph-marker-choices button').count();
  result.behavior.fullDeleteUndo=await page.evaluate(()=>window.baseline.deleteUndo());
  await page.evaluate(()=>window.baseline.load('重复引文。重复引文。\n',2,true));
  result.behavior.repeatedQuoteExact=(await page.evaluate(()=>window.baseline.text()))==='重复引文。重复引文。\n';
  try{await page.evaluate(body=>window.baseline.load(body,100),fill('中文 👩‍👩‍👧‍👦 e\u0301 العربية עברית\r\n',200000));await page.evaluate(()=>window.baseline.focus());await page.keyboard.insertText('测');result.behavior.crlfRawOffsets='UNEXPECTED_NO_ERROR';}catch(error){result.behavior.crlfRawOffsets={status:'FAIL',error:String(error),scope:'raw CRLF body and raw UTF16 synthetic markers passed directly to original createParagraphView; parent production preprocessing NOT_RUN'};}
  try{const browser=await context.browser().newBrowserCDPSession();const processes=await browser.send('SystemInfo.getProcessInfo');const ids=processes.processInfo.map(p=>p.id);const command=`Get-Process -Id ${ids.join(',')} -ErrorAction Stop | Select-Object Id,ProcessName,WorkingSet64,PrivateMemorySize64 | ConvertTo-Json -Compress`;result.processMemory={status:'MEASURED_END_OF_MATRIX',processes:JSON.parse(execFileSync('pwsh',['-NoProfile','-Command',command],{encoding:'utf8'})),scope:'CDP browser processes only; cumulative warm workload; not per-case delta'};}catch(e){result.processMemory={status:'NOT_AVAILABLE',reason:String(e),heapSource:'performance.memory JS heap only, not actual process memory'};}
}finally{await writeFile(evidence+'baseline-results.json',JSON.stringify(result,null,2));await context.close();}
