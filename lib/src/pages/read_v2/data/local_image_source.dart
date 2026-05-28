import 'dart:async';

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

  @override
  GalleryImage? peekImage(int index) {
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

  @override
  Future<GalleryImage> getImage(int index, {bool reParse = false, String? reloadKey}) async {
    final image = images[index];
    if (image == null) {
      const msg = 'Image not ready';
      _errors[index] = msg;
      throw StateError('$msg at index $index');
    }
    return image;
  }

  @override
  Future<void> reloadImage(int index) async {
    _errors.remove(index);
    _imageReady.add(index);
  }

  /// Subclasses call this when a previously-null image becomes non-null
  /// (e.g. download completes while the reader is open).
  void notifyImageReady(int index) {
    if (!_imageReady.isClosed) _imageReady.add(index);
  }

  @override
  void dispose() {
    _imageReady.close();
    _thumbnailReady.close();
  }
}

/// Source for galleries already downloaded via `GalleryDownloadService`.
/// Backed by `galleryDownloadInfos[gid].images` so newly-downloaded pages
/// appear without a reload.
class DownloadedImageSource extends LocalImageSourceBase {
  DownloadedImageSource({required this.gid, required List<GalleryImage?> images}) : super(images: images);

  final int gid;

  factory DownloadedImageSource.fromService(int gid) {
    final info = galleryDownloadService.galleryDownloadInfos[gid];
    if (info == null) {
      log.error('DownloadedImageSource: no download info for gid=$gid');
      return DownloadedImageSource(gid: gid, images: const []);
    }
    return DownloadedImageSource(gid: gid, images: info.images);
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
