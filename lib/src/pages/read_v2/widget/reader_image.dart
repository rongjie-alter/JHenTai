import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:jhentai/src/model/gallery_image.dart';

import '../data/local_image_source.dart';
import '../data/reader_image_source.dart';

/// Renders the image at [imageIndex] from [source]. Online sources stream the
/// bytes via [ExtendedImage.network]; local sources read the file directly.
class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.source,
    required this.imageIndex,
    this.fit = BoxFit.contain,
  });

  final ReaderImageSource source;
  final int imageIndex;
  final BoxFit fit;

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  StreamSubscription<int>? _sub;
  bool _requested = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.source.imageReadyStream.where((i) => i == widget.imageIndex).listen((_) {
      if (mounted) setState(() => _error = null);
    });
    _maybeRequest();
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageIndex != widget.imageIndex || oldWidget.source != widget.source) {
      _sub?.cancel();
      _sub = widget.source.imageReadyStream.where((i) => i == widget.imageIndex).listen((_) {
        if (mounted) setState(() => _error = null);
      });
      _requested = false;
      _error = null;
      _maybeRequest();
    }
  }

  void _maybeRequest() {
    if (_requested) return;
    if (widget.source.peekImage(widget.imageIndex) != null) return;
    _requested = true;
    widget.source.getImage(widget.imageIndex).then((_) {
      if (mounted) setState(() => _error = null);
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _requested = false;
    });
    await widget.source.reloadImage(widget.imageIndex);
    _maybeRequest();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.source.peekImage(widget.imageIndex);
    final error = _error ?? widget.source.errorFor(widget.imageIndex);

    if (image == null) {
      if (error != null) {
        return _ErrorView(message: '$error', onRetry: _retry);
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.source.isLocal && image.path != null) {
      return _LocalImage(image: image, fit: widget.fit, source: widget.source);
    }
    return ExtendedImage.network(
      image.url,
      fit: widget.fit,
      cache: true,
      clearMemoryCacheWhenDispose: true,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(child: CircularProgressIndicator());
          case LoadState.failed:
            return _ErrorView(message: 'Load failed', onRetry: _retry);
          case LoadState.completed:
            return null;
        }
      },
    );
  }
}

class _LocalImage extends StatelessWidget {
  const _LocalImage({required this.image, required this.fit, required this.source});

  final GalleryImage image;
  final BoxFit fit;
  final ReaderImageSource source;

  @override
  Widget build(BuildContext context) {
    String absolute;
    if (source is DownloadedImageSource) {
      absolute = DownloadedImageSource.absolutePath(image.path!);
    } else {
      absolute = image.path!;
    }
    final file = File(absolute);
    return Image.file(file, fit: fit, errorBuilder: (_, __, ___) => const _ErrorView(message: 'File missing'));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
