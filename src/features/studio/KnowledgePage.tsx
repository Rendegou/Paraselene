import { useState } from "react";
import type { Knowledge, SourceReference, StudioView } from "./model";
import { StudioIcon } from "./StudioIcon";

interface KnowledgeProps {
  view: StudioView; entries: Knowledge[]; selectedId: string;
  select: (id: string) => void; update: (item: Knowledge) => void; onReference: (id: string) => void;
  references: SourceReference[];
}

/** 设定详情编辑区：描述 + 若干固定字段，全部受控直接写回 entry。 */
function DetailEditor({ entry, update }: { entry: Knowledge; update: (item: Knowledge) => void }) {
  return <div className="knowledge-detail">
    <label htmlFor="entity-description">人物与设定</label>
    <textarea id="entity-description" value={entry.description} onChange={(event) => update({ ...entry, description: event.target.value })} />
    {entry.details.map((detail, index) => <div className="knowledge-field" key={detail.label}>
      <label htmlFor={`entity-field-${index}`}>{detail.label}</label><textarea id={`entity-field-${index}`} value={detail.value}
        onChange={(event) => update({ ...entry, details: entry.details.map((item, position) => position === index ? { ...item, value: event.target.value } : item) })} />
    </div>)}
  </div>;
}

/**
 * 资料页（人物 / 世界观与伏笔两个视图共用）：左侧条目页签 + 详情文档。
 * 视图与 kind 的对应规则：characters 视图只看人物，其余视图排除人物。
 * 选中态回退到第一条，无条目时展示引导空态。
 */
export function KnowledgePage(props: KnowledgeProps) {
  // characters 视图 ↔ character 实体；world 视图 ↔ 非 character 实体（规则/伏笔等）。
  const entries = props.entries.filter((item) => props.view === "characters" ? item.kind === "character" : item.kind !== "character");
  // selectedId 未命中（如切换视图后）时回退到首条，保证页面始终有内容可展示。
  const selected = entries.find((item) => item.id === props.selectedId) ?? entries[0];
  if (!selected) return <section className="knowledge-page"><h1>从一条设定开始</h1><p>作品资料会在这里与正文关联。</p></section>;
  return <section className="knowledge-page">
    <div className="surface-title"><div><h1>{props.view === "characters" ? "人物设定" : "世界观与伏笔"}</h1><p>让每次行动，都有来处。</p></div><span className="surface-note">体验设定 · 可编辑</span></div>
    <nav className="entity-tabs" aria-label="设定条目">{entries.map((item) => <button type="button" key={item.id}
      className={selected.id === item.id ? "selected" : ""} aria-pressed={selected.id === item.id} onClick={() => props.select(item.id)}>{item.title}</button>)}</nav>
    <article className="entity-document"><div className="entity-heading"><span className="entity-monogram">{selected.title.slice(0, 1)}</span>
      <div><h2>{selected.title}</h2><p>{selected.subtitle}</p></div></div>
      <DetailEditor entry={selected} update={props.update} />
      <section className="entity-sources"><h3>正文中的依据</h3>{selected.references.map((id) => {
        const reference = props.references.find((item) => item.id === id);
        if (!reference) return null;
        return <button key={id} type="button" onClick={() => props.onReference(id)}><StudioIcon name="link" size={16} /><span><strong>{reference.title}</strong><q>{reference.quote}</q></span><StudioIcon name="arrow" size={16} /></button>;
      })}</section>
    </article>
  </section>;
}

// 示意地图上的固定点位（体验作品的虚构坐标），与 Knowledge 条目通过 selectedId 关联。
const places = [{ id: "harbor", x: 250, y: 350, name: "旧码头" }, { id: "tower", x: 530, y: 130, name: "北岸灯塔" }];

/** 故事示意地图（SVG）：点选地点联动下方详情，可跳转到相关正文出处。纯虚构示意，非真实地理。 */
export function StoryMap({ entries, onReference }: { entries: Knowledge[]; onReference: (id: string) => void }) {
  const [selectedId, setSelectedId] = useState("tower");
  const selected = entries.find((item) => item.id === selectedId);
  return <section className="map-page"><div className="surface-title"><div><h1>雾港地图</h1><p>把地点、人物与发生过的事放在一起。</p></div><span className="surface-note">故事示意地图</span></div>
    <div className="map-stage"><svg viewBox="0 0 800 520" role="img" aria-label="雾港示意地图，包含旧码头和北岸灯塔">
      <defs><pattern id="map-grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0H0V40" fill="none" stroke="#e4e8e3" strokeWidth=".6" /></pattern></defs>
      <rect width="800" height="520" fill="#eef1ec" /><rect width="800" height="520" fill="url(#map-grid)" />
      <path d="M0 0H380L420 60 400 110 450 190 400 235 360 265 330 330 310 420 240 520H0Z" fill="#fafaf6" stroke="#b8c6bc" strokeWidth="2" />
      <path d="M250 350 360 265 400 235 450 190 530 130" fill="none" stroke="#7c9687" strokeWidth="2" strokeDasharray="6 6" />
      <text x="570" y="335" className="map-water-label">潮 汐 湾</text><text x="92" y="245" className="map-land-label">雾港旧城</text>
      <text x="710" y="50" className="map-compass">北 ↑</text>
      {places.map((place) => <g key={place.id} role="button" tabIndex={0} aria-label={`查看${place.name}`} className="map-location"
        onClick={() => setSelectedId(place.id)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); setSelectedId(place.id); } }}>
        <circle cx={place.x} cy={place.y} r={selectedId === place.id ? 16 : 10} fill="#fff" stroke="#607e6e" strokeWidth="2" />
        <circle cx={place.x} cy={place.y} r="4" fill="#607e6e" /><text x={place.x + 24} y={place.y + 5}>{place.name}</text>
      </g>)}
      <text x="28" y="488" className="map-legend">虚构场景 · 示意坐标，非实际地理比例</text>
    </svg></div>
    {selected && <div className="map-location-detail"><div><span>当前地点</span><h2>{selected.title}</h2><p>{selected.description}</p></div>
      <button className="studio-button" type="button" onClick={() => onReference(selected.references[0])}>查看相关正文 <StudioIcon name="arrow" size={15} /></button></div>}
  </section>;
}
