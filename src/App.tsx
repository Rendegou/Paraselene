import { useEffect, useRef, useState } from "react";
import {
  currentSurface, defaultCharacter, deleteApiKey, exportCharacterPack, getCharacter,
  getCloudEnabled, getRuntimeActivity, hasApiKey, hideCard, importCharacterPack, onCharacterChanged,
  llmChatPreview, llmChatSend, llmFetchModels, setApiKey, setCloudEnabled,
  setCharacter, startWindowDrag, toggleCard, type CharacterConfig, type IssuedPreview, type RuntimeActivity, type Space,
} from "./lib/ipc";
import "./App.css";
import IdeaPage from "./IdeaPage";
import ImportSection from "./ImportSection";
import moonIdle from "./assets/companions/moon-idle.png";
import moonCurious from "./assets/companions/moon-curious.png";
import moonPoke from "./assets/companions/moon-poke.png";
import moonSleep from "./assets/companions/moon-sleep.png";
import starIdle from "./assets/companions/star-idle.png";
import starCurious from "./assets/companions/star-curious.png";
import starPoke from "./assets/companions/star-poke.png";
import starSleep from "./assets/companions/star-sleep.png";
import cloudIdle from "./assets/companions/cloud-idle.png";
import cloudCurious from "./assets/companions/cloud-curious.png";
import cloudPoke from "./assets/companions/cloud-poke.png";
import cloudSleep from "./assets/companions/cloud-sleep.png";

const spaces: { id: Space; name: string }[] = [
  { id: "personal", name: "个人" },
  { id: "idea", name: "旧想法" },
  { id: "novel", name: "小说" },
  { id: "learning", name: "学习" },
];

const appearanceNames: Record<CharacterConfig["appearance"], string> = {
  moon: "月亮", star: "星星", cloud: "云朵",
};

type PetPose = "idle" | "curious" | "poke" | "sleep";

const companionImages: Record<CharacterConfig["appearance"], Record<PetPose, string>> = {
  moon: { idle: moonIdle, curious: moonCurious, poke: moonPoke, sleep: moonSleep },
  star: { idle: starIdle, curious: starCurious, poke: starPoke, sleep: starSleep },
  cloud: { idle: cloudIdle, curious: cloudCurious, poke: cloudPoke, sleep: cloudSleep },
};

function CompanionArt({ appearance, pose = "idle" }: { appearance: CharacterConfig["appearance"]; pose?: PetPose }) {
  return <img className="companion-art" src={companionImages[appearance][pose]} alt="" draggable={false} aria-hidden="true" />;
}

function MoonMark({ className }: { className: string }) {
  return <svg className={className} viewBox="0 0 32 32" aria-hidden="true">
    <path d="M21.8 2.8A13.5 13.5 0 1 0 29 22.2 11 11 0 0 1 21.8 2.8Z" />
  </svg>;
}

