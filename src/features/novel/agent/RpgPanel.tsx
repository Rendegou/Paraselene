// 跑团共写面板。行为契约不变量见 crates/novel-core/src/rpg.rs 的 rustdoc；
// 组件契约见下方 RpgPanel 的文档注释。

import { useState } from "react";
import {
  novelAiGenerate, novelRpgGenerateScene, novelRpgResponsePreview, novelRpgScenePreview,
  type IssuedPreview, type NovelDraft, type NovelRpgScene,
} from "../contracts";
import { PreviewCard } from "./PreviewCard";

/**
 * 跑团共写面板。状态机分两条线：场景线（direction → scenePreview → scene）
 * 与试写线（playerReply → responsePreview → draft），两条线各自"预览 → 确认"两段式。
 *
 * 契约：
 * - `selectedId` 必须指向已保存的章节文档；存在未保存手写修改（`unsavedText`）
 *   或详情加载中（`detailsLoading`）时所有发送按钮禁用，防止旧上下文被新请求污染。
 * - 预览一旦发出，修改输入会清空对应预览（见 onChange 里的 setXxx(null)），
 *   因为预览内容是按当时输入签发的，输入变化后旧预览即失效。
 * - 生成的 `NovelDraft` 只是待确认试写，由 `onGenerated` 上抛给状态层登记，
 *   本组件不直接写正稿。
 */
export function RpgPanel(props: {
  selectedId: string;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  detailsLoading: boolean;
  unsavedText: boolean;
  onGenerated: (draft: NovelDraft) => void;
  setNotice: (msg: string) => void;
}) {
  const [rpgDirection, setRpgDirection] = useState("");
  const [rpgScenePreview, setRpgScenePreview] = useState<IssuedPreview | null>(null);
  const [rpgScene, setRpgScene] = useState<NovelRpgScene | null>(null);
  const [playerReply, setPlayerReply] = useState("");
  const [rpgResponsePreview, setRpgResponsePreview] = useState<IssuedPreview | null>(null);

  async function previewRpgScene() {
    if (!props.selectedId || !rpgDirection.trim() || props.unsavedText || props.detailsLoading) return;
    // 发送前清掉旧场景/旧预览，避免用户看到与新方向无关的旧结果
    props.setBusy(true); props.setNotice(""); setRpgScene(null); setRpgScenePreview(null); setRpgResponsePreview(null);
    try { setRpgScenePreview(await novelRpgScenePreview(props.selectedId, rpgDirection)); }
    catch (error) { props.setNotice(`跑团场景预览失败：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  async function generateRpgScene() {
    if (!rpgScenePreview || props.unsavedText) return;
    props.setBusy(true); props.setNotice("");
    const id = rpgScenePreview.id; setRpgScenePreview(null);
    try {
      // 场景是一次性临时内容：只用于本轮选择，不进正稿也不进下一章上下文
      setRpgScene(await novelRpgGenerateScene(id));
      props.setNotice("场景仅供这轮选择，尚未保存为章节正稿。现在用一句话回答主角怎么想或怎么做。");
    } catch (error) { props.setNotice(`跑团场景生成失败：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  async function previewRpgResponse() {
    if (!rpgScene || !playerReply.trim() || props.unsavedText || props.detailsLoading) return;
    props.setBusy(true); props.setNotice(""); setRpgResponsePreview(null);
    try { setRpgResponsePreview(await novelRpgResponsePreview(rpgScene.id, playerReply)); }
    catch (error) { props.setNotice(`玩家回复预览失败：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  async function generateRpgResponse() {
    if (!rpgResponsePreview || props.unsavedText) return;
    props.setBusy(true); props.setNotice("");
    const id = rpgResponsePreview.id; setRpgResponsePreview(null);
    try {
      const created = await novelAiGenerate(id);
      props.onGenerated(created);
      props.setNotice("这轮互动已写成待确认试写；正稿未改变。请对照后决定是否采纳。");
    } catch (error) { props.setNotice(`跑团试写生成失败：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  return <section className="novel-rpg" aria-label="跑团共写">
    <h4>跑团共写</h4><p>幻月先扮演世界与编剧给出场景和走向；你的短回复就是主角的内心或行动。最终文字仍需你采纳才进正稿。</p>
    <label htmlFor="novel-rpg-direction">本轮场景方向</label>
    <textarea id="novel-rpg-direction" value={rpgDirection} maxLength={500} disabled={props.busy}
      placeholder="例如：主角在雨夜来到陌生城门" onChange={(event) => { setRpgDirection(event.target.value); setRpgScenePreview(null); setRpgScene(null); setRpgResponsePreview(null); }} />
    <button className="secondary" type="button" disabled={props.busy || props.detailsLoading || props.unsavedText || !rpgDirection.trim()}
      onClick={() => void previewRpgScene()}>预览场景请求</button>
    {rpgScenePreview && <PreviewCard title="场景外发预览" preview={rpgScenePreview}
      confirmLabel="确认发送并生成临时场景" busy={props.busy} onConfirm={() => void generateRpgScene()} />}
    {rpgScene && <div className="novel-rpg-scene"><h5>临时场景 · 尚未进入正稿</h5><p>{rpgScene.scene}</p>
      <div className="novel-rpg-options">{rpgScene.options.map((option, index) => <button type="button" key={`${index}-${option}`} disabled={props.busy}
        onClick={() => { setPlayerReply(option); setRpgResponsePreview(null); }}>{index + 1}. {option}</button>)}</div>
      <label htmlFor="novel-rpg-reply">主角的内心或行动</label>
      <textarea id="novel-rpg-reply" value={playerReply} maxLength={300} disabled={props.busy} placeholder="选择上方走向，或用自己的话回答"
        onChange={(event) => { setPlayerReply(event.target.value); setRpgResponsePreview(null); }} />
      <button className="secondary" type="button" disabled={props.busy || props.detailsLoading || props.unsavedText || !playerReply.trim()}
        onClick={() => void previewRpgResponse()}>预览这轮试写请求</button>
      {rpgResponsePreview && <PreviewCard title="玩家回复外发预览" preview={rpgResponsePreview}
        confirmLabel="确认发送并保存待确认试写" busy={props.busy} onConfirm={() => void generateRpgResponse()} />}
    </div>}
  </section>;
}
