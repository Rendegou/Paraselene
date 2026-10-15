import { Compartment } from '../../../paraselene-work/node_modules/@codemirror/state/dist/index.js';
import { createParagraphView } from '../../../paraselene-work/src/features/studio/writing/editorSetup';
import { slotExtension, markerExtension } from '../../../paraselene-work/src/features/studio/writing/editorSlots';
import { undo } from '../../../paraselene-work/node_modules/@codemirror/commands/dist/index.js';
import '../../../paraselene-work/src/features/studio/writing/NotebookFonts.css';

const paint = () => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
let view: any, props: any, compartments: any;
const callbacks = { mount(node: HTMLElement | null) { if (node) node.textContent = '合成讨论：保留正文布局空间，单活动线程。'; }, open(id: string) { return toggle(id); } };
function create(body: string, count = 0, sameLine = false) {
  view?.destroy();
  compartments = { references: new Compartment(), slot: new Compartment(), markers: new Compartment() };
  const lineStarts = [0];
  for (let i=0;i<body.length;i++) if(body[i]==='\n') lineStarts.push(i+1);
  const markers = Array.from({length:count}, (_,i)=> {
    const from = sameLine ? i : lineStarts[Math.floor(i * (lineStarts.length-1)/Math.max(1,count))];
    return {id:`thread-${i}`,from,to:Math.min(body.length,from+2),valid:true,number:i+1};
  });
  props={body, chapterId:'synthetic',entities:[],markers,activeId:null,slot:null,slotCallbacks:callbacks,
    onChange(body:string){props.body=body;},onMap(){},onSelection(){},onReference(){}};
  view=createParagraphView(document.querySelector('#editor')!,()=>props,compartments);
}
async function toggle(id: string | null) {
  const start=performance.now();
  const marker=props.markers.find((m:any)=>m.id===id);
  props.activeId=id;
  view.dispatch({effects:[compartments.slot.reconfigure(slotExtension(marker?{id,at:view.state.doc.lineAt(marker.to).to}:null,callbacks)),
    compartments.markers.reconfigure(markerExtension(props.markers,id,callbacks))]});
  await paint(); return performance.now()-start;
}
let inputStart=0, pending: (()=>void)|null=null, inputs:number[]=[];
document.addEventListener('beforeinput',()=> {inputStart=performance.now();},true);
document.addEventListener('input',async()=> {const start=inputStart; await paint(); inputs.push(performance.now()-start);pending?.();pending=null;},true);
(window as any).baseline={
  async load(body:string,count=0,sameLine=false) {const start=performance.now();create(body,count,sameLine);await paint();return performance.now()-start;},
  async switchChapter(body:string) {const start=performance.now();create(body);await paint();return performance.now()-start;},
  toggle,
  async focus() {view.dispatch({selection:{anchor:Math.floor(view.state.doc.length/2)}});view.focus();await paint();inputs=[];},
  inputs:()=>inputs,
  async top() {view.scrollDOM.scrollTop=0;await paint();},
  async deleteUndo() {const before=view.state.doc.toString();view.dispatch({changes:{from:0,to:view.state.doc.length,insert:''},userEvent:'delete'});const empty=view.state.doc.length===0;undo(view);await paint();return {empty,restored:view.state.doc.toString()===before};},
  text:()=>view.state.doc.toString(),
  async scroll() {const frames:number[]=[];let prev=performance.now();for(let i=0;i<120;i++){await new Promise(requestAnimationFrame);const now=performance.now();frames.push(now-prev);prev=now;view.scrollDOM.scrollTop=(view.scrollDOM.scrollHeight-view.scrollDOM.clientHeight)*(i/119);}await paint();return frames;},
  details:()=>({ua:navigator.userAgent,dpr:devicePixelRatio,viewport:[innerWidth,innerHeight],font:{family:getComputedStyle(view.contentDOM).fontFamily,size:getComputedStyle(view.contentDOM).fontSize,lineHeight:getComputedStyle(view.contentDOM).lineHeight,loaded:document.fonts.check('20px "Notebook Serif"','月光落在窗边')},heap:(performance as any).memory?.usedJSHeapSize??null,lines:view.state.doc.lines,utf16:view.state.doc.length})
};
