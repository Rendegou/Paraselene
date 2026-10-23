import { useEffect, useRef, useState } from "react";
import {
  confirmOldIdea, confirmOldIdeaStatus, convertOldIdea, listOldIdeas, oldIdeaSource,
  setOldIdeaReminder, suggestOldIdea,
  type IdeaCandidate, type IdeaSource, type IdeaStatus, type IdeaTargetSpace, type SavedIdea,
} from "./lib/ipc";
import "./IdeaPage.css";
import TargetPage from "./TargetPage";

// 旧想法状态机的中文名与允许的流转方向；done/wrong 是终态（不可再流转）。
const statusNames: Record<IdeaStatus, string> = {
  liked: "还喜欢", started: "已开始", done: "已完成", shelved: "先放下", wrong: "记错了",
};

const nextStatuses: Record<IdeaStatus, IdeaStatus[]> = {
  liked: ["started", "shelved", "wrong"],
  started: ["done", "shelved", "wrong"],
  shelved: ["started", "wrong"],
  done: [], wrong: [],
};

// 想法可转去的空间与界面称呼，与 TargetPage 的 targetNames 保持一致。
const targetNames: Record<IdeaTargetSpace, string> = {
  novel: "小说项目", learning: "学习目标", personal: "普通记忆卡",
};

/**
 * 出处元信息行：来源产品 · 会话标题 · 消息序号，供候选与已保存想法两处复用。
 * `sequence < 0` 表示引用指向整段会话而非单条消息。
 */
function SourceMeta({ source, title, sequence }: { source: string; title: string | null; sequence: number }) {
  const sourceName = ({ chatgpt: "ChatGPT", codex: "Codex", kimi: "Kimi", claude: "Claude" } as Record<string, string>)[source] || source;
  return <p className="idea-source-meta">{sourceName} · {title || "未命名会话"} · {sequence < 0 ? "整段会话" : `第 ${sequence + 1} 条消息`}</p>;
}

/**
 * 旧想法页：从已导入对话中翻候选 → 命名并确认保存 → 管理状态/转目标空间。
 *
 * Props 契约：
 * - `onOpenImport`：无可候选时引导跳去导入区的回调（父组件切到设置 tab）。
 *
 * 候选流：`suggestOldIdea(nextCandidateIndex)` 按偏移取下一个候选，不做本地过滤；
 * `nextCandidateIndex` 在保存后归零，使下一轮建议从头开始。
 * 转为目标空间后整页切到 `TargetPage`（用 `targetIdeaId` 作为切换标志）。
 */
