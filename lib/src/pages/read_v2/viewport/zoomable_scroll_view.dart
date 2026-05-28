import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
class ZoomableScrollView extends StatefulWidget {
  const ZoomableScrollView({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.onScaleChanged,
  });

  final Widget child;
  final double minScale;
  final double maxScale;

  final void Function(double scale)? onScaleChanged;

  @override
  State<ZoomableScrollView> createState() => _ZoomableScrollViewState();
}

class _ZoomableScrollViewState extends State<ZoomableScrollView> {
  late final TransformationController _controller = TransformationController();

  bool _zoomed = false;

  /// Scale captured at [PointerPanZoomStartEvent] so updates can be applied
  /// relative to it (`event.scale` on update is cumulative from start).
  double? _panZoomBaseScale;

  static const double _zoomedThreshold = 1.01;
  static const double _wheelScaleStep = 0.15;

  /// Below this delta from 1.0 we treat a pan-zoom event as a pure pan and
  /// let the inner scrollable handle it as a scroll. Keeps plain trackpad
  /// scrolling working in continuous modes.
  static const double _panZoomScaleEpsilon = 0.005;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  void _onTransform() {
    final scale = _controller.value.getMaxScaleOnAxis();
    widget.onScaleChanged?.call(scale);
    final zoomed = scale > _zoomedThreshold;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
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
      _zoomBy(-(claimed as PointerScrollEvent).scrollDelta.dy.sign * _wheelScaleStep, claimed.localPosition);
    });
  }

  /// Trackpad pinch start — remember the scale we were at so
  /// [_onPointerPanZoomUpdate] can apply `event.scale` (which is cumulative
  /// from gesture start) on top of it.
  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomBaseScale = _controller.value.getMaxScaleOnAxis();
  }

  /// Trackpad pinch update. Pure pans (scale ≈ 1.0) are ignored so the
  /// inner scrollable handles them as native scroll; meaningful scale
  /// changes apply directly to the [TransformationController] around the
  /// focal point. The inner scrollable may also process the pan portion
  /// of this event as a drag — see the plan's "Known limitation".
  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final base = _panZoomBaseScale;
    if (base == null) return;
    if ((event.scale - 1.0).abs() < _panZoomScaleEpsilon) return;

    final target = (base * event.scale).clamp(widget.minScale, widget.maxScale);
    final current = _controller.value.getMaxScaleOnAxis();
    if (current == 0) return;
    final factor = target / current;
    if (factor == 1.0) return;

    final focal = event.localPosition;
    _controller.value = _controller.value.clone()
      ..translate(focal.dx, focal.dy)
      ..scale(factor, factor)
      ..translate(-focal.dx, -focal.dy);
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomBaseScale = null;
  }

  void _zoomBy(double delta, Offset focal) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current + delta).clamp(widget.minScale, widget.maxScale);
    final factor = target / current;
    final matrix = _controller.value.clone()
      ..translate(focal.dx, focal.dy)
      ..scale(factor, factor)
      ..translate(-focal.dx, -focal.dy);
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        panEnabled: _zoomed,
        scaleEnabled: true,
        child: widget.child,
      ),
    );
  }
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

  @override
  ZoomGuardScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ZoomGuardScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (HardwareKeyboard.instance.isControlPressed) return false;
    return super.shouldAcceptUserOffset(position);
  }
}
