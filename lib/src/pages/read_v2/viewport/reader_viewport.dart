import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'zoomable_scroll_view.dart' show ZoomGuardScrollPhysics;

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

  /// Mirror of [ZoomableScrollView]'s pinch-detect threshold. When a trackpad
  /// pan-zoom event's cumulative scale drifts more than this from 1.0 we treat
  /// the gesture as a pinch and freeze the surrounding `PageView` (or any
  /// other [ZoomGuardScrollPhysics]-using Scrollable) so it stops eating the
  /// pan portion of [PointerPanZoomUpdateEvent] and wobbling the page.
  ///
  /// We do NOT apply zoom from these handlers — [InteractiveViewer]'s own
  /// [ScaleGestureRecognizer] wins the gesture arena in page modes and
  /// handles scaling natively. The Listener exists only to signal pinch state.
  static const double _pinchDetectThreshold = 0.001;

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

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if ((event.scale - 1.0).abs() > _pinchDetectThreshold) {
      ZoomGuardScrollPhysics.beginPinch();
    }
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    // Defer past the synchronous PageView drag-end handler so any residual
    // velocity is also suppressed — mirror of ZoomableScrollView's deferral.
    Future.microtask(ZoomGuardScrollPhysics.endPinch);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        panEnabled: true,
        scaleEnabled: true,
        onInteractionUpdate: widget.onInteractionUpdate,
        child: widget.child,
      ),
    );
  }
}
