// M1 合成文档探针：经真实 FFI 验证精确文本、元数据、身份与双写者 CAS。
//
// 只写入显式标记的临时合成数据库，不读取作者库；不输出正文内容。
import '../native/generated/api.dart';
import 'assertions.dart';

/// Synthetic Unicode fixture deliberately includes CRLF and bidi controls.
///
/// 故意包含 CRLF、emoji ZWJ 序列、组合音标与 bidi 控制符的合成正文，
/// 用于验证逐字往返与内容 hash 不被归一化。
const syntheticBody =
    '中文\u{1f469}\u200d\u{1f4bb} e\u0301\r\n'
    '第二行\u2067العربية\u2069\r\n末尾';

/// Exercises exact text, metadata, identity and two-writer CAS through FFI.
///
/// 用两个会话走一遍创建作品/章节、保存、revision 冲突、身份不匹配、重新读取、
/// hash 往返与列表计数，最后返回安全的标识与 hash 摘要（不含正文）。
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
