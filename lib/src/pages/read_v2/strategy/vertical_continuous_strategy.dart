import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../viewport/zoomable_scroll_view.dart';
import 'reading_strategy.dart';

class VerticalContinuousStrategy extends StatefulWidget {
  const VerticalContinuousStrategy({super.key, required this.ctx});

  final ReadingStrategyContext ctx;

  @override
  State<VerticalContinuousStrategy> createState() => VerticalContinuousStrategyState();
}

class VerticalContinuousStrategyState extends ReadingStrategyState<VerticalContinuousStrategy> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();
  final ScrollOffsetController _offsetController = ScrollOffsetController();

  late int _currentGroup = widget.ctx.initialGroup;

  @override
  void initState() {
    super.initState();
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  void _onPositionsChanged() {
    final positions = _positionsListener.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList();
    if (positions.isEmpty) return;
    positions.sort((a, b) => a.index - b.index);
    final visible = positions.first.index;
    if (visible != _currentGroup) {
      _currentGroup = visible;
      widget.ctx.onGroupChanged(visible);
    }
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }

  @override
  void advance() {
    _offsetController.animateScroll(
      offset: MediaQuery.of(context).size.height * 0.9,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void retreat() {
    _offsetController.animateScroll(
      offset: -MediaQuery.of(context).size.height * 0.9,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void jumpToGroup(int group) {
    if (!_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index: group,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ZoomableScrollView(
      minScale: ctx.minScale,
      maxScale: ctx.maxScale,
      child: ScrollablePositionedList.separated(
        scrollDirection: Axis.vertical,
        itemCount: ctx.groups.length,
        initialScrollIndex: ctx.initialGroup,
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        scrollOffsetController: _offsetController,
        itemBuilder: (_, groupIndex) => ctx.imageBuilder(ctx.groups[groupIndex].first),
        separatorBuilder: (_, __) => SizedBox(height: ctx.imageSpace.toDouble()),
      ),
    );
  }
}