function Pet() {
  const [error, setError] = useState("");
  const [character, setCharacterState] = useState<CharacterConfig>(defaultCharacter);
  const [pose, setPose] = useState<PetPose>("idle");
  const sleepTimer = useRef<number | null>(null);
  const curiosityTimer = useRef<number | null>(null);
  const reactionTimer = useRef<number | null>(null);
  const openingCard = useRef(false);
  const pointerNearby = useRef(false);

  function cancelSleep() {
    if (sleepTimer.current !== null) window.clearTimeout(sleepTimer.current);
    sleepTimer.current = null;
  }

  function scheduleSleep() {
    cancelSleep();
    if (pointerNearby.current || openingCard.current) return;
    sleepTimer.current = window.setTimeout(() => {
      if (!pointerNearby.current && !openingCard.current) setPose("sleep");
      sleepTimer.current = null;
    }, 90_000);
  }

  function cancelCuriosity() {
    if (curiosityTimer.current !== null) window.clearTimeout(curiosityTimer.current);
    curiosityTimer.current = null;
  }

  function noticePerson() {
    cancelSleep();
    cancelCuriosity();
    if (openingCard.current) return;
    setPose("curious");
    curiosityTimer.current = window.setTimeout(() => {
      curiosityTimer.current = null;
      if (!openingCard.current) setPose("idle");
      scheduleSleep();
    }, 1_100);
  }

  function leavePet() {
    pointerNearby.current = false;
    cancelCuriosity();
    if (!openingCard.current) setPose("idle");
    scheduleSleep();
  }

  function openCard() {
    if (openingCard.current) return;
    openingCard.current = true;
    cancelSleep();
    cancelCuriosity();
    setPose("poke");
    // 留一小段可见反应，再打开卡片；连续点击只消费一次，避免把卡片立刻关回去。
    const delay = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 280;
    reactionTimer.current = window.setTimeout(() => {
      reactionTimer.current = null;
      void toggleCard().catch(() => setError("卡片暂时打不开")).finally(() => {
        openingCard.current = false;
        setPose("idle");
        scheduleSleep();
      });
    }, delay);
  }

  useEffect(() => {
    scheduleSleep();
    return () => {
      cancelSleep();
      cancelCuriosity();
      if (reactionTimer.current !== null) window.clearTimeout(reactionTimer.current);
    };
  }, []);

  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    getCharacter().then((value) => { if (active) setCharacterState(value); }).catch(() => setError("形象读取失败"));
    onCharacterChanged((value) => { if (active) setCharacterState(value); })
      .then((stop) => { if (active) unsubscribe = stop; else stop(); })
      .catch(() => setError("形象同步失败"));
    return () => { active = false; unsubscribe?.(); };
  }, []);

  useEffect(() => {
    for (const nextPose of ["curious", "poke", "sleep"] as const) {
      const image = new Image();
      image.src = companionImages[character.appearance][nextPose];
    }
  }, [character.appearance]);

  return <main className={`pet pet-${character.appearance} pet-pose-${pose}`}
    onPointerEnter={() => { pointerNearby.current = true; noticePerson(); }} onPointerLeave={leavePet}>
    <div className="pet-grip" title={`拖动${character.name}`} aria-hidden="true"
      onMouseDown={(event) => { if (event.button === 0) void startWindowDrag().catch(() => setError("暂时无法拖动")); }} />
    <button className="pet-body" type="button" aria-label={`打开${character.name}卡片`}
      onFocus={noticePerson} onClick={openCard}>
      <CompanionArt appearance={character.appearance} pose={pose} />
    </button>
    {error && <span className="pet-error" role="status">{error}</span>}
  </main>;
}

