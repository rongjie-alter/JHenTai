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

  static const double _zoomedThreshold = 1.01;
  static const double _wheelScaleStep = 0.15;

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
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent claimed) {
      _zoomBy(-(claimed as PointerScrollEvent).scrollDelta.dy.sign * _wheelScaleStep, claimed.localPosition);
    });
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
