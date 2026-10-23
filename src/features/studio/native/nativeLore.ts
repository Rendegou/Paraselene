import { novelSaveLoreEntry, novelListVersions } from "../../../lib/ipc";
import type { LoreEntry, SourceAnchor } from "../../../lib/ipc";
import { loreAdapter, type LoreAdapter } from "./loreAdapter";
import { SaveCoordinator } from "./saveCoordinator";
import type { Entity, EntityKind } from "../types";

/** 一条资料的完整快照：后端条目 + 出处锚点 + head 正文 + 前端实体视图。 */
interface LoreSnapshot { entry: LoreEntry; anchors: SourceAnchor[]; body: string; entity: Entity }

/**
 * Author lore drafts retain a version CAS; explicit save confirms the selected author revision.
 * 设定（lore）领域对象：条目编辑稿同样走版本 CAS（headVersion 即 revision），
 * 经 SaveCoordinator 防抖落盘；confirm 显式确认作者版本。
 */
export class NativeLore {
  private entries = new Map<string, LoreEntry>();
  private anchors = new Map<string, SourceAnchor[]>();
  /** 加载世代计数：作废迟到的批量读取结果。 */
  private loadGeneration = 0;
  /** 编辑稿保存协调器：body 序列化为 { name, body } JSON；冲突以"版本冲突"消息识别。 */
  readonly saves = new SaveCoordinator({
    save: async (request) => {
      const entry = this.entries.get(request.documentId);
      if (!entry || entry.workId !== request.workId || request.expectedRevision === null) throw new Error("资料归属无效");
      const value: { name: string; body: string } = JSON.parse(request.body);
      const saved = await novelSaveLoreEntry(entry.id, request.expectedRevision, value.name, value.body, entry.aliases, entry.scope, false);
      this.entries.set(entry.id, saved);
      return { revision: saved.headVersion, savedAt: saved.updatedAt };
    },
    isConflict: (error) => String(error).includes("版本冲突"),
  });
  constructor(readonly workId: string, private readonly adapter: LoreAdapter = loreAdapter) {}
  /** 加载全部设定条目并装配为前端实体；任何快照读取失败都让整个 load 抛错（不安装半成品）。 */
  async load(): Promise<Entity[]> {
    const generation = ++this.loadGeneration;
    const entries = await this.adapter.list(this.workId);
    const snapshots = await Promise.all(entries.filter((entry) => ["character", "location", "world"].includes(entry.kind)).map((entry) => this.readSnapshot(entry)));
    if (generation !== this.loadGeneration) return [];
    // Failed reads must not install newer CAS revisions behind an unchanged visible draft.
    for (const snapshot of snapshots) this.install(snapshot);
    return snapshots.map((snapshot) => snapshot.entity);
  }
  /** 读取单个条目的版本与出处锚点；head 版本正文缺失视为数据损坏。 */
  private async readSnapshot(entry: LoreEntry): Promise<LoreSnapshot> {
    const [versions, anchors] = await Promise.all([this.adapter.versions(entry.id), this.adapter.listSources(this.workId, entry.id)]);
    const body = versions.find((version) => version.version === entry.headVersion)?.body;
    if (body === undefined) throw new Error("资料版本缺失");
    return { entry, anchors, body, entity: { id: entry.id, kind: entry.kind as EntityKind, name: entry.name, body,
      subtitle: entry.status === "confirmed" ? "已确认设定" : "作者编辑稿 · 尚未确认", sources: [], related: [] } };
  }
  /**
   * 安装快照到保存协调器（建立 CAS 基线）并缓存条目/锚点。
   * hydrate 的前提是协调器槽位干净——见 load 的整体失败语义。
   */
  private install({ entry, anchors, body }: LoreSnapshot) {
    this.saves.hydrate({ workId: this.workId, documentId: entry.id, expectedRevision: entry.headVersion, baseHead: null,
      body: JSON.stringify({ name: entry.name, body }) });
    this.entries.set(entry.id, entry); this.anchors.set(entry.id, anchors);
  }
  /** 新建设定条目（authorConfirmed 直接确认首版）并安装快照。 */
  async create(kind: EntityKind): Promise<Entity> {
    const names = { character: "新人物", location: "新地点", world: "新世界规则" };
    const entry = await this.adapter.create(this.workId, { kind, name: names[kind], body: "", authorConfirmed: true });
    const snapshot = await this.readSnapshot(entry); this.install(snapshot);
    return snapshot.entity;
  }
  /** 本地编辑入口：序列化后推入保存协调器（实际落盘由协调器 flush）。 */
  edit(entity: Entity) {
    this.saves.edit(this.workId, entity.id, JSON.stringify({ name: entity.name, body: entity.body }));
  }
  /**
   * 确认设定：先把编辑稿落盘，再以最新 headVersion 做确认写（authorConfirmed=true），
   * 最后重建 CAS 基线。冲突时由 SaveCoordinator 抛出，调用方感知。
   */
  async confirm(id: string) {
    await this.saves.flushDocument(this.workId, id);
    const entry = this.entries.get(id);
    if (!entry) throw new Error("资料不存在");
    const state = this.saves.getState(this.workId, id);
    const value: { name: string; body: string } = JSON.parse(state.body);
    const saved = await novelSaveLoreEntry(id, entry.headVersion, value.name, value.body, entry.aliases, entry.scope, true);
    this.entries.set(id, saved);
    this.saves.hydrate({ ...state, expectedRevision: saved.headVersion });
  }
  /** 取条目缓存的出处锚点列表（未加载时为空数组）。 */
  sources(id: string) { return this.anchors.get(id) ?? []; }
  /** 重新拉取条目的出处锚点（绑定新锚点后调用）。 */
  async refreshSources(id: string) { this.anchors.set(id, await this.adapter.listSources(this.workId, id)); }
  /** 读出处锚点指向的绑定版本正文；版本不存在抛错（不跳相似版本）。 */
  async versionBody(anchor: SourceAnchor) {
    const versions = await novelListVersions(anchor.documentId);
    const version = versions.find((item) => item.id === anchor.sourceVersionId);
    if (!version) throw new Error("绑定版本不存在");
    return version.body;
  }
}