function Card() {
  const [tab, setTab] = useState<"chat" | "ideas" | "character" | "settings">("chat");
  const [space, setSpace] = useState<Space>("personal");
  const [prompt, setPrompt] = useState("");
  const [preview, setPreview] = useState<IssuedPreview | null>(null);
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [keyInput, setKeyInput] = useState("");
  const [hasKey, setHasKey] = useState<boolean | null>(null);
  const [cloud, setCloud] = useState<Record<Space, boolean> | null>(null);
  const [settingsError, setSettingsError] = useState(false);
  const [models, setModels] = useState<string[]>([]);
  const [model, setModel] = useState("");
  const [character, setCharacterState] = useState<CharacterConfig>(defaultCharacter);
  const [draftCharacter, setDraftCharacter] = useState<CharacterConfig>(defaultCharacter);
  const [packInput, setPackInput] = useState("");
  const [packOutput, setPackOutput] = useState("");
  const [activity, setActivity] = useState<RuntimeActivity | null>(null);
  const previewRevision = useRef(0);
  const activeSpace = spaces.find((item) => item.id === space)?.name ?? "个人";

  useEffect(() => {
    void reloadSettings();
  }, []);

  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    getCharacter().then((value) => { if (active) { setCharacterState(value); setDraftCharacter(value); } })
      .catch(() => setNotice("角色设置读取失败。"));
    onCharacterChanged((value) => {
      if (active) { setCharacterState(value); setDraftCharacter(value); invalidatePreview(); }
    }).then((stop) => { if (active) unsubscribe = stop; else stop(); })
      .catch(() => setNotice("角色设置同步失败。"));
    return () => { active = false; unsubscribe?.(); };
  }, []);

  function invalidatePreview() { previewRevision.current += 1; setPreview(null); }

  function invalidate() { invalidatePreview(); setNotice(""); }

  async function reloadSettings() {
    setCloud(null); setHasKey(null); setSettingsError(false);
    try {
      const [key, ...flags] = await Promise.all([hasApiKey(), ...spaces.map((item) => getCloudEnabled(item.id))]);
      setHasKey(key);
      setCloud(Object.fromEntries(spaces.map((item, index) => [item.id, flags[index]])) as Record<Space, boolean>);
    } catch {
      setSettingsError(true);
      setNotice("设置读取失败；请重试后再发送模型请求。");
    }
  }

  async function prepare() {
    if (!prompt.trim()) { setNotice("先写下要问的内容。"); return; }
    if (!cloud?.[space]) { setNotice("请先确认该空间的云调用开关。"); return; }
    const revision = previewRevision.current;
    setBusy(true); setNotice("");
    try {
      const result = await llmChatPreview({
        space, messages: [{ role: "user", content: prompt.trim() }],
        ...(model ? { model } : {}),
      });
      if (previewRevision.current === revision) { setPreview(result); setReply(""); }
    } catch (error) { setNotice(`无法生成预览：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function send() {
    if (!preview || hasKey !== true || cloud?.[preview.prepared.space] !== true) return;
    setBusy(true); setNotice(""); setReply("");
    try {
      await llmChatSend(preview.id, (event) => {
        if (event.type === "delta") setReply((text) => text + event.content);
        if (event.type === "error") setNotice(`模型请求失败：${event.message}`);
      });
    } catch (error) { setNotice(`模型请求失败：${String(error)}`); }
    finally { setBusy(false); setPreview(null); }
  }

  async function saveKey() {
    if (!keyInput.trim()) return;
    setBusy(true);
    try {
      await setApiKey(keyInput.trim());
      setKeyInput(""); setHasKey(true); setNotice("Key 已保存到 Windows 凭据管理器。");
    } catch (error) { setNotice(`保存失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function removeKey() {
    setBusy(true);
    try {
      await deleteApiKey();
      setHasKey(false); setNotice("Key 已移除。");
    } catch (error) { setNotice(`移除失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function toggleCloud(id: Space, enabled: boolean) {
    setBusy(true);
    try {
      await setCloudEnabled(id, enabled);
      setCloud((current) => current ? { ...current, [id]: enabled } : current);
      invalidate();
    } catch (error) { setNotice(`设置失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function fetchModels() {
    setBusy(true);
    try {
      const names = await llmFetchModels();
      setModels(names); setNotice(`已获取 ${names.length} 个可用模型。`);
    } catch (error) { setNotice(`获取模型失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function saveCharacter() {
    setBusy(true); setNotice("");
    try {
      const saved = await setCharacter(draftCharacter);
      setCharacterState(saved); setDraftCharacter(saved); invalidatePreview(); setPackOutput("");
      setNotice("角色设置已保存。下一次预览会使用新的说话方式。");
    } catch (error) { setNotice(`角色保存失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function exportPack() {
    setBusy(true); setNotice("");
    try {
      setPackOutput(await exportCharacterPack());
      setNotice("分享内容已生成，只含形象和说话方式，不含本地名称。可复制下方 JSON。");
    } catch (error) { setNotice(`生成失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function importPack() {
    setBusy(true); setNotice("");
    try {
      const saved = await importCharacterPack(packInput);
      setCharacterState(saved); setDraftCharacter(saved); setPackInput(""); setPackOutput(""); invalidatePreview();
      setNotice("角色包已导入；本地名称保持不变。");
    } catch (error) { setNotice(`导入被拒绝：${String(error)}`); }
    finally { setBusy(false); }
  }

  async function refreshActivity() {
    try { setActivity(await getRuntimeActivity()); }
    catch (error) { setNotice(`读取运行计数失败：${String(error)}`); }
  }

  return <main className="card">
    <header className="card-header" onMouseDown={(event) => {
      if (event.button !== 0 || (event.target as Element).closest("button")) return;
      void startWindowDrag().catch(() => setNotice("卡片暂时无法拖动"));
    }}>
      <div className="brand"><MoonMark className="brand-mark" /><h1>{character.name}</h1></div>
      <button className="close" type="button" aria-label="关闭卡片" onClick={() => hideCard()}><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 4l12 12M16 4L4 16" /></svg></button>
    </header>
    <nav className="tabs" aria-label="卡片功能">
      {([ ["chat", "对话"], ["ideas", "旧想法"], ["character", "形象"], ["settings", "设置"] ] as const).map(([id, label]) =>
        <button key={id} type="button" className={tab === id ? "active" : ""} aria-current={tab === id ? "page" : undefined}
          onClick={() => { setTab(id); setNotice(""); }}>{label}</button>)}
    </nav>
    {tab === "chat" ? <section className="chat-page">
      <div className="conversation" aria-live="polite">
        {preview ? <div className="review-sheet">
          <h2>这段话将离开本机</h2>
          <p className="review-meta">{spaces.find((item) => item.id === preview.prepared.space)?.name}空间 · {preview.prepared.model}</p>
          <div className="preview-text">{preview.prepared.messages.map((message) => `${message.role === "system" ? "说话方式" : "你的输入"}：${message.content ?? ""}`).join("\n\n")}</div>
          {hasKey !== true && <p className="inline-alert">请先在设置中保存 DeepSeek Key。</p>}
          <div className="review-actions"><button className="secondary" type="button" disabled={busy} onClick={invalidatePreview}>返回修改</button><button className="primary" type="button" disabled={busy || hasKey !== true || cloud?.[preview.prepared.space] !== true} onClick={send}>确认发送</button></div>
        </div> : reply ? <div className="reply-sheet"><h2>{character.name}的回复</h2><p>{reply}</p></div>
          : <div className="welcome"><CompanionArt appearance={character.appearance} /><h2>想从哪一句开始？</h2><p>写下现在想说的事，我在这里。</p></div>}
      </div>
      <div className="composer">
        <div className="composer-top"><label htmlFor="space">写入空间</label><select id="space" value={space} disabled={busy} onChange={(e) => { setSpace(e.target.value as Space); invalidate(); }}>
          {spaces.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select><span className="space-caption">{activeSpace}的内容独立保存</span></div>
        <label className="sr-only" htmlFor="prompt">写给{character.name}</label>
        <textarea id="prompt" rows={3} value={prompt} disabled={busy} placeholder={`写给${character.name}…`}
          onChange={(e) => { setPrompt(e.target.value); invalidate(); }} />
        <div className="composer-bottom"><p>仅发送本次文字，旧对话检索仍在接入。</p><button className="primary" type="button" disabled={busy || !prompt.trim() || cloud?.[space] !== true} onClick={prepare}>{busy ? "请稍候…" : "查看外发内容"}</button></div>
        {cloud?.[space] === false && <p className="inline-alert">此空间已关闭云调用，可在设置中开启。</p>}
        {cloud === null && <p className="inline-alert">云调用状态未确认，请到设置页重试。</p>}
      </div>
      {notice && <p className="notice" role="status">{notice}</p>}
    </section> : <div className="content">
      {tab === "ideas" ? <IdeaPage onOpenImport={() => { setTab("settings"); setNotice(""); }} /> : tab === "character" ? <section className="page character-page">
        <div className="page-heading"><h2>形象与说话方式</h2></div>
        <div className="character-portrait"><CompanionArt appearance={draftCharacter.appearance} /><div><h3>{draftCharacter.name || "未命名"}</h3><p>{appearanceNames[draftCharacter.appearance]}形态</p></div></div>
        <div className="appearance-choices" role="group" aria-label="选择形象">{(["moon", "star", "cloud"] as const).map((appearance) =>
          <button key={appearance} type="button" className={draftCharacter.appearance === appearance ? "selected" : ""} aria-pressed={draftCharacter.appearance === appearance}
            disabled={busy} onClick={() => setDraftCharacter({ ...draftCharacter, appearance })}>{appearanceNames[appearance]}</button>)}</div>
        <label htmlFor="character-name">本地名称</label>
        <input id="character-name" type="text" maxLength={16} value={draftCharacter.name} disabled={busy}
          onChange={(e) => setDraftCharacter({ ...draftCharacter, name: e.target.value })} />
        <label htmlFor="voice">说话方式</label>
        <select id="voice" value={draftCharacter.voice} disabled={busy}
          onChange={(e) => setDraftCharacter({ ...draftCharacter, voice: e.target.value as CharacterConfig["voice"] })}>
          <option value="gentle">温和清楚</option><option value="playful">轻快友好</option><option value="concise">简短直接</option>
        </select>
        <p className="section-note">名称只留在本机；保存后，新对话会使用所选说话方式。</p>
        <button className="primary wide" type="button" disabled={busy || !draftCharacter.name.trim()} onClick={saveCharacter}>保存角色设置</button>
        <details className="fold"><summary>分享或导入角色包</summary>
          <p className="section-note">分享包只含固定形象和说话方式，不含脚本、密钥、对话或本地名称。</p>
          <button className="secondary" type="button" disabled={busy} onClick={exportPack}>生成分享内容</button>
          {packOutput && <textarea className="pack-json" aria-label="分享内容 JSON" readOnly rows={5} value={packOutput} onFocus={(e) => e.target.select()} />}
          <label htmlFor="pack-input">导入分享内容</label>
          <textarea id="pack-input" rows={4} value={packInput} disabled={busy} placeholder="粘贴角色包 JSON"
            onChange={(e) => setPackInput(e.target.value)} />
          <button className="secondary" type="button" disabled={busy || !packInput.trim()} onClick={importPack}>检查并导入</button>
        </details>
      </section> : <section className="page settings-page">
        <div className="page-heading"><h2>设置</h2><p>本机资料和云调用都由你决定。</p></div>
        <ImportSection onOpenIdeas={() => { setTab("ideas"); setNotice(""); }} />
        <div className="section-title"><h3>DeepSeek Key</h3><strong className={`key-state ${hasKey ? "ready" : ""}`}>{hasKey === null ? "尚未确认" : hasKey ? "已设置" : "未设置"}</strong></div>
        <p className="section-note">保存在 Windows 凭据管理器，界面不会回显。</p>
        <label htmlFor="key">{hasKey ? "替换 Key" : "输入 Key"}</label>
        <input id="key" type="password" autoComplete="off" placeholder="仅本次输入" value={keyInput}
          disabled={busy} onChange={(e) => setKeyInput(e.target.value)} />
        <div className="actions"><button className="primary" type="button" disabled={busy || !keyInput.trim()} onClick={saveKey}>保存 Key</button>
          {hasKey === true && <button className="text-action" type="button" disabled={busy} onClick={removeKey}>移除 Key</button>}</div>
        <div className="section-title section-break"><h3>云调用</h3></div>
        <p className="section-note">按空间分别控制；关闭后不能预览或发送。</p>
        <div className="switch-list">{cloud ? spaces.map((item) => <label className="switch-row" key={item.id}>
          <span>{item.name}</span><input type="checkbox" checked={cloud[item.id]} disabled={busy}
            onChange={(e) => toggleCloud(item.id, e.target.checked)} />
        </label>) : <p className="section-note">{settingsError ? "开关读取失败，请重试。" : "正在读取开关…"}</p>}</div>
        {settingsError && <button className="text-action" type="button" onClick={() => void reloadSettings()}>重试读取设置</button>}
        <details className="fold"><summary>模型与运行信息</summary>
          <button className="secondary" type="button" disabled={busy || hasKey !== true} onClick={fetchModels}>获取可用模型</button>
          {models.length > 0 && <><label htmlFor="model">当前选择</label>
            <select id="model" value={model} disabled={busy} onChange={(e) => { setModel(e.target.value); invalidate(); }}>
              <option value="">默认模型</option>{models.map((name) => <option key={name} value={name}>{name}</option>)}
            </select></>}
          <p className="section-note">运行计数仅统计本进程的模型网络尝试与会话扫描；重启后归零。</p>
          <button className="secondary" type="button" onClick={refreshActivity}>刷新计数</button>
          {activity && <div className="activity-counts" aria-live="polite">
            <span>运行时长</span><strong>{Math.floor(activity.uptime_seconds / 60)} 分 {activity.uptime_seconds % 60} 秒</strong>
            <span>模型网络尝试</span><strong>{activity.model_network_attempts}</strong>
            <span>会话扫描调用</span><strong>{activity.scan_invocations}</strong>
          </div>}
        </details>
      </section>}
      {notice && <p className="notice" role="status">{notice}</p>}
    </div>}
  </main>;
}

export default function App() { return currentSurface() === "pet" ? <Pet /> : <Card />; }
