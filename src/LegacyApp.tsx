import { useEffect, useRef, useState } from "react";
import {
  currentSurface, defaultCharacter, deleteApiKey, exportCharacterPack, getCharacter,
  openEditorSpike,
  getCloudEnabled, getRuntimeActivity, hasApiKey, hideCard, importCharacterPack, onCharacterChanged,
  llmChatPreview, llmChatSend, llmFetchModels, openLearningWindow, setApiKey, setCloudEnabled,
  setCharacter, startWindowDrag, toggleCard, type CharacterConfig, type IssuedPreview, type RuntimeActivity, type Space,
} from "./lib/ipc";
import "./App.css";
import IdeaPage from "./IdeaPage";
import ImportSection from "./ImportSection";
import MemoryPage from "./MemoryPage";
import NovelEditor from "./NovelEditor";
import EditorSpike from "./features/novel/editor/EditorSpike";
import moonIdle from "./assets/companions/moon-idle.png";
import moonCurious from "./assets/companions/moon-curious.png";
import moonPoke from "./assets/companions/moon-poke.png";
import moonSleep from "./assets/companions/moon-sleep.png";
import moonBlink from "./assets/companions/moon-blink.png";
import starIdle from "./assets/companions/star-idle.png";
import starCurious from "./assets/companions/star-curious.png";
import starPoke from "./assets/companions/star-poke.png";
import starSleep from "./assets/companions/star-sleep.png";
import starBlink from "./assets/companions/star-blink.png";
import cloudIdle from "./assets/companions/cloud-idle.png";
import cloudCurious from "./assets/companions/cloud-curious.png";
import cloudPoke from "./assets/companions/cloud-poke.png";
import cloudSleep from "./assets/companions/cloud-sleep.png";
import cloudBlink from "./assets/companions/cloud-blink.png";

// 四个记忆/写入空间与界面名称；与后端 Space 枚举对应。
const spaces: { id: Space; name: string }[] = [
  { id: "personal", name: "个人" },
  { id: "idea", name: "旧想法" },
  { id: "novel", name: "小说" },
  { id: "learning", name: "学习" },
];

// 桌宠外观形态的中文名。
const appearanceNames: Record<CharacterConfig["appearance"], string> = {
  moon: "月亮", star: "星星", cloud: "云朵",
};

// 桌宠动作姿态；blink 不算姿态，是叠加在 idle 上的眨眼贴图，单独建表。
type PetPose = "idle" | "curious" | "poke" | "sleep";

// 每种形态的四姿态贴图与眨眼贴图，打包期静态引入（小图，不进懒加载 chunk）。
const companionImages: Record<CharacterConfig["appearance"], Record<PetPose, string>> = {
  moon: { idle: moonIdle, curious: moonCurious, poke: moonPoke, sleep: moonSleep },
  star: { idle: starIdle, curious: starCurious, poke: starPoke, sleep: starSleep },
  cloud: { idle: cloudIdle, curious: cloudCurious, poke: cloudPoke, sleep: cloudSleep },
};
const blinkImages: Record<CharacterConfig["appearance"], string> = {
  moon: moonBlink, star: starBlink, cloud: cloudBlink,
};

/** 桌宠立绘：按形态与姿态取图；纯展示，alt 置空并 aria-hidden 由外层按钮承担无障碍名称。 */
function CompanionArt({ appearance, pose = "idle" }: { appearance: CharacterConfig["appearance"]; pose?: PetPose }) {
  return <img className="companion-art" src={companionImages[appearance][pose]} alt="" draggable={false} aria-hidden="true" />;
}

/** 品牌月形标记（纯装饰 SVG），卡片标题区使用。 */
function MoonMark({ className }: { className: string }) {
  return <svg className={className} viewBox="0 0 32 32" aria-hidden="true">
    <path d="M21.8 2.8A13.5 13.5 0 1 0 29 22.2 11 11 0 0 1 21.8 2.8Z" />
  </svg>;
}

/**
 * 桌宠窗口本体：贴图 + 姿态状态机 + 点击开卡片 + 按住拖动窗口。
 *
 * 姿态约定：
 * - idle 为默认；curious 是"注意到人"的短时反应；poke 是点击后的开卡片前摇；sleep 是空闲 90 秒后进入；
 * - 所有姿态切换都受 `pointerNearby` / `openingCard` 两个 ref 守卫，避免定时器乱序覆盖用户正在交互的状态；
 * - 拖动用 `dragged` ref 区分"点击"与"拖动"：位移超过 6px 视为拖动并交原生层移动窗口，
 *   松手时不触发 click 开卡片。
 * 形象配置经 `getCharacter` 首读 + `onCharacterChanged` 订阅双通道同步。
 */
