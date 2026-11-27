import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pinch_zoom.dart';

export 'pinch_zoom.dart' show ZoomGuardScrollPhysics, zoomAroundViewportPoint;

/// Wraps a scrollable [child] (typically a [ScrollablePositionedList] or
/// [ListView]) and adds pinch-to-zoom on top.
///
/// At scale = 1 the inner scrollable handles all drag/wheel/trackpad
/// gestures normally (native infinite scroll). Pinch (touch / trackpad) or
/// Ctrl+wheel (desktop mouse) zooms in; once zoomed, drag-to-pan engages
/// and the inner scrollable is frozen until the user zooms back out.
///
/// Why this dance: a naive [InteractiveViewer] around a [ListView] eats the
/// drag arena and the list can never scroll. Binding `panEnabled` to scale
/// keeps native scroll behaviour at the default zoom level.
///
/// For the inner scrollable to surrender Ctrl+wheel events (so the outer
/// [Listener] here can claim them via [PointerSignalResolver]), pass
/// [ZoomGuardScrollPhysics] as the scrollable's physics — see that class.
///
/// Pinch handling lives in [PinchZoomViewportMixin], shared with
/// [ReaderViewport].
class ZoomableScrollView extends StatefulWidget {
  const ZoomableScrollView({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.onScaleChanged,
  });

  final Widget child;

  /// Scroll axis of the inner scrollable [child]. The inner scrollable only
  /// consumes trackpad pan along this axis; the cross-axis component is
  /// applied to the zoom matrix here (see [_ZoomableScrollViewState.onTrackpadPan]).
  final Axis scrollDirection;
  final double minScale;
  final double maxScale;

  final void Function(double scale)? onScaleChanged;

  @override
  State<ZoomableScrollView> createState() => _ZoomableScrollViewState();
}

class _ZoomableScrollViewState extends State<ZoomableScrollView> with PinchZoomViewportMixin<ZoomableScrollView> {
  static const double _wheelScaleStep = 0.15;

  @override
  double get minScale => widget.minScale;

  @override
  double get maxScale => widget.maxScale;

  /// Pure two-finger pan must scroll, not zoom: ignore pan-zoom updates whose
  /// scale is this close to 1.0 and let the inner scrollable handle them. Kept
  /// looser than the pinch-detect threshold to avoid jittery scaling.
  @override
  double get zoomApplyThreshold => 0.005;

  @override
  void onScaleChanged(double scale) => widget.onScaleChanged?.call(scale);

  /// Two-finger pan while zoomed. The inner scrollable only reacts to the
  /// main-axis component of the pan, and InteractiveViewer's pan path is
  /// disabled for the whole pan-zoom gesture — so without this, the cross-axis
  /// component reaches nobody. Apply it to the matrix translation ourselves.
  @override
  void onTrackpadPan(Offset localPanDelta) {
    final d = widget.scrollDirection == Axis.vertical ? localPanDelta.dx : localPanDelta.dy;
    if (d == 0) return;
    final matrix = transformationController.value.clone();
    final t = matrix.getTranslation();
    if (widget.scrollDirection == Axis.vertical) {
      matrix.setTranslationRaw(t.x + d, t.y, t.z);
    } else {
      matrix.setTranslationRaw(t.x, t.y + d, t.z);
    }
    clampTranslation(matrix);
    transformationController.value = matrix;
  }

  /// Ctrl+wheel zoom. We register with the [PointerSignalResolver] so the
  /// event is claimed at this level and the inner scrollable never sees it.
  ///
  /// The inner scrollable would normally register first (hit-test is
  /// leaf-to-root and only the first registrant wins), but
  /// [ZoomGuardScrollPhysics] makes it return false from
  /// `shouldAcceptUserOffset` while Ctrl is pressed, so it bails out
  /// before registering and our claim here wins.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent claimed) {
      final delta = -(claimed as PointerScrollEvent).scrollDelta.dy.sign * _wheelScaleStep;
      zoomTo(transformationController.value.getMaxScaleOnAxis() + delta, claimed.localPosition);
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildPinchZoomViewport(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
