import 'dart:async';

import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_thumbnail.dart';

/// Abstract source of images for the v2 reader. Three implementations exist:
/// online (network-parsed), downloaded (already on disk), archive (extracted zip).
abstract class ReaderImageSource {
  int get pageCount;

  /// True when image bytes are available without a network call (downloaded / archive).
  bool get isLocal;

  /// Fires the index of an image whose [GalleryImage] just became available
  /// (i.e. URL/path resolved). UI listens to rebuild that page.
  Stream<int> get imageReadyStream;

  /// Fires the index of a thumbnail that just became available.
  Stream<int> get thumbnailReadyStream;

  /// Already-resolved image, or null if not yet ready. Cheap, sync.
  GalleryImage? peekImage(int index);

  /// Already-resolved thumbnail, or null if not yet ready. Cheap, sync.
  GalleryThumbnail? peekThumbnail(int index);

  /// Kicks off resolution if needed. For local sources this returns immediately
  /// (the path is already known). For online, schedules parse-href + parse-url
  /// and resolves when both succeed.
  Future<GalleryImage> getImage(int index, {bool reParse = false, String? reloadKey});

  /// Returns the thumbnail (used by the bottom thumbnail strip).
  Future<GalleryThumbnail?> getThumbnail(int index);

  /// Force-reload an image (clear cache, re-parse if online).
  Future<void> reloadImage(int index);

  /// Optional human-readable error for [index], or null if no error.
  String? errorFor(int index);

  void dispose();
}
