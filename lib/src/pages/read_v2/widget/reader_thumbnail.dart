import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/widget/eh_thumbnail.dart';

import '../data/local_image_source.dart';
import '../data/reader_image_source.dart';

/// Thumbnail cell for the bottom thumbnail strip. For online sources, lazily
/// requests the thumbnail batch. For local sources, renders the on-disk file.
class ReaderThumbnail extends StatefulWidget {
  const ReaderThumbnail({
    super.key,
    required this.source,
    required this.imageIndex,
    this.borderRadius = BorderRadius.zero,
  });

  final ReaderImageSource source;
  final int imageIndex;
  final BorderRadius borderRadius;

  @override
  State<ReaderThumbnail> createState() => _ReaderThumbnailState();
}

class _ReaderThumbnailState extends State<ReaderThumbnail> {
  StreamSubscription<int>? _sub;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.source.thumbnailReadyStream.where((i) => i == widget.imageIndex).listen((_) {
      if (mounted) setState(() {});
    });
    _maybeRequest();
  }

  void _maybeRequest() {
    if (_requested) return;
    if (widget.source.isLocal) return;
    if (widget.source.peekThumbnail(widget.imageIndex) != null) return;
    _requested = true;
    widget.source.getThumbnail(widget.imageIndex).catchError((_) => null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;

    if (source.isLocal) {
      final image = source.peekImage(widget.imageIndex);
      if (image == null || image.path == null) {
        return Center(child: UIConfig.loadingAnimation(context));
      }
      final path = source is DownloadedImageSource
          ? DownloadedImageSource.absolutePath(image.path!)
          : image.path!;
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: 200,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54),
        ),
      );
    }

    final thumb = source.peekThumbnail(widget.imageIndex);
    if (thumb == null) {
      return Center(child: UIConfig.loadingAnimation(context));
    }
    return LayoutBuilder(
      builder: (_, constraints) => EHThumbnail(
        thumbnail: thumb,
        containerHeight: constraints.maxHeight,
        containerWidth: constraints.maxWidth,
        borderRadius: widget.borderRadius,
      ),
    );
  }
}