function Pet() {
  const [error, setError] = useState("");
  const [character, setCharacterState] = useState<CharacterConfig>(defaultCharacter);
  const [pose, setPose] = useState<PetPose>("idle");
  const sleepTimer = useRef<number | null>(null);
  const curiosityTimer = useRef<number | null>(null);
  const reactionTimer = useRef<number | null>(null);
  const openingCard = useRef(false);
  const pointerNearby = useRef(false);
  const dragOrigin = useRef<{ x: number; y: number } | null>(null);
  const dragged = useRef(false);

  function cancelSleep() {
    if (sleepTimer.current !== null) window.clearTimeout(sleepTimer.current);
    sleepTimer.current = null;
  }

  // 90 秒无交互且指针不在附近、卡片未打开时才入睡；任何排期前先取消旧定时器防重。
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

  // 注意到人：醒来 -> curious 反应 1.1 秒 -> 回到 idle 并重新排入睡。打开卡片期间不打扰。
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
    // 拖动结束的 pointerup 也会触发 click，用 dragged 标志消费掉这一次，避免拖动后误开卡片。
    if (dragged.current) {
      dragged.current = false;
      return;
    }
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

  // 进入页面即排入睡；卸载时清掉三个定时器，防止 setState 到已卸载组件。
  useEffect(() => {
    scheduleSleep();
    return () => {
      cancelSleep();
      cancelCuriosity();
      if (reactionTimer.current !== null) window.clearTimeout(reactionTimer.current);
    };
  }, []);

  // 形象同步：先读当前值，再订阅变更；卸载时取消防阅。active 标志挡住卸载后才到的响应。
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    getCharacter().then((value) => { if (active) setCharacterState(value); }).catch(() => setError("形象读取失败"));
    onCharacterChanged((value) => { if (active) setCharacterState(value); })
      .then((stop) => { if (active) unsubscribe = stop; else stop(); })
      .catch(() => setError("形象同步失败"));
    return () => { active = false; unsubscribe?.(); };
  }, []);

  // 形态切换后预载其余姿态贴图：姿态变化只换 src，不希望用户看到首次加载的空白帧。
  useEffect(() => {
    for (const nextPose of ["curious", "poke", "sleep"] as const) {
      const image = new Image();
      image.src = companionImages[character.appearance][nextPose];
    }
  }, [character.appearance]);

  return <main className={`pet pet-${character.appearance} pet-pose-${pose}`}
    onPointerEnter={() => { pointerNearby.current = true; noticePerson(); }} onPointerLeave={leavePet}>
    <button className="pet-body" type="button" aria-label={`点击打开${character.name}卡片，拖动移动${character.name}`}
      onFocus={noticePerson}
      onPointerDown={(event) => {
        // 只有鼠标左键能发起拖动；触屏点击走 click 开卡片，不参与窗口拖动。
        if (event.button !== 0 || event.pointerType !== "mouse") return;
        dragOrigin.current = { x: event.screenX, y: event.screenY };
        dragged.current = false;
      }}
      onPointerMove={(event) => {
        const origin = dragOrigin.current;
        if (!origin || event.buttons !== 1) return;
        // 6px 死区：区分"按下抖动"与"真的想拖"，越过阈值才交原生层接管窗口移动。
        if (Math.hypot(event.screenX - origin.x, event.screenY - origin.y) < 6) return;
        dragOrigin.current = null;
        dragged.current = true;
        void startWindowDrag().catch(() => setError("暂时无法拖动"));
      }}
      onPointerUp={() => { dragOrigin.current = null; }}
      onPointerCancel={() => { dragOrigin.current = null; }}
      onClick={openCard}>
      <span className="pet-animation">
        <CompanionArt appearance={character.appearance} pose={pose} />
        {pose === "idle" && <img className="companion-art companion-blink" src={blinkImages[character.appearance]}
          alt="" draggable={false} aria-hidden="true" />}
      </span>
    </button>
    {error && <span className="pet-error" role="status">{error}</span>}
  </main>;
}

/**
 * 卡片窗口本体：对话外发预览、旧想法/记忆/学习入口、形象设置与 Key/云开关设置。
 *
 * 外发两步模型：`prepare` 先在本地生成"将发送内容"的预览（IssuedPreview），
 * 用户确认后才 `send` 真正出网；任何影响内容的变更（输入、空间、模型、角色）都会使预览失效。
 *
 * 预览失效约定：`previewRevision` ref 单调递增，发起预览前记录值，响应回来时若已变更则丢弃——
 * 重渲染不创建第二个生成请求，旧预览不会盖掉新输入。
 *
 * 子页面契约：MemoryPage 通过 `onEditStateChange` 上报编辑中状态，
 * 这里转成 `memoryLocked` 禁用其他 tab，防止编辑未收尾时被切走。
 */
