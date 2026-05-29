import 'package:flutter/widgets.dart';

import '../viewport/reader_viewport.dart';
import '../viewport/zoomable_scroll_view.dart' show ZoomGuardScrollPhysics;
import 'reading_strategy.dart';

class SinglePageStrategy extends StatefulWidget {
  const SinglePageStrategy({super.key, required this.ctx});

  final ReadingStrategyContext ctx;

  @override
  State<SinglePageStrategy> createState() => SinglePageStrategyState();
}

class SinglePageStrategyState extends ReadingStrategyState<SinglePageStrategy> {
  late final PageController _controller = PageController(initialPage: widget.ctx.initialGroup);

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
      itemCount: ctx.groups.length,
      onPageChanged: ctx.onGroupChanged,
      itemBuilder: (_, groupIndex) {
        final imageIndex = ctx.groups[groupIndex].first;
        return ReaderViewport(
          minScale: ctx.minScale,
          maxScale: ctx.maxScale,
          resetKey: imageIndex,
          child: ctx.imageBuilder(imageIndex),
        );
      },
    );
  }
}
