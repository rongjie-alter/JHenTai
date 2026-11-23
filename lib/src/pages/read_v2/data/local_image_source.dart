import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_thumbnail.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/log.dart';

import 'reader_image_source.dart';

/// Shared base for downloaded and archive sources. Both have pre-resolved
/// image paths and need no network parsing.
abstract class LocalImageSourceBase implements ReaderImageSource {
  LocalImageSourceBase({required this.images});

  /// Backing list. Length is [pageCount]. Nulls indicate "not yet present
  /// in this list" (rare for archive, common for partially-downloaded gallery).
  final List<GalleryImage?> images;

  /// Per-index error string set when getImage fails. Cleared on reload.
  final Map<int, String> _errors = {};

  final StreamController<int> _imageReady = StreamController.broadcast();
  final StreamController<int> _thumbnailReady = StreamController.broadcast();

  @override
  int get pageCount => images.length;

  @override
  bool get isLocal => true;

  @override
  Stream<int> get imageReadyStream => _imageReady.stream;

  @override
  Stream<int> get thumbnailReadyStream => _thumbnailReady.stream;

  /// Whether [image] is fully present on disk and safe to render.
  /// Subclasses override this when files can still be in flight.
  bool isImageReady(GalleryImage image) => true;

  @override
  GalleryImage? peekImage(int index) {
    final image = peekImageMetadata(index);
    if (image == null || !isImageReady(image)) return null;
    return image;
  }

  @override
  GalleryImage? peekImageMetadata(int index) {
    if (index < 0 || index >= images.length) return null;
    return images[index];
  }

  @override
  GalleryThumbnail? peekThumbnail(int index) => null;

  /// Thumbnails for local sources are just the image itself shown small.
  /// We don't surface a separate thumbnail object; the UI uses the image path.
  @override
  Future<GalleryThumbnail?> getThumbnail(int index) async => null;

  @override
  String? errorFor(int index) => _errors[index];

  /// Pending [getImage] calls for images that exist in the gallery but are not
  /// ready yet (e.g. still downloading). Completed by [notifyImageReady].
  final Map<int, Completer<GalleryImage>> _waiters = {};

  @override
  Future<GalleryImage> getImage(int index, {bool reParse = false, String? reloadKey}) {
    if (index < 0 || index >= images.length) {
      const msg = 'Image not found';
      _errors[index] = msg;
      return Future.error(StateError('$msg at index $index'));
    }
    final image = peekImage(index);
    if (image != null) return Future.value(image);
    return (_waiters[index] ??= Completer<GalleryImage>()).future;
  }

  @override
  Future<void> reloadImage(int index) async {
    _errors.remove(index);
    if (!_imageReady.isClosed) _imageReady.add(index);
  }

  /// Subclasses call this when the image at [index] changes (e.g. a download
  /// completes while the reader is open). Resolves pending [getImage] calls
  /// once the image is ready and tells listeners to rebuild.
  void notifyImageReady(int index) {
    final image = peekImage(index);
    if (image != null) {
      _errors.remove(index);
      final waiter = _waiters.remove(index);
      if (waiter != null && !waiter.isCompleted) waiter.complete(image);
    }
    if (!_imageReady.isClosed) _imageReady.add(index);
  }

  @override
  void dispose() {
    // Pending waiters are left uncompleted on purpose: their widgets are being
    // disposed too, and completing with an error would surface as unhandled.
    _waiters.clear();
    _imageReady.close();
    _thumbnailReady.close();
  }
}

/// Source for galleries already downloaded via `GalleryDownloadService`.
/// Backed by `galleryDownloadInfos[gid].images` so newly-downloaded pages
/// appear without a reload.
class DownloadedImageSource extends LocalImageSourceBase {
  DownloadedImageSource({required this.gid, required List<GalleryImage?> images}) : super(images: images) {
    for (int i = 0; i < images.length; i++) {
      _disposers.add(
        galleryDownloadService.addListenerId('${galleryDownloadService.downloadImageId}::$gid::$i', () => notifyImageReady(i)),
      );
    }
  }

  final int gid;

  final List<VoidCallback> _disposers = [];

  factory DownloadedImageSource.fromService(int gid) {
    final info = galleryDownloadService.galleryDownloadInfos[gid];
    if (info == null) {
      log.error('DownloadedImageSource: no download info for gid=$gid');
      return DownloadedImageSource(gid: gid, images: const []);
    }
    return DownloadedImageSource(gid: gid, images: info.images);
  }

  /// The download service assigns `path` before the file is written, so only
  /// fully-downloaded images may be rendered.
  @override
  bool isImageReady(GalleryImage image) => image.downloadStatus == DownloadStatus.downloaded;

  @override
  void dispose() {
    for (final disposer in _disposers) {
      disposer();
    }
    _disposers.clear();
    super.dispose();
  }

  /// Resolve a relative path to an absolute path on disk.
  static String absolutePath(String relativePath) =>
      GalleryDownloadService.computeImageDownloadAbsolutePathFromRelativePath(relativePath);
}

/// Source for unpacked archives. The image list is materialised once
/// at construction time and does not change while the reader is open.
class ArchiveImageSource extends LocalImageSourceBase {
  ArchiveImageSource({required List<GalleryImage> images}) : super(images: images.cast<GalleryImage?>());
}
