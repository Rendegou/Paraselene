import { test } from "node:test";
import assert from "node:assert/strict";
import { applySuggestion, locateSource, parseProject, projectMarkdown } from "./previewModel";
import { sampleProject } from "./sample";
import { loadPreview, previewStorageKey, savePreview, type ProjectStorage } from "./previewStorage";

/** 测试用内存存储实现：模拟 localStorage 的最小接口。 */
function storage(): ProjectStorage {
  const values = new Map<string, string>();
  return { getItem: key => values.get(key) ?? null, setItem: (key, value) => { values.set(key, value); } };
}

/** 被改没或出现多次的引文不得跳转到编造位置——必须返回 null。 */
test("edited-away and ambiguous source quotes never jump to fabricated positions", () => {
  const project = structuredClone(sampleProject);
  assert.ok(locateSource(project, "ch-3", "“你还是来了。”"));
  project.chapters[2].body = "“你还是来了。”\n“你还是来了。”";
  assert.equal(locateSource(project, "ch-3", "“你还是来了。”"), null);
  assert.equal(locateSource(project, "missing", "一句话"), null);
  project.chapters[2].body = "新正文";
  assert.equal(locateSource(project, "ch-3", "“你还是来了。”"), null);
});

/** patch 只精确应用一个 UTF-16 选区，且正文快照变化后必须拒绝（含 😀 级代理对偏移的用例）。 */
test("patch applies exactly one UTF-16 selection and rejects changed chapter snapshots", () => {
  const project = structuredClone(sampleProject);
  project.chapters[2].body = "前文🌙对白与对白后文";
  const body = project.chapters[2].body;
  const from = body.indexOf("对白");
  const suggestion = { chapterId: "ch-3", from, to: from + 2, text: "对白", replacement: "新句", baseBody: body };
  const changed = applySuggestion(project, suggestion);
  assert.equal(changed.chapters[2].body, "前文🌙新句与对白后文");
  assert.equal(project.chapters[2].body, body);
  assert.throws(() => applySuggestion(changed, suggestion), /正文已变化/);
  assert.throws(() => applySuggestion(project, { ...suggestion, text: "假引用" }), /选段已失效/);
});

/** 刷新后能还原已保存预览，且不得改动示例工程或本机数据。 */
test("refresh restores saved preview without mutating sample or native data", () => {
  const store = storage();
  const project = loadPreview(store);
  project.chapters[2].body = "手写新正文";
  const saved = savePreview(store, project, 0);
  assert.equal(saved.revision, 1);
  assert.equal(loadPreview(store).chapters[2].body, "手写新正文");
  assert.notEqual(sampleProject.chapters[2].body, "手写新正文");
  assert.throws(() => savePreview(store, project, 0), /另一窗口已保存/);
});

/** 损坏存储与配额错误必须向外抛错，且绝不能覆盖已有数据。 */
test("damaged storage and quota failure surface errors and never replace data", () => {
  const store = storage();
  store.setItem(previewStorageKey, "broken-json");
  assert.throws(() => loadPreview(store));
  assert.throws(() => savePreview(store, sampleProject, 0));
  assert.equal(store.getItem(previewStorageKey), "broken-json");
  const full = { getItem: () => null, setItem: () => { throw new Error("quota"); } };
  assert.throws(() => savePreview(full, sampleProject, 0), /quota/);
});

/** 落盘前校验几何、标识与元数据：不合法的设定数据在渲染前即被拒绝。 */
test("saved entities validate geometry, identifiers and metadata before rendering", () => {
  const project = structuredClone(sampleProject);
  assert.deepEqual(parseProject(JSON.stringify(project)), project);
  const invalid = { ...project, entities: [{ ...project.entities[0], related: [42] }] };
  assert.throws(() => parseProject(JSON.stringify(invalid)), /设定数据损坏/);
  assert.throws(() => parseProject(JSON.stringify({ ...sampleProject, revision: -1 })), /格式不兼容/);
  assert.throws(() => parseProject(JSON.stringify({ ...sampleProject, chapters: [] })), /章节数据损坏/);
});

/** 导出的 Markdown 必须包含每一章正文与每一条设定。 */
test("export includes every edited chapter and entity", () => {
  const markdown = projectMarkdown(sampleProject);
  for (const chapter of sampleProject.chapters) assert.ok(markdown.includes(chapter.body));
  for (const entity of sampleProject.entities) assert.ok(markdown.includes(entity.body));
});
