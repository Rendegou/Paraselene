import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {evaluateBudget,renderReport} from './summarize.mjs';

const recorded=JSON.parse(await readFile(new URL('../../docs/evidence/m3/baseline-results.json',import.meta.url),'utf8'));
test('complete numeric matrix passes without accepting M3',()=>{
  assert.equal(evaluateBudget(recorded).overall,'PASS');
  assert.match(renderReport(recorded),/M3 原端对照闸门未关闭/);
});
for(const [name,mutate,field] of [
  ['slow input',r=>{r.cases[0].inputToDoubleRafMs.raw.fill(51);},'input'],
  ['slow load',r=>{r.cases.find(c=>c.name==='200k').loadMs.raw[0]=1001;},'load'],
  ['sustained scroll',r=>{r.cases[0].scrollFrameMs.raw.splice(0,3,34,34,34);},'scroll'],
  ['reported failed budget',r=>{r.cases[0].budget.inputP95AtMost50ms=false;},'input'],
])test(name+' cannot retain PASS from stale summary fields',()=>{
  const altered=structuredClone(recorded);mutate(altered);
  assert.equal(evaluateBudget(altered)[field],'FAIL');
  assert.equal(evaluateBudget(altered).overall,'FAIL');
  assert.match(renderReport(altered),/总状态 \*\*FAIL\*\*/);
});
for(const [name,mutate] of [
  ['missing case',r=>r.cases.pop()],
  ['insufficient input',r=>{r.cases[0].inputToDoubleRafMs.raw.pop();}],
  ['missing budget',r=>{delete r.cases[0].budget;}],
  ['invalid sample',r=>{r.cases[0].inputToDoubleRafMs.raw[0]=null;}],
])test(name+' fails closed as NOT_RUN',()=>{
  const altered=structuredClone(recorded);mutate(altered);
  assert.equal(evaluateBudget(altered).overall,'NOT_RUN');
});
test('CRLF status and error derive from current input',()=>{
  const altered=structuredClone(recorded);
  altered.behavior.crlfRawOffsets={status:'FAIL',error:'SYNTHETIC_CHANGED_ERROR'};
  assert.match(renderReport(altered),/SYNTHETIC_CHANGED_ERROR/);
  assert.doesNotMatch(renderReport(altered),/Position 193974/);
  delete altered.behavior.crlfRawOffsets;
  assert.match(renderReport(altered),/CRLF原始偏移检查：\*\*NOT_RUN\*\*/);
  assert.equal(evaluateBudget({}).overall,'NOT_RUN');
});
