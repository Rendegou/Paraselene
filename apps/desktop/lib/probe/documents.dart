import '../native/generated/api.dart';
import 'assertions.dart';

/// Synthetic Unicode fixture deliberately includes CRLF and bidi controls.
const syntheticBody =
    '中文\u{1f469}\u200d\u{1f4bb} e\u0301\r\n'
    '第二行\u2067العربية\u2069\r\n末尾';

/// Exercises exact text, metadata, identity and two-writer CAS through FFI.
Future<Map<String, Object>> probeDocuments(
  CoreSession first,
  CoreSession second,
) async {
  final work = await first.createWork(title: 'M1 合成作品');
  final other = await first.createWork(title: 'M1 隔离作品');
  final chapter = await first.createChapter(workId: work.id, title: '合成章节');
  final initial = await first.load(workId: work.id, documentId: chapter.id);
  require(initial.revision == null, 'new_revision_not_null');
  final saved = await first.save(
    workId: work.id,
    documentId: chapter.id,
    body: syntheticBody,
  );
  final stale = await second.load(workId: work.id, documentId: chapter.id);
  final updated = await first.save(
    workId: work.id,
    documentId: chapter.id,
    expectedRevision: saved.revision,
    body: syntheticBody,
  );
  await expectBridgeError(
    'revision_conflict',
    () => second.save(
      workId: work.id,
      documentId: chapter.id,
      expectedRevision: stale.revision,
      body: 'stale synthetic text',
    ),
  );
  await expectBridgeError(
    'identity_mismatch',
    () => first.load(workId: other.id, documentId: chapter.id),
  );
  final loaded = await second.load(workId: work.id, documentId: chapter.id);
  require(loaded.body == syntheticBody, 'unicode_roundtrip');
  require(loaded.contentHash == updated.contentHash, 'hash_roundtrip');
  require((await first.listWorks()).length == 2, 'work_count');
  require(
    (await first.listChapters(workId: work.id)).length == 1,
    'chapter_count',
  );
  return {
    'workId': work.id,
    'chapterId': chapter.id,
    'contentHash': loaded.contentHash!,
    'revision': loaded.revision!.toString(),
  };
}
