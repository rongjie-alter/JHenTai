import 'dart:math' as math;

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

  /// Tight threshold for detecting a trackpad pinch. Crossing this flips
  /// [ZoomGuardScrollPhysics] into pinch mode so the surrounding [PageView]
  /// stops applying drag deltas from the pan portion of pan-zoom events.
  static const double _pinchDetectThreshold = 0.001;

  /// Scale above which we treat the image as "zoomed in" and unlock
  /// [InteractiveViewer.panEnabled] for single-finger drag-to-pan.
  static const double _zoomedThreshold = 1.01;

  bool _zoomed = false;

  /// True while a trackpad pan-zoom gesture is in flight. Used to fully
  /// disengage [InteractiveViewer] (`panEnabled: false`) for the duration of
  /// the pinch — without this its pan path applies translation from the pan
  /// portion of pan-zoom events even while we're driving the scale ourselves,
  /// which is the residual page-mode wobble.
  bool _trackpadPinching = false;

  /// Captured at [PointerPanZoomStartEvent] and reused for every update in
  /// the gesture. Using a fixed focal point (instead of each event's current
  /// `localPosition`) keeps the image rock-steady when finger centroid drifts
  /// a few pixels during a pinch — Windows precision touchpads in particular.
  double? _trackpadBaseScale;
  Offset? _trackpadLockedFocal;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(covariant ReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final zoomed = scale > _zoomedThreshold;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadBaseScale = _controller.value.getMaxScaleOnAxis();
    _trackpadLockedFocal = event.localPosition;
    setState(() => _trackpadPinching = true);
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final base = _trackpadBaseScale;
    final focal = _trackpadLockedFocal;
    if (base == null || focal == null) {
      return;
    }

    if ((event.scale - 1.0).abs() > _pinchDetectThreshold) {
      ZoomGuardScrollPhysics.beginPinch();
    }

    // Idempotent target-based scale: regardless of how many events we've
    // processed, the matrix ends up at `base * event.scale` clamped to
    // bounds. No accumulation drift.
    final target = (base * event.scale).clamp(widget.minScale, widget.maxScale);
    final current = _controller.value.getMaxScaleOnAxis();
    if (current == 0) {
      return;
    }
    final factor = target / current;
    if (factor == 1.0) {
      return;
    }

    final matrix = _controller.value.clone()
      ..translate(focal.dx, focal.dy)
      ..scale(factor, factor)
      ..translate(-focal.dx, -focal.dy);
    _clampTranslation(matrix);
    _controller.value = matrix;
  }

  /// Clamp the translation column of [matrix] so a viewport-sized child
  /// scaled by `matrix.getMaxScaleOnAxis()` never exposes empty space
  /// beyond its edges. Mirrors [InteractiveViewer]'s default
  /// `boundaryMargin: EdgeInsets.zero` clamp for matrix writes we drive
  /// directly from the outer [Listener] (which bypass IV's `_clampMatrix`).
  void _clampTranslation(Matrix4 matrix) {
    final size = context.size;
    if (size == null) return;
    final scale = matrix.getMaxScaleOnAxis();
    final maxTx = math.max(0.0, (scale - 1.0) * size.width / 2);
    final maxTy = math.max(0.0, (scale - 1.0) * size.height / 2);
    final t = matrix.getTranslation();
    matrix.setTranslationRaw(
      t.x.clamp(-maxTx, maxTx),
      t.y.clamp(-maxTy, maxTy),
      0.0,
    );
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadBaseScale = null;
    _trackpadLockedFocal = null;
    setState(() => _trackpadPinching = false);
    // Defer past the synchronous PageView drag-end handler so any residual
    // velocity is also suppressed — mirror of ZoomableScrollView's deferral.
    Future.microtask(ZoomGuardScrollPhysics.endPinch);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        // Disengage InteractiveViewer entirely during a trackpad pinch — we
        // drive the matrix from the outer Listener with a locked focal point.
        // Leaving its scale path active causes a per-frame fight with our
        // Listener writes (the residual wobble); leaving its pan path active
        // makes the pan portion of pan-zoom events shift the image.
        // Touch pinch (Android, multi-touch) still uses scaleEnabled — pan-zoom
        // events come only from trackpad/touchpad, so `_trackpadPinching` is
        // never true for touch.
        panEnabled: _zoomed && !_trackpadPinching,
        scaleEnabled: !_trackpadPinching,
        onInteractionUpdate: widget.onInteractionUpdate,
        child: widget.child,
      ),
    );
  }
}
