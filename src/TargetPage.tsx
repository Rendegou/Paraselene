import { useEffect, useState } from "react";
import {
  convertedIdeaTarget, oldIdeaSource, openNovelEditor, updateConvertedIdeaTarget,
  type IdeaSource, type IdeaTarget, type IdeaTargetSpace,
} from "./lib/ipc";
import "./TargetPage.css";

// 按目标空间切换的界面文案：同一"目标"概念在小说/学习/记忆三个空间有不同称呼。
const targetNames: Record<IdeaTargetSpace, string> = {
  novel: "小说项目", learning: "学习目标", personal: "记忆卡",
};

// 摘要输入框的引导语，同样按空间区分。
const noteLabels: Record<IdeaTargetSpace, string> = {
  novel: "创作起点", learning: "下一步练什么", personal: "想记住的内容",
};

/**
 * 旧想法的"目标"编辑页：展示并允许修改一条已确认旧想法转出的目标（小说项目 / 学习目标 / 记忆卡）。
 *
 * Props 契约：
 * - `ideaId`：要打开的目标所属旧想法 id；
 * - `ideaTitle`：旧想法标题，仅作展示起点；
 * - `onBack`：返回旧想法列表的回调，由父组件（IdeaPage）提供。
 *
 * 状态来源：目标数据经 `convertedIdeaTarget` 一次性加载；保存走乐观锁（携带 `updatedAt`），
 * 后端版本不一致时由 IPC 报错并展示在 notice。
 */
export default function TargetPage({ ideaId, ideaTitle, onBack }: { ideaId: string; ideaTitle: string; onBack: () => void }) {
  const [target, setTarget] = useState<IdeaTarget | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [title, setTitle] = useState("");
  const [summary, setSummary] = useState("");
  const [source, setSource] = useState<IdeaSource | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");

  // 加载目标：active 标志防止组件已卸载或 ideaId 已切换后，旧响应回填新状态。
  useEffect(() => {
    let active = true;
    convertedIdeaTarget(ideaId).then((value) => {
      if (!active) return;
      setTarget(value);
      setTitle(value?.title ?? "");
      setSummary(value?.summary ?? "");
      setLoaded(true);
    }).catch((error) => {
      if (active) { setNotice(`目标未能打开：${String(error)}`); setLoaded(true); }
    });
    return () => { active = false; };
  }, [ideaId]);

  // 保存修改：以打开时的 updatedAt 做乐观锁；成功后同步本地表单，避免保存按钮因 changed 判定继续亮起。
  async function save() {
    if (!target || !title.trim()) return;
    setBusy(true); setNotice("");
    try {
      const updated = await updateConvertedIdeaTarget(ideaId, target.updatedAt, title.trim(), summary.trim());
      setTarget(updated); setTitle(updated.title); setSummary(updated.summary ?? "");
      setNotice("已保存到本机。");
    } catch (error) { setNotice(`未能保存：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 读取原始出处：出处记录可能已被索引清理移除（返回 null），此时给出说明而非报错。
  async function showSource() {
    setBusy(true); setNotice("");
    try {
      const result = await oldIdeaSource(ideaId);
      if (!result) { setNotice("原始出处已不可用。"); return; }
      setSource(result);
    } catch (error) { setNotice(`未能读取出处：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 打开小说编辑区仅对 novel 空间且已生成 workId 的目标可用。
  async function openNovel() {
    if (!target?.workId) return;
    setBusy(true); setNotice("");
    try { await openNovelEditor(target.workId); }
    catch (error) { setNotice(`小说编辑区暂时打不开：${String(error)}`); }
    finally { setBusy(false); }
  }

  // 表单是否与已保存版本一致；null（目标缺失）时视为无改动，保存按钮保持禁用。
  const changed = target && (title.trim() !== target.title || summary.trim() !== (target.summary ?? ""));

  // 三态渲染：加载中 / 目标已缺失（给返回入口）/ 正常编辑。messageSeq < 0 是"整段会话引用"的约定。
  return <section className="page target-page">
    <button className="text-action target-back" type="button" onClick={onBack}>← 返回旧想法</button>
    {!loaded ? <p className="section-note">正在打开目标…</p> : !target ?
      <div className="target-missing"><h2>目标已不可用</h2><p>这条旧想法的目标可能已被移除。原想法和出处仍可在上一页查看。</p></div> : <>
        <div className="page-heading"><h2>{targetNames[target.space]}</h2><p>从你确认的旧想法开始，写下现在想接着做的事。</p></div>
        <div className="target-origin"><span>起点</span><strong>{ideaTitle}</strong><button className="text-action" type="button" disabled={busy} onClick={showSource}>查看原话</button></div>
        <label htmlFor="target-title">{target.space === "novel" ? "作品名称" : "目标名称"}</label>
        <input id="target-title" type="text" value={title} maxLength={80} disabled={busy}
          onChange={(event) => setTitle(event.target.value)} />
        <label htmlFor="target-summary">{noteLabels[target.space]}</label>
        <textarea id="target-summary" rows={5} value={summary} maxLength={2000} disabled={busy}
          placeholder={target.space === "novel" ? "写下设定或下一场景的方向…" : target.space === "learning" ? "写下下一步要练的内容…" : "写下你想留下的线索…"}
          onChange={(event) => setSummary(event.target.value)} />
        <button className="primary wide" type="button" disabled={busy || !title.trim() || !changed} onClick={save}>
          {busy ? "请稍候…" : "保存"}
        </button>
        {target.space === "novel" && target.workId && <button className="secondary wide" type="button" disabled={busy} onClick={openNovel}>打开小说编辑区</button>}
        {source && <div className="target-source"><h3>原始出处</h3>
          <p className="section-note">{source.source || "原来源已移除"} · {source.sessionTitle || "未命名会话"} · {source.messageSeq < 0 ? "整段会话" : `第 ${source.messageSeq + 1} 条消息`}</p>
          {source.text ? <p>{source.text}</p> : <><p className="section-note">原消息已从索引移除；以下是保存时的短引用。</p><p>{source.anchor || "短引用也不可用"}</p></>}
        </div>}
      </>}
    {notice && <p className="notice" role="status">{notice}</p>}
  </section>;
}
