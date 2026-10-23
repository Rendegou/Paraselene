import { useEffect, useRef, useState } from "react";
import { hasApiKey, setApiKey, deleteApiKey, getCloudEnabled, setCloudEnabled } from "../../../lib/ipc";

/** Key 只在用户填写期间存在于密码输入；存入 Windows 凭据管理器，不回读明文。 */
export function NativeModelSettings() {
  const [open, setOpen] = useState(false), [key, setKey] = useState("");
  const [configured, setConfigured] = useState<boolean | null>(null), [enabled, setEnabled] = useState(false);
  const [busy, setBusy] = useState(false), [error, setError] = useState("");
  const dialog = useRef<HTMLDialogElement>(null), trigger = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    dialog.current?.showModal();
    let active = true;
    void Promise.all([hasApiKey(), getCloudEnabled("novel")]).then(([exists, cloud]) => {
      if (active) { setConfigured(exists); setEnabled(cloud); }
    }).catch((reason: unknown) => { if (active) setError(`本机模型设置读取失败：${String(reason)}`); });
    return () => { active = false; trigger.current?.focus(); };
  }, [open]);
  const close = () => { setKey(""); setOpen(false); };
  async function save() {
    if (!key.trim() || busy) return;
    setBusy(true); setError("");
    try { await setApiKey(key.trim()); setConfigured(true); }
    catch (reason) { setError(`凭据存储失败：${String(reason)}`); }
    finally { setKey(""); setBusy(false); }
  }
  async function remove() {
    setBusy(true); setError("");
    try { await deleteApiKey(); setConfigured(false); }
    catch (reason) { setError(`凭据删除失败：${String(reason)}`); }
    finally { setBusy(false); }
  }
  async function toggleCloud(value: boolean) {
    setBusy(true); setError("");
    try { await setCloudEnabled("novel", value); setEnabled(value); }
    catch (reason) { setError(`云调用开关未保存：${String(reason)}`); }
    finally { setBusy(false); }
  }
  return <>
    <button type="button" ref={trigger} onClick={() => { setError(""); setConfigured(null); setOpen(true); }}>模型设置</button>
    {open && <dialog ref={dialog} className="native-model-settings" onCancel={close}>
      <header><h2>官方 DeepSeek</h2><button type="button" onClick={close} aria-label="关闭模型设置">×</button></header>
      <p>{configured === null ? "正在读取本机凭据状态…" : configured ? "本机已配置 API Key；有效性以实际请求为准。" : "尚未配置 API Key。离线写作和导出仍可使用。"}</p>
      <form onSubmit={(event) => { event.preventDefault(); void save(); }}>
        <label htmlFor="native-model-key">DeepSeek API Key</label>
        <input id="native-model-key" type="password" value={key} autoComplete="off" spellCheck={false} disabled={busy} onChange={(event) => setKey(event.target.value)} />
        <button type="submit" disabled={busy || !key.trim()}>保存到 Windows 凭据管理器</button>
        {configured && <button type="button" disabled={busy} onClick={() => void remove()}>移除本机 Key</button>}
      </form>
      <label><input type="checkbox" checked={enabled} disabled={busy || configured === null} onChange={(event) => void toggleCloud(event.target.checked)} /> 允许小说空间云调用</label>
      <p>仅在你查看材料并确认发送后调用模型。设置 Key 或打开云开关不会自动发送。</p>
      {error && <p role="alert">{error}</p>}
    </dialog>}
  </>;
}
