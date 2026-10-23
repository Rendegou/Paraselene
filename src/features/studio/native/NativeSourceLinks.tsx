import type { Studio } from "../useStudio";
/** 实体资料的正文出处列表：展示已绑定锚点（区分当前确认版本与过期出处），并支持绑定当前选段。 */
export function NativeSourceLinks({ studio, entityId }: { studio: Studio; entityId: string }) {
  const native = studio.native;
  if (!native) return null;
  const anchors = native.sources(entityId);
  return <div className="studio-source-list">
    {anchors.length === 0 && <p>尚无正文出处。先确认正文版本，再用正文选段绑定。</p>}
    {anchors.map((anchor) => <div key={anchor.id}>
      // isCurrent=false 表示绑定时的正文版本已不是当前确认稿，展示时显式标注，避免误信旧出处。
      <p>{anchor.isCurrent ? "当前确认版本出处" : "旧版本出处 · 当前稿已变化"}</p>
      <button type="button" onClick={() => void native.viewSource(anchor)}>查看绑定版本</button>
    </div>)}
    // 没有正文选段或正在写库时禁止绑定；选段来自编辑器选区，绑定后即成为该实体的新锚点。
    <button type="button" disabled={!studio.selection || native.busy} onClick={() => {
      if (studio.selection) void native.bindSource(entityId, studio.selection);
    }}>绑定当前正文选段</button>
  </div>;
}
