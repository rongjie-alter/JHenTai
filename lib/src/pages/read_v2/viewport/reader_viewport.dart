import 'package:flutter/material.dart';

import 'pinch_zoom.dart';

/// Full pan + zoom viewport used by page-based modes (single, double).
///
/// One [ReaderViewport] wraps each visible PageView page. Pinch zooms; once
/// zoomed, drag pans. Zoom resets to identity when [resetKey] changes
/// (typically when the page changes). Gesture handling lives in
/// [PinchZoomViewportMixin], shared with [ZoomableScrollView].
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

class _ReaderViewportState extends State<ReaderViewport> with PinchZoomViewportMixin<ReaderViewport> {
  @override
  double get minScale => widget.minScale;

  @override
  double get maxScale => widget.maxScale;

  @override
  void didUpdateWidget(covariant ReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      transformationController.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildPinchZoomViewport(
      onInteractionUpdate: widget.onInteractionUpdate,
      child: widget.child,
    );
  }
}
