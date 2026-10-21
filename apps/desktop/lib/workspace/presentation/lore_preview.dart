// R09 资料查阅、带入讨论与完整编辑分离的支持层。
// 预览卡只读展示当前 head 与历史请求提交时的引用快照，不写库、不发模型请求；
// 只有作者明确点击“带入讨论”才把条目 ID 写入绑定的当前讨论引用集合。

import 'package:flutter/material.dart';

import 'lore_preview_data.dart';
import 'lore_preview_sections.dart';

export 'lore_discussion_target.dart';
export 'lore_preview_data.dart';

/// 轻量只读资料预览：宽窗靠右临时卡、窄窗面板，复用同一份内容。
///
/// 预览本身不改变讨论引用、不增加模型上下文；[onAttach] 与 [onRemove]
/// 返回 true 时才更新按钮状态。历史快照区展示提交时的名称与正文，
/// “查看当前资料”只滚动到当前内容，不会用最新内容覆盖历史。
class LorePreview extends StatefulWidget {
  const LorePreview({
    required this.data,
    this.history = const [],
    this.attached = false,
    this.onAttach,
    this.onRemove,
    this.onEdit,
    required this.onClose,
    super.key,
  });

  final LorePreviewData data;
  final List<LoreRequestSnapshot> history;
  final bool attached;
  final bool Function()? onAttach;
  final bool Function()? onRemove;
  final VoidCallback? onEdit;
  final VoidCallback onClose;

  @override
  State<LorePreview> createState() => _LorePreviewState();
}

class _LorePreviewState extends State<LorePreview> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  late bool _attached = widget.attached;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    return Dialog(
      key: const ValueKey('lore-preview-card'),
      alignment: wide ? AlignmentDirectional.centerEnd : Alignment.center,
      insetPadding: EdgeInsets.all(wide ? 24 : 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 400 : 520,
          maxHeight: size.height * (wide ? 0.72 : 0.86),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LorePreviewHeader(data: widget.data, onClose: widget.onClose),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: LorePreviewBody(
                    data: widget.data,
                    history: widget.history,
                    currentKey: _currentKey,
                    onViewCurrent: _scrollToCurrent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              LorePreviewActions(
                attached: _attached,
                onEdit: widget.onEdit,
                onAttach: widget.onAttach == null ? null : _attach,
                onRemove: widget.onRemove == null ? null : _remove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _attach() {
    final onAttach = widget.onAttach;
    if (onAttach == null || !onAttach()) return;
    setState(() => _attached = true);
  }

  void _remove() {
    final onRemove = widget.onRemove;
    if (onRemove == null || !onRemove()) return;
    setState(() => _attached = false);
  }

  Future<void> _scrollToCurrent() async {
    final target = _currentKey.currentContext;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    try {
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: duration,
          curve: Curves.easeOut,
        );
      } else if (_scroll.hasClients) {
        if (duration == Duration.zero) {
          _scroll.jumpTo(0);
        } else {
          await _scroll.animateTo(0, duration: duration, curve: Curves.easeOut);
        }
      }
    } catch (error) {
      // 资料路由退出可能终止滚动；仅记录类型，不泄漏作者资料或路径。
      debugPrint('lore_preview_scroll_failed: ${error.runtimeType}');
    }
  }
}
