import { useState } from "react";
import type { Studio } from "../useStudio";
import type { Entity } from "../types";
import { NativeSourceLinks } from "./NativeSourceLinks";

/**
 * 原生模式下单个设定实体（人物/世界观条目等）的详情卡片。
 * 编辑态直接写本地 state（受控输入），点"保存并确认"才落库；名称/正文长度有硬上限。
 */
export function NativeEntityDetail({ studio, entity }: { studio: Studio; entity: Entity }) {
  const [editing, setEditing] = useState(false);
  const native = studio.native!;
  return <article className="studio-entity-detail">
    <div className="studio-entity-heading">
      {editing ? <div><label htmlFor="native-entity-name">设定名称</label>
        <input id="native-entity-name" maxLength={120} value={entity.name} onChange={(event) => native.updateEntity(entity.id, "name", event.target.value)} /></div>
        : <h2>{entity.name}</h2>}
      <span className="studio-author-tag">{entity.subtitle}</span>
    </div>
    {editing ? <><label htmlFor="native-entity-body">资料正文</label>
      <textarea id="native-entity-body" className="studio-entity-body" value={entity.body} maxLength={20000}
        onChange={(event) => native.updateEntity(entity.id, "body", event.target.value)} /></>
      : <div className="studio-entity-body">{entity.body || "这份资料尚未填写。"}</div>}
    <div>
      <button type="button" onClick={() => setEditing((value) => !value)}>{editing ? "结束编辑" : "编辑资料"}</button>
      // busy 时禁用，避免同一实体并发重复保存。
      <button type="button" disabled={native.busy} onClick={() => void native.saveEntity(entity.id)}>保存并确认这份设定</button>
    </div>
    <h3 className="studio-section-heading">正文出处</h3>
    <NativeSourceLinks studio={studio} entityId={entity.id} />
  </article>;
}
