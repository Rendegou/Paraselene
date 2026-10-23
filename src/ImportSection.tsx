import { useEffect, useRef, useState } from "react";
import {
  cancelImportPreview, confirmImportFile, selectImportFile,
  type ImportCompletion, type ImportReview, type ImportSource,
} from "./lib/ipc";
import "./ImportSection.css";

// 可选导入来源与界面名称；新增来源需后端解析器同步支持。
const sources: { id: ImportSource; name: string }[] = [
  { id: "chatgpt", name: "ChatGPT" },
  { id: "codex", name: "Codex" },
  { id: "kimi", name: "Kimi" },
  { id: "claude", name: "Claude" },
];

// 对话消息角色的中文显示名；未知角色回退显示原始 role 字符串。
const roleName: Record<string, string> = { user: "我", assistant: "助手", system: "系统", developer: "开发者", tool: "工具" };

/**
 * 本机资料导入区：选来源 → 选文件并预览 → 确认写入本机索引。
 *
 * Props 契约：
 * - `onOpenIdeas`：导入成功后由用户触发的"去找旧想法"跳转回调。
 *
 * 预览生命周期：选文件后后端返回带 `token` 的预览句柄，确认或取消时必须用同一 token 收尾；
 * 组件卸载时若预览未收尾，自动向后端取消，避免预览会话泄漏。
 * 中途切换来源或重新选文件也会先取消旧预览。
 */
export default function ImportSection({ onOpenIdeas }: { onOpenIdeas: () => void }) {
  const [source, setSource] = useState<ImportSource>("chatgpt");
  const [review, setReview] = useState<ImportReview | null>(null);
  const [completion, setCompletion] = useState<ImportCompletion | null>(null);
  const [busy, setBusy] = useState<"choosing" | "importing" | null>(null);
  const [error, setError] = useState("");
  const token = useRef<string | null>(null);
  const mounted = useRef(true);
  const reviewHeading = useRef<HTMLHeadingElement>(null);

  // 挂载标志：选文件是异步的，若用户在文件对话框打开期间离开页面，
  // 收到预览结果后要通知后端取消，而不是在已卸载组件上 setState。
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (token.current) void cancelImportPreview(token.current);
    };
  }, []);

  // 放弃当前预览：取消后端预览会话并清空界面状态，供"取消/换来源/重选文件"复用。
  function forgetPreview() {
    if (token.current) void cancelImportPreview(token.current);
    token.current = null;
    setReview(null);
  }

  async function chooseFile() {
    forgetPreview(); setCompletion(null); setError(""); setBusy("choosing");
    try {
      const result = await selectImportFile(source);
      if (result) {
        if (!mounted.current) {
          // 组件已卸载：只补取消，不触碰任何 state。
          void cancelImportPreview(result.token);
          return;
        }
        token.current = result.token;
        setReview(result);
        // 预览区标题设了 tabIndex=-1，延迟聚焦让屏幕阅读器在内容出现后再朗读。
        window.setTimeout(() => reviewHeading.current?.focus(), 0);
      }
    } catch (cause) { setError(`文件未能预览：${String(cause)}`); }
    finally { setBusy(null); }
  }

  // 确认导入：token 必须与当前预览一致，防止"预览 A 后界面被换成预览 B 却确认了 A"。
  async function confirm() {
    if (!review || token.current !== review.token) return;
    setError(""); setBusy("importing");
    try {
      const result = await confirmImportFile(review.token);
      token.current = null;
      setReview(null);
      setCompletion(result);
    } catch (cause) {
      token.current = null;
      setReview(null);
      setError(`导入未完成：${String(cause)}。请重新选择文件，核对结果后再试。`);
    } finally { setBusy(null); }
  }

  return <section className="import-section" aria-labelledby="import-heading">
    <div className="section-title"><h3 id="import-heading">本机资料</h3></div>
    <p className="section-note">只有你选中的导出文件会被读取；先预览，再确认保存到本机索引。</p>
    <fieldset className="import-sources" disabled={busy !== null}>
      <legend>对话来自</legend>
      {sources.map((item) => <label key={item.id} className={source === item.id ? "chosen" : ""}>
        <input type="radio" name="import-source" value={item.id} checked={source === item.id}
          onChange={() => { forgetPreview(); setCompletion(null); setError(""); setSource(item.id); }} />
        {item.name}
      </label>)}
    </fieldset>
    <button className="secondary import-pick" type="button" disabled={busy !== null} onClick={chooseFile}>
      {busy === "choosing" ? "正在选择…" : "选择导出文件"}
    </button>
    <p className="section-note">ChatGPT 支持 Markdown ZIP；其他来源可选 Markdown、JSON、JSONL 或 TXT。</p>

    {/* 预览确认块：只读展示统计、警告与抽样消息；任何写入都要点下方"确认导入"显式触发。 */}
    {review && <div className="import-review">
      <h4 ref={reviewHeading} tabIndex={-1}>确认导入内容</h4>
      <p className="import-file-name">{review.fileName}</p>
      <p className="section-note">识别为{review.detectedFormat} · {review.sessions} 段对话 · {review.messages} 条消息</p>
      {(review.partial > 0 || review.failedFiles > 0 || review.warningCount > 0) &&
        <p className="import-warning" role="status">需核对：{review.partial} 段可能不完整，{review.failedFiles} 个文件未解析，{review.warningCount} 条提示。</p>}
      {review.warnings.length > 0 && <details><summary>查看解析提示</summary><ul>{review.warnings.map((warning, index) => <li key={index}>{warning}</li>)}</ul></details>}
      {review.sampleMessages.length > 0 && <div className="import-sample">
        <strong>内容抽样：{review.sampleTitle || "未命名会话"}</strong>
        {review.sampleMessages.map((message, index) => <p key={index}><span>{roleName[message.role] || message.role}</span>{message.text}</p>)}
      </div>}
      <div className="import-actions">
        <button className="primary" type="button" disabled={busy !== null} onClick={confirm}>
          {busy === "importing" ? "正在导入…" : `确认导入 ${review.sessions} 段对话`}
        </button>
        <button className="text-action" type="button" disabled={busy !== null} onClick={forgetPreview}>取消</button>
      </div>
    </div>}

    {completion && <div className="import-result" role="status">
      <p>新增 {completion.indexed} 段对话、{completion.messages} 条消息；重复 {completion.duplicates} 段。</p>
      {(completion.writeFailed > 0 || completion.scanFailed > 0 || completion.warningCount > 0) &&
        <p>另有 {completion.writeFailed + completion.scanFailed} 段失败、{completion.warningCount} 条提示，可重新选择文件核对。</p>}
      <button className="text-action" type="button" onClick={onOpenIdeas}>去找旧想法</button>
    </div>}
    {error && <p className="import-error" role="alert">{error}</p>}
  </section>;
}
