import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared pinch/pan-zoom machinery for the v2 reader viewports
/// ([ReaderViewport] for page modes, [ZoomableScrollView] for continuous
/// modes). Both wrap an [InteractiveViewer] in an outer [Listener] that drives
/// trackpad pinches itself; the per-viewport differences are exposed as hooks:
///
/// * [zoomApplyThreshold] — continuous modes ignore near-1.0 scale updates so a
///   pure two-finger pan scrolls instead of zooming.
/// * [onTrackpadPan] — called with the pan delta of non-pinch pan-zoom updates
///   while zoomed (continuous modes apply the cross-axis component).
/// * [onScaleChanged] — called on every transform change.
mixin PinchZoomViewportMixin<T extends StatefulWidget> on State<T> {
  late final TransformationController transformationController = TransformationController();

  double get minScale;

  double get maxScale;

  /// Below this delta from 1.0 a pan-zoom update does not change the scale.
  /// Zero means every scale change is applied.
  double get zoomApplyThreshold => 0.0;

  /// Pan delta of a pan-zoom update that has not (yet) been recognised as a
  /// pinch, delivered only while [zoomed].
  void onTrackpadPan(Offset localPanDelta) {}

  void onScaleChanged(double scale) {}

  /// Tight threshold for detecting that a trackpad gesture is a pinch (not a
  /// pure pan). Crossing it flips [ZoomGuardScrollPhysics] into pinch mode so
  /// the surrounding scrollable stops applying drag deltas from the pan
  /// portion of pan-zoom events — kills the scroll wobble during a pinch.
  static const double _pinchDetectThreshold = 0.001;

  /// Scale above which the child counts as "zoomed in" and
  /// [InteractiveViewer.panEnabled] is unlocked for drag-to-pan.
  static const double _zoomedThreshold = 1.01;

  bool _zoomed = false;

  bool get zoomed => _zoomed;

  /// True while a trackpad pan-zoom gesture is in flight. Used to fully
  /// disengage [InteractiveViewer] (`panEnabled: false`, `scaleEnabled: false`)
  /// for the duration of the gesture — otherwise its pan path applies
  /// translation from the pan portion of pan-zoom events while we're driving
  /// the scale ourselves (the pinch wobble).
  bool _trackpadPinching = false;

  /// Scale captured at [PointerPanZoomStartEvent]; `event.scale` on update is
  /// cumulative from gesture start, so the target is `base * event.scale`.
  double? _panZoomBaseScale;

  /// Focal point captured at [PointerPanZoomStartEvent] and reused for every
  /// update, so finger-centroid drift during a pinch (Windows precision
  /// touchpads in particular) doesn't accumulate into the translation.
  Offset? _lockedFocal;

  /// True once the current trackpad gesture has been recognised as a pinch.
  bool _panZoomIsPinch = false;

  @override
  void initState() {
    super.initState();
    transformationController.addListener(_onTransform);
  }

  @override
  void dispose() {
    // If this viewport is torn down mid-pinch (e.g. the reader is closed), the
    // pan-zoom end event may never reach us. Release the static guard so other
    // scrollables (including future reader sessions) are not left frozen.
    if (_trackpadPinching) {
      ZoomGuardScrollPhysics.endPinch();
    }
    transformationController.removeListener(_onTransform);
    transformationController.dispose();
    super.dispose();
  }

  void _onTransform() {
    final scale = transformationController.value.getMaxScaleOnAxis();
    onScaleChanged(scale);
    final zoomed = scale > _zoomedThreshold;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomBaseScale = transformationController.value.getMaxScaleOnAxis();
    _lockedFocal = event.localPosition;
    _panZoomIsPinch = false;
    setState(() => _trackpadPinching = true);
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final base = _panZoomBaseScale;
    final focal = _lockedFocal;
    if (base == null || focal == null) return;

    // Mark the pinch as early as possible so the guarded scrollable stops
    // applying pan deltas — done before the zoom-apply early-return so pinches
    // that haven't crossed that threshold yet still suppress scroll.
    if ((event.scale - 1.0).abs() > _pinchDetectThreshold) {
      _panZoomIsPinch = true;
      ZoomGuardScrollPhysics.beginPinch();
    }

    if (_zoomed && !_panZoomIsPinch) {
      onTrackpadPan(event.localPanDelta);
    }

    if ((event.scale - 1.0).abs() < zoomApplyThreshold) return;

    // Idempotent target-based scale: the matrix ends up at `base * scale`
    // clamped to bounds regardless of how many events were processed.
    zoomTo(base * event.scale, focal);
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomBaseScale = null;
    _lockedFocal = null;
    _panZoomIsPinch = false;
    // Defer clearing past this event-dispatch cycle so the guarded scrollable's
    // synchronous drag-end handler still sees the pinch and any residual fling
    // is suppressed. Scheduled before setState: the event can arrive after this
    // State is disposed, and setState would then throw before endPinch ran.
    Future.microtask(ZoomGuardScrollPhysics.endPinch);
    if (mounted) {
      setState(() => _trackpadPinching = false);
    } else {
      _trackpadPinching = false;
    }
  }

  /// Zoom to [targetScale] (clamped to [minScale]..[maxScale]) around [focal],
  /// a point in viewport coordinates.
  void zoomTo(double targetScale, Offset focal) {
    final target = targetScale.clamp(minScale, maxScale);
    final current = transformationController.value.getMaxScaleOnAxis();
    if (current == 0) return;
    final factor = target / current;
    if (factor == 1.0) return;

    final matrix = zoomAroundViewportPoint(transformationController.value, focal, factor);
    clampTranslation(matrix);
    transformationController.value = matrix;
  }

  /// Clamp the translation column of [matrix] so a viewport-sized child
  /// scaled by `matrix.getMaxScaleOnAxis()` never exposes empty space beyond
  /// its edges. Mirrors [InteractiveViewer]'s default
  /// `boundaryMargin: EdgeInsets.zero` behaviour for the matrix writes we
  /// drive directly (which bypass IV's own `_clampMatrix`).
  ///
  /// The bound is **asymmetric**: tx ∈ [-(s-1)·w, 0], ty ∈ [-(s-1)·h, 0].
  /// The child's content origin (0,0) is at the top-left (not the centre),
  /// so a viewport `(0,0)–(w,h)` mapped back to scene coords by `M⁻¹` fits
  /// inside the child's bounds exactly when translation lies in this range.
  /// Cursor-anchored zoom at focal `f ∈ [0,w] × [0,h]` produces
  /// `t = (1-s)·f`, which is always in range — no clamping, the cursor stays
  /// anchored. Clamping only intervenes when the user actually drifts (zoom
  /// in at A, move cursor, zoom out at B).
  ///
  /// A symmetric bound (`±(s-1)·w/2`) would mis-handle right/bottom-half
  /// focals: cursor-anchored zoom there exceeds the symmetric bound and gets
  /// truncated, shifting the image during the zoom.
  void clampTranslation(Matrix4 matrix) {
    final size = context.size;
    if (size == null) return;
    final scale = matrix.getMaxScaleOnAxis();
    final maxNegTx = math.max(0.0, (scale - 1.0) * size.width);
    final maxNegTy = math.max(0.0, (scale - 1.0) * size.height);
    final t = matrix.getTranslation();
    matrix.setTranslationRaw(
      t.x.clamp(-maxNegTx, 0.0),
      t.y.clamp(-maxNegTy, 0.0),
      0.0,
    );
  }

  Widget buildPinchZoomViewport({
    required Widget child,
    void Function(PointerSignalEvent event)? onPointerSignal,
    GestureScaleUpdateCallback? onInteractionUpdate,
  }) {
    return Listener(
      onPointerSignal: onPointerSignal,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: InteractiveViewer(
        transformationController: transformationController,
        minScale: minScale,
        maxScale: maxScale,
        // Disengage InteractiveViewer entirely during a trackpad pinch — we
        // drive the matrix from the outer Listener with a locked focal point.
        // Leaving its scale path active causes a per-frame fight with our
        // Listener writes (the residual wobble); leaving its pan path active
        // makes the pan portion of pan-zoom events shift the image. Touch
        // pinch (multi-touch) still uses scaleEnabled — pan-zoom events come
        // only from trackpad/touchpad, so `_trackpadPinching` is never true
        // for touch.
        panEnabled: _zoomed && !_trackpadPinching,
        scaleEnabled: !_trackpadPinching,
        onInteractionUpdate: onInteractionUpdate,
        child: child,
      ),
    );
  }
}

