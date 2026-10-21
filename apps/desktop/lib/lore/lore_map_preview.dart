// 资料地图预览：把 location 类资料以卡片布局呈现，关系连线由作者在当前会话中建立。
// 只读数据源、会话内状态：位置/连线/缩放不写库，也不新增或修改资料条目。

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// Session-only location layout, relations and zoom; never claims DB persistence.
///
/// 地点布局、关系连线与缩放都只存在于当前会话，不写库；本组件只读资料行。
class LoreMapPreview extends StatefulWidget {
  const LoreMapPreview({
    required this.rows,
    required this.positions,
    required this.links,
    required this.onOpen,
    super.key,
  });
  final List<Map<String, dynamic>> rows;
  final Map<String, Offset> positions;
  final Set<(String, String)> links;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  @override
  State<LoreMapPreview> createState() => _LoreMapPreviewState();
}

class _LoreMapPreviewState extends State<LoreMapPreview> {
  String? _selected;
  final _transform = TransformationController();
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _locations => widget.rows
      .where((r) => (r['entry'] as Map)['kind'] == 'location')
      .toList();
  String _id(Map<String, dynamic> row) => (row['entry'] as Map)['id'] as String;
  // 未拖动过的地点按五列网格给出初始位置，拖动后以会话内坐标为准。
  Offset _point(int index) =>
      widget.positions[_id(_locations[index])] ??
      Offset((index % 5) * 220.0, (index ~/ 5) * (_nodeHeight + 32));

  // 两行操作保留至少48px命中，大字号增加节点而不压缩按钮。
  double get _nodeHeight =>
      math.max(88.0, MediaQuery.textScalerOf(context).scale(13) * 3.2 + 24);

  // 画布不低于 1600，保证 InteractiveViewer 有足够的平移空间。
  double get _height =>
      (((_locations.length + 4) ~/ 5) * (_nodeHeight + 32) + _nodeHeight)
          .clamp(1600, double.infinity)
          .toDouble();
  void _move(int index, Offset delta) {
    // 拖拽限制在画布内，避免卡片被拖出可视范围后无法再选中。
    final next = _point(index) + delta;
    widget.positions[_id(_locations[index])] = Offset(
      next.dx.clamp(0, 2020),
      next.dy.clamp(0, _height - _nodeHeight),
    );
  }

  void _relate(String id) {
    setState(() {
      if (_selected == null) {
        _selected = id;
        return;
      }
      if (_selected != id) {
        // 无向关系以字典序归一化，避免 A-B 与 B-A 被记成两条连线。
        final pair = _selected!.compareTo(id) < 0
            ? (_selected!, id)
            : (id, _selected!);
        if (!widget.links.remove(pair)) widget.links.add(pair);
      }
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (_locations.isEmpty) return Center(child: Text(s.referenceEmpty));
    final centers = {
      for (var i = 0; i < _locations.length; i++)
        _id(_locations[i]): _point(i) + Offset(90, _nodeHeight / 2),
    };
    return Column(
      children: [
        Text(s.mapPreview),
        Text(s.mapRelationsHelp),
        Expanded(
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: .3,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(400),
              child: SizedBox(
                width: 2200,
                height: _height,
                child: CustomPaint(
                  painter: _RelationsPainter([
                    for (final pair in widget.links)
                      if (centers[pair.$1] != null && centers[pair.$2] != null)
                        (centers[pair.$1]!, centers[pair.$2]!),
                  ], Theme.of(context).colorScheme.outline),
                  child: Stack(
                    children: [
                      for (var i = 0; i < _locations.length; i++)
                        Positioned(
                          left: _point(i).dx,
                          top: _point(i).dy,
                          child: GestureDetector(
                            onScaleUpdate: (details) => setState(
                              () => _move(i, details.focalPointDelta),
                            ),
                            child: _LocationCard(
                              row: _locations[i],
                              height: _nodeHeight,
                              selected: _selected == _id(_locations[i]),
                              onOpen: () async =>
                                  await widget.onOpen(_locations[i]),
                              onRelate: () => _relate(_id(_locations[i])),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelationsPainter extends CustomPainter {
  const _RelationsPainter(this.lines, this.color);
  final List<(Offset, Offset)> lines;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final pair in lines) {
      canvas.drawLine(pair.$1, pair.$2, pen);
    }
  }

  @override
  bool shouldRepaint(_RelationsPainter old) =>
      old.color != color ||
      old.lines.length != lines.length ||
      List.generate(
        lines.length,
        (i) => i,
      ).any((i) => old.lines[i] != lines[i]);
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.row,
    required this.height,
    required this.selected,
    required this.onOpen,
    required this.onRelate,
  });
  final Map<String, dynamic> row;
  final double height;
  final bool selected;
  final Future<void> Function() onOpen;
  final VoidCallback onRelate;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    height: height,
    child: Card(
      child: Column(
        children: [
          Expanded(
            child: TextButton(
              onPressed: onOpen,
              child: Text((row['entry'] as Map)['name'] as String),
            ),
          ),
          Semantics(
            selected: selected,
            child: TextButton.icon(
              onPressed: onRelate,
              icon: Icon(selected ? Icons.check_circle : Icons.link),
              label: Text(AppLocalizations.of(context).mapRelation),
            ),
          ),
        ],
      ),
    ),
  );
}
