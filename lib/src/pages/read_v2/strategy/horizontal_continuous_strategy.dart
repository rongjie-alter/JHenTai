import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../slicing/reading_mode.dart';
import '../viewport/zoomable_scroll_view.dart';
import 'reading_strategy.dart';

class HorizontalContinuousStrategy extends StatefulWidget {
  const HorizontalContinuousStrategy({super.key, required this.ctx});

  final ReadingStrategyContext ctx;

  @override
  State<HorizontalContinuousStrategy> createState() => HorizontalContinuousStrategyState();
}

class HorizontalContinuousStrategyState extends ReadingStrategyState<HorizontalContinuousStrategy> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();
  final ScrollOffsetController _offsetController = ScrollOffsetController();

  late int _currentGroup = widget.ctx.initialGroup;

  bool get _isRtl => widget.ctx.mode == ReadingModeV2.horizontalContinuousRTL;

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
    final dx = MediaQuery.of(context).size.width * 0.9;
    _offsetController.animateScroll(
      offset: _isRtl ? -dx : dx,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void retreat() {
    final dx = MediaQuery.of(context).size.width * 0.9;
    _offsetController.animateScroll(
      offset: _isRtl ? dx : -dx,
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
        scrollDirection: Axis.horizontal,
        reverse: _isRtl,
        physics: const ZoomGuardScrollPhysics(),
        itemCount: ctx.groups.length,
        initialScrollIndex: ctx.initialGroup,
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        scrollOffsetController: _offsetController,
        itemBuilder: (_, groupIndex) => ctx.imageBuilder(ctx.groups[groupIndex].first),
        separatorBuilder: (_, __) => SizedBox(width: ctx.imageSpace.toDouble()),
      ),
    );
  }
}