export default function IdeaPage({ onOpenImport }: { onOpenImport: () => void }) {
  const [saved, setSaved] = useState<SavedIdea[]>([]);
  const [candidate, setCandidate] = useState<IdeaCandidate | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [source, setSource] = useState<IdeaSource | null>(null);
  const [title, setTitle] = useState("");
  const [candidateStatus, setCandidateStatus] = useState<IdeaStatus>("liked");
  const [nextStatus, setNextStatus] = useState<IdeaStatus | "">("");
  const [targetSpace, setTargetSpace] = useState<IdeaTargetSpace | "">("");
  const [busy, setBusy] = useState(false);
  const [noCandidate, setNoCandidate] = useState(false);
  const [nextCandidateIndex, setNextCandidateIndex] = useState(0);
  const [notice, setNotice] = useState("");
  const [targetIdeaId, setTargetIdeaId] = useState<string | null>(null);
  const sourceHeading = useRef<HTMLHeadingElement>(null);
  const selected = saved.find((idea) => idea.id === selectedId) ?? null;
  const convertedSpace = selected?.payload?.convertedTo?.space;

  // 进入页面拉一次已保存列表；本页不轮询，候选与保存都靠用户显式触发。
  useEffect(() => {
    let active = true;
    listOldIdeas().then((items) => { if (active) setSaved(items); })
      .catch(() => { if (active) setNotice("读取已保存的旧想法失败，请重新打开此页。"); });
    return () => { active = false; };
  }, []);

  // 切到目标编辑页时把外层滚动容器回顶，避免带着旧想法页的长滚动位置进入新页。
  useEffect(() => {
    document.querySelector<HTMLElement>(".content")?.scrollTo({ top: 0 });
  }, [targetIdeaId]);

  // 翻下一条候选；找到则推进偏移，没找到则提示（不自动保存任何候选）。
  async function findCandidate() {
    setBusy(true); setNotice(""); setNoCandidate(false); setSource(null); setSelectedId(null); setTargetSpace("");
    try {
      const found = await suggestOldIdea(nextCandidateIndex);
      setCandidate(found); setTitle(""); setCandidateStatus("liked");
      setNoCandidate(found === null);
      if (found) setNextCandidateIndex((index) => index + 1);
    } catch (error) { setNotice(`查找失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 确认保存候选：连同原始出处一起入库；新想法置顶并选中，候选流偏移归零。
  async function saveCandidate() {
    if (!candidate || !title.trim()) return;
    setBusy(true); setNotice("");
    try {
      const idea = await confirmOldIdea(candidate, title.trim(), candidateStatus);
      setSaved((items) => [idea, ...items]);
      setSelectedId(idea.id); setNextStatus(""); setTargetSpace(""); setCandidate(null); setTitle("");
      setNextCandidateIndex(0);
      setNotice("已保存这条旧想法及原始出处。");
    } catch (error) { setNotice(`保存失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 状态流转按上面的状态机校验（UI 只给合法选项），后端仍会以旧状态做乐观锁校验。
  async function changeStatus() {
    if (!selected || !nextStatus) return;
    setBusy(true); setNotice("");
    try {
      const updated = await confirmOldIdeaStatus(selected.id, selected.status, nextStatus);
      setSaved((items) => items.map((idea) => idea.id === updated.id ? updated : idea));
      setNextStatus(""); setNotice(`已确认状态：${statusNames[updated.status]}。`);
    } catch (error) { setNotice(`状态未更改：${String(error)}。请重新打开此页核对。`); }
    finally { setBusy(false); }
  }

  async function openSavedSource() {
    if (!selected) return;
    setBusy(true); setNotice("");
    try {
      const result = await oldIdeaSource(selected.id);
      if (!result) { setNotice("这条想法没有可用的出处记录。"); return; }
      setSource(result);
      window.setTimeout(() => sourceHeading.current?.focus(), 0);
    } catch (error) { setNotice(`读取原文失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 转为目标空间：成功后只更新列表行并切页；已转过的想法不会再显示转换入口（见下方渲染分支）。
  async function convert() {
    if (!selected || !targetSpace) return;
    setBusy(true); setNotice("");
    try {
      const result = await convertOldIdea(selected.id, targetSpace);
      setSaved((items) => items.map((idea) => idea.id === result.idea.id ? result.idea : idea));
      setTargetSpace("");
      setTargetIdeaId(selected.id);
    } catch (error) { setNotice(`创建失败：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 提醒偏好是"永不主动提起"的布尔取反切换，无需确认弹窗。
  async function changeReminder() {
    if (!selected) return;
    const never = selected.reminderPref?.mode !== "never";
    setBusy(true); setNotice("");
    try {
      const updated = await setOldIdeaReminder(selected.id, never);
      setSaved((items) => items.map((idea) => idea.id === updated.id ? updated : idea));
      setNotice(never ? "已记录：以后不主动提起这条。" : "已记录：以后可以主动提起这条。");
    } catch (error) { setNotice(`提醒偏好未更改：${String(error)}`); }
    finally { setBusy(false); }
  }

  // targetIdeaId 非空时整页替换为目标编辑页；返回即回到本页，候选与选中态保持。
  if (targetIdeaId) return <TargetPage ideaId={targetIdeaId}
    ideaTitle={saved.find((idea) => idea.id === targetIdeaId)?.title ?? "旧想法"}
    onBack={() => setTargetIdeaId(null)} />;

  return <section className="page idea-page">
    <div className="page-heading"><h2>旧想法</h2><p>从已导入的对话里找一条，先看原文，再由你决定。</p></div>

    <div className="idea-find">
      <button className="primary" type="button" disabled={busy} onClick={findCandidate}>{busy ? "请稍候…" : nextCandidateIndex > 0 ? "再找一条" : "找一条旧想法"}</button>
      <p>只查本机索引，不调用模型；候选不会自动保存。</p>
    </div>

    {noCandidate && <div className="idea-empty" role="status"><p>在已导入资料中没找到更多符合当前线索的旧想法。</p>
      <button className="text-action" type="button" onClick={onOpenImport}>去导入对话资料</button></div>}

    {candidate && <div className="idea-candidate">
      <h3>找到一段可能有关的原话</h3>
      <blockquote>{candidate.excerpt}</blockquote>
      <SourceMeta source={candidate.source} title={candidate.sessionTitle} sequence={candidate.messageSeq} />
      <details className="idea-original"><summary>查看这条消息的完整原文</summary><p>{candidate.sourceText}</p></details>
      <label htmlFor="idea-title">给这条想法起个标题</label>
      <input id="idea-title" type="text" maxLength={80} value={title} disabled={busy}
        placeholder="用自己的话概括" onChange={(event) => setTitle(event.target.value)} />
      <label htmlFor="idea-first-status">现在的状态</label>
      <select id="idea-first-status" value={candidateStatus} disabled={busy}
        onChange={(event) => setCandidateStatus(event.target.value as IdeaStatus)}>
        {(Object.keys(statusNames) as IdeaStatus[]).map((status) => <option key={status} value={status}>{statusNames[status]}</option>)}
      </select>
      <div className="idea-actions"><button className="primary" type="button" disabled={busy || !title.trim()} onClick={saveCandidate}>确认保存</button>
        <button className="secondary" type="button" disabled={busy} onClick={() => setCandidate(null)}>暂不保存</button></div>
    </div>}

    <div className="idea-saved">
      <h3>已保存</h3>
      {saved.length === 0 ? <p className="section-note">还没有已确认的旧想法。</p> : <div className="idea-list">
        {saved.map((idea) => <button key={idea.id} type="button" className={selectedId === idea.id ? "selected" : ""}
          aria-pressed={selectedId === idea.id} onClick={() => { setSelectedId(idea.id); setNextStatus(""); setTargetSpace(""); setSource(null); setCandidate(null); }}>
          <span>{idea.title}</span><small>{statusNames[idea.status]}</small>
        </button>)}
      </div>}
    </div>

    {selected && <div className="idea-detail">
      <h3>{selected.title}</h3><p className="section-note">当前状态：{statusNames[selected.status]}</p>
      <button className="text-action" type="button" disabled={busy} onClick={openSavedSource}>打开原始出处</button>
      {nextStatuses[selected.status].length > 0 && <div className="idea-status-change">
        <label htmlFor="idea-next-status">更改状态</label>
        <select id="idea-next-status" value={nextStatus} disabled={busy}
          onChange={(event) => setNextStatus(event.target.value as IdeaStatus | "")}>
          <option value="">选择下一状态</option>
          {nextStatuses[selected.status].map((status) => <option key={status} value={status}>{statusNames[status]}</option>)}
        </select>
        <button className="secondary" type="button" disabled={busy || !nextStatus} onClick={changeStatus}>确认状态</button>
      </div>}
      {convertedSpace ? <div className="idea-converted"><p className="section-note">已转为{targetNames[convertedSpace]}，出处仍保留。</p>
          <button className="secondary" type="button" disabled={busy} onClick={() => setTargetIdeaId(selected.id)}>打开{targetNames[convertedSpace]}</button></div>
        : <div className="idea-status-change">
          <label htmlFor="idea-target-space">把这条想法发展为</label>
          <select id="idea-target-space" value={targetSpace} disabled={busy}
            onChange={(event) => setTargetSpace(event.target.value as IdeaTargetSpace | "")}>
            <option value="">选择去向</option>
            {(Object.keys(targetNames) as IdeaTargetSpace[]).map((space) => <option key={space} value={space}>{targetNames[space]}</option>)}
          </select>
          <button className="secondary" type="button" disabled={busy || !targetSpace} onClick={convert}>确认创建</button>
        </div>}
      <button className="text-action idea-reminder" type="button" disabled={busy} onClick={changeReminder}>
        {selected.reminderPref?.mode === "never" ? "允许以后主动提起" : "以后不再主动提起"}
      </button>
    </div>}

    {selected && source && <div className="idea-source-view">
      <h3 ref={sourceHeading} tabIndex={-1}>原始出处</h3>
      <SourceMeta source={source.source || "原来源已移除"} title={source.sessionTitle} sequence={source.messageSeq} />
      {source.text ? <p className="idea-full-text">{source.text}</p>
        : <><p className="section-note">原消息已从索引移除；以下仅是保存时的短引用。</p><p className="idea-full-text">{source.anchor || "短引用也不可用"}</p></>}
    </div>}

    {notice && <p className="notice" role="status">{notice}</p>}
  </section>;
}
