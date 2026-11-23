import 'package:flutter/widgets.dart';

import '../slicing/page_group.dart';
import '../slicing/reading_mode.dart';
import '../viewport/reader_viewport.dart';
import '../viewport/zoomable_scroll_view.dart' show ZoomGuardScrollPhysics;
import 'reading_strategy.dart';

class DoublePageStrategy extends StatefulWidget {
  const DoublePageStrategy({super.key, required this.ctx});

  final ReadingStrategyContext ctx;

  @override
  State<DoublePageStrategy> createState() => DoublePageStrategyState();
}

class DoublePageStrategyState extends ReadingStrategyState<DoublePageStrategy> {
  late final PageController _controller = PageController(initialPage: widget.ctx.initialGroup);

  bool get _isRtl => widget.ctx.mode == ReadingModeV2.doublePageRTL;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPage);
  }

  void _onPage() {
    final page = _controller.page;
    if (page == null) return;
    final rounded = page.round();
    if (rounded == widget.ctx.initialGroup) return;
    widget.ctx.onGroupChanged(rounded);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPage);
    _controller.dispose();
    super.dispose();
  }

  @override
  void advance() {
    if (!_controller.hasClients) return;
    if (widget.ctx.enablePageAnime) {
      _controller.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.ease);
    } else {
      _controller.jumpToPage((_controller.page ?? 0).round() + 1);
    }
  }

  @override
  void retreat() {
    if (!_controller.hasClients) return;
    if (widget.ctx.enablePageAnime) {
      _controller.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.ease);
    } else {
      _controller.jumpToPage((_controller.page ?? 0).round() - 1);
    }
  }

  @override
  void jumpToGroup(int group) {
    if (!_controller.hasClients) return;
    if (widget.ctx.enablePageAnime) {
      _controller.animateToPage(group, duration: const Duration(milliseconds: 200), curve: Curves.ease);
    } else {
      _controller.jumpToPage(group);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return PageView.builder(
      controller: _controller,
      physics: const ZoomGuardScrollPhysics(),
      reverse: _isRtl,
      itemCount: ctx.groups.length,
      onPageChanged: ctx.onGroupChanged,
      itemBuilder: (_, groupIndex) {
        final PageGroup group = ctx.groups[groupIndex];
        // ReaderViewport wraps the *pair* so pinch/pan operates on the spread.
        return ReaderViewport(
          minScale: ctx.minScale,
          maxScale: ctx.maxScale,
          resetKey: groupIndex,
          child: _SpreadRow(
            group: group,
            isRtl: _isRtl,
            imageBuilder: ctx.imageBuilder,
            imageSpace: ctx.imageSpace,
          ),
        );
      },
    );
  }
}

class _SpreadRow extends StatelessWidget {
  const _SpreadRow({
    required this.group,
    required this.isRtl,
    required this.imageBuilder,
    required this.imageSpace,
  });

  final PageGroup group;
  final bool isRtl;
  final Widget Function(int imageIndex) imageBuilder;
  final int imageSpace;

  @override
  Widget build(BuildContext context) {
    if (group.indices.length == 1) {
      return Center(child: imageBuilder(group.first));
    }
    // Indices are stored chronologically. The PageView's `reverse` flag only
    // reverses the order of groups, not the layout inside a spread, so for RTL
    // the earlier page must be placed on the right explicitly.
    final int leftIndex = isRtl ? group.indices[1] : group.indices[0];
    final int rightIndex = isRtl ? group.indices[0] : group.indices[1];
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: imageBuilder(leftIndex)),
        SizedBox(width: imageSpace.toDouble()),
        Expanded(child: imageBuilder(rightIndex)),
      ],
    );
  }
}
