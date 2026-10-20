// synthetic_workspace_repository 的 part：为内存合成仓库生成与校验确认复核令牌。
// 读边界：只读取合成仓库内存中的章节、文档与版本映射，不访问文件或数据库。
// 关键不变量：令牌绑定作品、文档、head、修订、正文与目录上下文，任何漂移都以稳定冲突码失败。
part of 'synthetic_workspace_repository.dart';

/// In-memory review checks for the explicit fixture, never a native hash claim.
extension _SyntheticConfirmation on SyntheticWorkspaceRepository {
  // 目录上下文参与令牌，使确认期间其他章节的版本变化也会令令牌失效。
  String _context(String work) => jsonEncode([
    for (final c in _chapters.values)
      if (_owners[c.id] == work && c.headVersionId != null)
        [c.id, c.headVersionId],
  ]);

  PreparedConfirmation _prepareReview(
    String work,
    String chapter,
    String? head,
    int revision,
  ) {
    _chapter(work, chapter);
    final d = _documents[chapter]!;
    if (revision <= 0 || revision == 9223372036854775807) {
      throw const WorkspaceFailure('invalid_input');
    }
    _head(d, head);
    if (d.revision == null) throw const WorkspaceFailure('not_found');
    _cas(d, revision);
    if (d.baseHeadVersion != head) {
      throw const WorkspaceFailure('base_conflict');
    }
    return PreparedConfirmation(
      body: d.body,
      token: jsonEncode({
        'work': work,
        'document': chapter,
        'head': head,
        'revision': revision,
        'body': d.body,
        'context': _context(work),
      }),
    );
  }

  ChapterDocument _checkedReview(String work, String chapter, String token) {
    _chapter(work, chapter);
    final dynamic review;
    try {
      review = jsonDecode(token);
    } on FormatException {
      throw const WorkspaceFailure('invalid_input');
    }
    if (review is! Map<String, dynamic>) {
      throw const WorkspaceFailure('invalid_input');
    }
    if (review['work'] != work || review['document'] != chapter) {
      throw const WorkspaceFailure('identity_mismatch');
    }
    final d = _documents[chapter]!;
    if (d.revision == null) throw const WorkspaceFailure('not_found');
    if (review['revision'] != d.revision || review['body'] != d.body) {
      throw const WorkspaceFailure('revision_conflict');
    }
    if (review['head'] != d.headVersionId) {
      throw const WorkspaceFailure('head_conflict');
    }
    if (d.baseHeadVersion != d.headVersionId) {
      throw const WorkspaceFailure('base_conflict');
    }
    if (review['context'] != _context(work)) {
      throw const WorkspaceFailure('context_conflict');
    }
    return d;
  }
}
