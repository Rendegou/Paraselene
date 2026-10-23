import { test } from "node:test";
import assert from "node:assert/strict";
import { NativeLore } from "./nativeLore";
import { createLoreAdapter } from "./loreAdapter";
import type { LoreEntry, LoreVersion } from "../../../lib/ipc";

/** 条目测试桩。 */
function entry(id: string, headVersion: number): LoreEntry {
  return { id, workId: "work", kind: "character", name: id, aliases: [], status: "confirmed",
    scope: "whole", headVersion, createdAt: "now", updatedAt: "now" };
}
/** 版本测试桩。 */
function version(id: string, number: number, body: string): LoreVersion {
  return { id: `${id}-${number}`, entryId: id, version: number, body, confirmed: true, origin: "author", createdAt: "now" };
}

/** 聚合 reload 失败时，可见草稿的原始 CAS 快照必须原样保留（不被更新 revision 污染）。 */
test("failed aggregate lore reload leaves the visible draft's original CAS snapshot intact", async () => {
  let reloading = false;
  const adapter = createLoreAdapter({
    listLore: async () => reloading ? [entry("a", 2), entry("b", 1)] : [entry("a", 1)],
    loreVersions: async (id) => {
      if (id === "b") throw new Error("synthetic missing version");
      return [version("a", reloading ? 2 : 1, reloading ? "remote newer body" : "visible body")];
    },
    listLoreSourceAnchors: async () => [],
  });
  const lore = new NativeLore("work", adapter);
  const [visible] = await lore.load();
  reloading = true;
  await assert.rejects(lore.load(), /missing version/);
  const beforeEdit = lore.saves.getState("work", "a");
  assert.equal(beforeEdit.expectedRevision, 1);
  assert.equal(JSON.parse(beforeEdit.body).body, "visible body");
  lore.edit({ ...visible, body: "local next edit" });
  assert.equal(lore.saves.getState("work", "a").expectedRevision, 1);
  assert.equal(JSON.parse(lore.saves.getState("work", "a").body).body, "local next edit");
});

/** 迟到的旧批次不能覆盖新批次的 CAS revision（loadGeneration 作废机制）。 */
test("an older delayed batch cannot reinstall an obsolete lore CAS revision", async () => {
  let lists = 0, reads = 0;
  let releaseOld!: (value: LoreVersion[]) => void;
  let started!: () => void;
  const oldStarted = new Promise<void>((resolve) => { started = resolve; });
  const adapter = createLoreAdapter({
    listLore: async () => [entry("a", ++lists)],
    loreVersions: async () => {
      if (++reads === 1) {
        started();
        return new Promise<LoreVersion[]>((resolve) => { releaseOld = resolve; });
      }
      return [version("a", 2, "new batch body")];
    },
    listLoreSourceAnchors: async () => [],
  });
  const lore = new NativeLore("work", adapter);
  const old = lore.load();
  await oldStarted;
  await lore.load();
  releaseOld([version("a", 1, "old batch body")]);
  assert.deepEqual(await old, []);
  assert.equal(lore.saves.getState("work", "a").expectedRevision, 2);
  assert.equal(JSON.parse(lore.saves.getState("work", "a").body).body, "new batch body");
});
