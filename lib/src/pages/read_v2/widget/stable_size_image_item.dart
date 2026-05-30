import 'dart:async';

import 'package:flutter/material.dart';

import '../data/reader_image_source.dart';

/// Wraps a [child] (typically `ReaderImage`) in a [SizedBox] whose main-axis
/// extent is computed from the image's known aspect ratio. Used by continuous
/// scrolling strategies to keep list-item heights/widths stable while the
/// underlying bytes are still loading, so the viewport doesn't jump as items
/// resize.
///
/// Size resolution priority (highest first):
///   1. `source.peekImage(index)` width/height
///   2. `source.peekThumbnail(index)` thumb width/height (same aspect ratio)
///   3. Half the perpendicular viewport dimension (placeholder).
///
/// Rebuilds when either `imageReadyStream` or `thumbnailReadyStream` reports
/// the matching index.
class StableSizeImageItem extends StatefulWidget {
  const StableSizeImageItem({
    super.key,
    required this.source,
    required this.imageIndex,
    required this.axis,
    required this.child,
  });

  final ReaderImageSource source;
  final int imageIndex;
  final Axis axis;
  final Widget child;

  @override
  State<StableSizeImageItem> createState() => _StableSizeImageItemState();
}

class _StableSizeImageItemState extends State<StableSizeImageItem> {
  StreamSubscription<int>? _imageSub;
  StreamSubscription<int>? _thumbSub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant StableSizeImageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.imageIndex != widget.imageIndex) {
      _imageSub?.cancel();
      _thumbSub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _imageSub = widget.source.imageReadyStream.where((i) => i == widget.imageIndex).listen((_) {
      if (mounted) setState(() {});
    });
    _thumbSub = widget.source.thumbnailReadyStream.where((i) => i == widget.imageIndex).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _imageSub?.cancel();
    _thumbSub?.cancel();
    super.dispose();
  }

  /// Returns (width, height) of the original image if known via metadata,
  /// otherwise null.
  Size? _intrinsicSize() {
    final image = widget.source.peekImage(widget.imageIndex);
    if (image != null && image.width != null && image.height != null && image.width! > 0 && image.height! > 0) {
      return Size(image.width!, image.height!);
    }
    final thumb = widget.source.peekThumbnail(widget.imageIndex);
    if (thumb != null && thumb.thumbWidth != null && thumb.thumbHeight != null && thumb.thumbWidth! > 0 && thumb.thumbHeight! > 0) {
      return Size(thumb.thumbWidth!, thumb.thumbHeight!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final intrinsic = _intrinsicSize();
        final media = MediaQuery.of(context).size;

        if (widget.axis == Axis.vertical) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : media.width;
          final double height;
          if (intrinsic != null) {
            final fitted = applyBoxFit(BoxFit.contain, intrinsic, Size(width, double.infinity));
            height = fitted.destination.height;
          } else {
            height = media.height * 0.5;
          }
          return SizedBox(width: width, height: height, child: widget.child);
        } else {
          final height = constraints.maxHeight.isFinite ? constraints.maxHeight : media.height;
          final double width;
          if (intrinsic != null) {
            final fitted = applyBoxFit(BoxFit.contain, intrinsic, Size(double.infinity, height));
            width = fitted.destination.width;
          } else {
            width = media.width * 0.5;
          }
          return SizedBox(width: width, height: height, child: widget.child);
        }
      },
    );
  }
}
