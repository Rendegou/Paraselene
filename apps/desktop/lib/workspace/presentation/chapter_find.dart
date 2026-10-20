// 章节内文本查找栏：按字面量查找并用编辑器选区高亮匹配，回车继续下一个匹配。
// 读边界：只读取编辑器当前文档的原始文本，不写仓库；位置按 Unicode 码点报告，与章节历史一致。
// 关键不变量：空查询不查找；到结尾后从开头循环一次；切换章节时清空上一次的匹配游标。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_input_client.dart';
import '../../l10n/generated/app_localizations.dart';

/// In-chapter literal find. The query field keeps focus while the editor
/// paints the exact selected match, so Enter continues with the next match.
///
/// 章节内查找栏；查询输入框保持焦点，编辑器只负责显示选中的匹配。
class ChapterFindBar extends StatefulWidget {
  const ChapterFindBar({
    required this.editor,
    required this.onClose,
    this.chapterId,
    super.key,
  });
  final EditorInputClient editor;
  final VoidCallback onClose;
  final String? chapterId;

  @override
  State<ChapterFindBar> createState() => ChapterFindBarState();
}

/// 查找栏状态；持有查询控制器与焦点，切换章节时重置匹配游标与结果。
class ChapterFindBarState extends State<ChapterFindBar> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'chapter find');
  int _cursor = -1;
  String _result = '';

  @override
  void didUpdateWidget(ChapterFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId) {
      _cursor = -1;
      _result = '';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The global Ctrl+F handler reuses the open bar instead of stacking one.
  ///
  /// 全局 Ctrl+F 复用已打开的查找栏：重新聚焦并全选现有查询。
  void focusInput() {
    _focus.requestFocus();
    _query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _query.text.length,
    );
  }

  void _changed(String _) {
    setState(() {
      _cursor = -1;
      _result = '';
    });
  }

  /// Exact literal match; wraps once at the end of the chapter.
  void _findNext() {
    final strings = AppLocalizations.of(context);
    final raw = widget.editor.document.raw;
    final query = _query.text;
    if (query.isEmpty) return;
    var at = raw.indexOf(query, _cursor + 1);
    if (at < 0) at = raw.indexOf(query);
    if (at < 0) {
      setState(() => _result = strings.findNoMatch);
      return;
    }
    _cursor = at;
    widget.editor.select(
      TextSelection(baseOffset: at, extentOffset: at + query.length),
    );
    // Position is reported in Unicode code points, matching the storage
    // contract used by chapter history and word counts.
    final position = raw.substring(0, at).runes.length + 1;
    setState(() => _result = strings.findPosition('$position'));
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Focus(
      onKeyEvent: _key,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: strings.findPrompt,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _changed,
                onSubmitted: (_) => _findNext(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _findNext, child: Text(strings.findNext)),
            if (_result.isNotEmpty)
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _result,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            IconButton(
              tooltip: strings.closeDialog,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
