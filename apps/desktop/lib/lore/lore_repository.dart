// 资料与出处原生仓库：复用当前 CoreSession，JSON 编解码在此完成。
// 读取条目/版本/出处；写入包括保存条目、绑定出处与拒绝候选；CAS 与校验由 Rust 负责。

import 'dart:convert';
import 'source_mark_controller.dart';
import '../native/generated/api.dart';

/// Repositories whose native session exposes lore access.
///
/// 工作区可选能力：暴露同一原生会话的 lore 仓库。
abstract interface class LoreHost {
  LoreRepository get lore;
}

/// Lore/source access shares the current native workspace session.
///
/// 资料与出处访问复用当前原生工作区会话；JSON 字符串在本层与 Map 互转。
final class LoreRepository implements SourceMarkRepository {
  const LoreRepository(this.session);
  final CoreSession session;
  List<Map<String, dynamic>> _rows(String value) => (jsonDecode(value) as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  /// 读取作品全部资料条目行，每行含 entry 与 head 对象。
  Future<List<Map<String, dynamic>>> list(String work) async =>
      _rows(await session.listLore(workId: work));

  /// 保存资料条目；edit 含 id 与 expectedVersion 时走 CAS 更新，为空表示新建。
  Future<void> save(String work, Map<String, dynamic> edit) async {
    await session.saveLore(workId: work, editJson: jsonEncode(edit));
  }

  /// 读取条目历史版本；版本号与 origin 由原生层给出。
  Future<List<Map<String, dynamic>>> versions(
    String work,
    String entry,
  ) async => _rows(await session.loreVersions(workId: work, entryId: entry));

  /// 读取条目已记录出处；anchor.isCurrent 表示是否仍指向当前正文。
  Future<List<Map<String, dynamic>>> sources(String work, String entry) async =>
      _rows(await session.loreSources(workId: work, entryId: entry));

  /// 绑定出处；版本身份与 UTF-16 区间由原生层校验，失败不产生部分绑定。
  Future<void> bind(String work, Map<String, dynamic> binding) =>
      session.bindLoreSource(workId: work, bindingJson: jsonEncode(binding));

  /// 拒绝候选条目，expectedVersion 做 CAS。
  Future<void> reject(String work, String id, int version) =>
      session.rejectLore(workId: work, entryId: id, expectedVersion: version);

  /// 章节 (id, 标题) 列表，供作用域下拉使用。
  Future<List<(String, String)>> chapterOptions(String work) async =>
      (await session.listChapters(
        workId: work,
      )).map((row) => (row.id, row.title)).toList();

  /// 读取某正文的出处标记投影，返回 headVersion 与 marks；偏移以 UTF-16 计。
  @override
  Future<Map<String, dynamic>> sourceMarks(
    String work,
    String chapter,
    String body,
  ) async =>
      jsonDecode(
            await session.chapterSourceMarks(
              work: work,
              chapter: chapter,
              body: body,
            ),
          )
          as Map<String, dynamic>;
}