/// Returns [matrix] scaled by [factor] around [focal], where [focal] is a
/// point in **viewport** coordinates (e.g. the cursor / pinch position from
/// a [Listener] outside the [InteractiveViewer]).
///
/// The zoom is pre-multiplied: `T(f)·S(k)·T(-f)·M`. Post-multiplying
/// (`M·T(f)·S(k)·T(-f)`, i.e. `matrix..translate()..scale()..translate()`)
/// would instead scale around the *scene* point `f`, which only coincides
/// with the viewport point when `M` is identity — so every zoom that starts
/// from an already-zoomed state would drift away from the cursor.
Matrix4 zoomAroundViewportPoint(Matrix4 matrix, Offset focal, double factor) {
  return Matrix4.translationValues(focal.dx * (1 - factor), focal.dy * (1 - factor), 0)
    ..multiply(Matrix4.diagonal3Values(factor, factor, 1))
    ..multiply(matrix);
}

/// [ScrollPhysics] that surrenders user offset (and therefore the
/// [PointerSignalResolver] race) when Ctrl is held.
///
/// Flutter's `Scrollable._receivedPointerSignal` calls
/// `physics.shouldAcceptUserOffset(position)` *before* registering with
/// the resolver — returning `false` makes the scrollable bail out without
/// registering, so an outer [Listener] (e.g. inside [ZoomableScrollView])
/// can claim Ctrl+wheel events for zoom.
///
/// Plain wheel scrolling (Ctrl not held) is unaffected: physics defers to
/// the parent.
class ZoomGuardScrollPhysics extends ScrollPhysics {
  const ZoomGuardScrollPhysics({super.parent});

  /// Set by [PinchZoomViewportMixin] while a trackpad pinch is in flight. The
  /// inner Scrollable's drag recognizer still accepts the pan portion of the
  /// `PointerPanZoomUpdate` events, but with this flag set its pan delta is
  /// neutralized in [applyPhysicsToUserOffset] and any residual fling is
  /// suppressed in [createBallisticSimulation] — so the list visibly holds
  /// position during the pinch instead of wobbling.
  ///
  /// One reader is mounted at a time so this static is fine; same precedent
  /// as the [HardwareKeyboard.instance.isControlPressed] check below.
  static bool _pinching = false;
  static void beginPinch() => _pinching = true;
  static void endPinch() => _pinching = false;

  @override
  ZoomGuardScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ZoomGuardScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (HardwareKeyboard.instance.isControlPressed) return false;
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (_pinching) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (_pinching) return null;
    return super.createBallisticSimulation(position, velocity);
  }
}
