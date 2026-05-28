import 'package:flutter/material.dart';

/// Full pan + zoom viewport used by page-based modes (single, double).
///
/// One [ReaderViewport] wraps each visible PageView page. Pinch/Ctrl+wheel
/// zooms; once zoomed, drag pans. Zoom resets to identity when [resetKey]
/// changes (typically when the page changes).
class ReaderViewport extends StatefulWidget {
  const ReaderViewport({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.resetKey,
    this.onInteractionUpdate,
  });

  final Widget child;
  final double minScale;
  final double maxScale;

  /// Changing this triggers a transformation reset (back to scale=1, no pan).
  final Object? resetKey;

  final void Function(ScaleUpdateDetails)? onInteractionUpdate;

  @override
  State<ReaderViewport> createState() => _ReaderViewportState();
}

class _ReaderViewportState extends State<ReaderViewport> {
  late final TransformationController _controller = TransformationController();

  @override
  void didUpdateWidget(covariant ReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      panEnabled: true,
      scaleEnabled: true,
      onInteractionUpdate: widget.onInteractionUpdate,
      child: widget.child,
    );
  }
}