function Card() {
  const [tab, setTab] = useState<"chat" | "ideas" | "memory" | "learning" | "character" | "settings">("chat");
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
  const [memoryLocked, setMemoryLocked] = useState(false);
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

  // 使当前预览作废：凡是影响外发内容的变更（输入/空间/模型/角色）都必须调它。
  function invalidatePreview() { previewRevision.current += 1; setPreview(null); }

  function invalidate() { invalidatePreview(); setNotice(""); }

  // 一次性读 Key 存在性与各空间云开关；任一失败整体标记 settingsError，不做半套状态。
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

  // 第一步：只生成预览不出网；revision 校验丢弃"输入已变才回来的旧预览"。
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

  // 第二步：按预览 id 流式发送；结束时无论如何清掉预览，防止同一内容被确认两次。
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

  // Key 只进 Windows 凭据管理器，界面不回显；保存成功也只置 hasKey 标志。
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

  // 云开关按空间独立；变更后使预览失效，避免旧空间的预览被当成新空间内容发出。
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

  // 角色保存走草稿 -> 确认两步；生效后使预览失效（说话方式变了，旧预览不再代表新回复）。
  async function saveCharacter() {
    setBusy(true); setNotice("");
    try {
      const saved = await setCharacter(draftCharacter);
      setCharacterState(saved); setDraftCharacter(saved); invalidatePreview(); setPackOutput("");
      setNotice("角色设置已保存。下一次预览会使用新的说话方式。");
    } catch (error) { setNotice(`角色保存失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 分享包只含形象与说话方式，不含本地名称/密钥/对话；导出文本就地展示、聚焦全选复制。
  async function exportPack() {
    setBusy(true); setNotice("");
    try {
      setPackOutput(await exportCharacterPack());
      setNotice("分享内容已生成，只含形象和说话方式，不含本地名称。可复制下方 JSON。");
    } catch (error) { setNotice(`生成失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 导入分享包：后端做结构与内容校验，本地名称不被覆盖；导入后同样使预览失效。
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
    {/* 标题栏空白区域可拖动窗口；点在按钮上时不启动拖动。 */}
    <header className="card-header" onMouseDown={(event) => {
      if (event.button !== 0 || (event.target as Element).closest("button")) return;
      void startWindowDrag().catch(() => setNotice("卡片暂时无法拖动"));
    }}>
      <div className="brand"><MoonMark className="brand-mark" /><h1>{character.name}</h1></div>
      <button className="close" type="button" aria-label="关闭卡片" onClick={() => hideCard()}><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 4l12 12M16 4L4 16" /></svg></button>
    </header>
    <nav className="tabs" aria-label="卡片功能">
      {([ ["chat", "对话"], ["ideas", "旧想法"], ["memory", "记忆"], ["learning", "学习"], ["character", "形象"], ["settings", "设置"] ] as const).map(([id, label]) =>
        <button key={id} type="button" className={tab === id ? "active" : ""} aria-current={tab === id ? "page" : undefined}
          disabled={memoryLocked && id !== "memory"}
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
      {tab === "ideas" ? <IdeaPage onOpenImport={() => { setTab("settings"); setNotice(""); }} /> : tab === "memory" ? <MemoryPage onEditStateChange={setMemoryLocked} /> : tab === "learning" ? <section className="page learning-entry">
        <div className="page-heading"><h2>五分钟 Python 练习</h2></div>
        <p>先从一个纯函数开始。代码只在独立的本地练习窗口运行，关闭窗口即结束执行。</p>
        <button className="primary" type="button" onClick={() => { void openLearningWindow().catch((error) => setNotice(`练习窗口打不开：${String(error)}`)); }}>打开练习窗口</button>
        {notice && <p className="notice" role="status">{notice}</p>}
      </section> : tab === "character" ? <section className="page character-page">
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
      {/* 临时 spike 入口（T05B / ADR-0003，验证后移除） */}
      <section className="section"><h2>技术验证</h2>
        <button className="secondary" type="button" onClick={() => void openEditorSpike()}>打开编辑器 spike（T05B 验证窗口）</button>
      </section>
      {notice && <p className="notice" role="status">{notice}</p>}
    </div>}
  </main>;
}

/**
 * 历史窗口的分派出口：App.tsx 懒加载到本模块后再按 surface 细分
 * （pet 桌宠 / novel 小说编辑 / editor-spike 编辑器验证窗 / 默认卡片）。
 * 与 App.tsx 里的 studio 快速路径互补；新增窗口面时要两处同步。
 */
export default function App() {
  const surface = currentSurface();
  return surface === "pet" ? <Pet />
    : surface === "novel" ? <NovelEditor />
    : surface === "editor-spike" ? <EditorSpike />
    : <Card />;
}
