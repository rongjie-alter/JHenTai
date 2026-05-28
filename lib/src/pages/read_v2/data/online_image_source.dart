import 'dart:async';

import 'package:dio/dio.dart';
import 'package:executor/executor.dart';
import 'package:extended_image/extended_image.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/exception/eh_parse_exception.dart';
import 'package:jhentai/src/exception/eh_site_exception.dart';
import 'package:jhentai/src/extension/dio_exception_extension.dart';
import 'package:jhentai/src/model/detail_page_info.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_thumbnail.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/setting/site_setting.dart';
import 'package:jhentai/src/utils/eh_executor.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:retry/retry.dart';

import 'reader_image_source.dart';

/// Online (network-parsed) image source.
///
/// Mirrors v1's parse-href -> parse-url pipeline but stays in its own file
/// so v1 [`read_page_logic.dart`](../../read/read_page_logic.dart) doesn't need
/// to be touched. Uses the shared [EHExecutor] rate-limiter pattern to avoid
/// hammering the site.
class OnlineImageSource implements ReaderImageSource {
  OnlineImageSource({required this.galleryUrl, required this.pageCount})
      : _thumbnails = List.filled(pageCount, null, growable: false),
        _images = List.filled(pageCount, null, growable: false),
        _thumbnailLoading = List.filled(pageCount, false, growable: false),
        _imageLoading = List.filled(pageCount, false, growable: false);

  final String galleryUrl;

  @override
  final int pageCount;

  int _thumbnailsCountPerPage = SiteSetting.thumbnailsCountPerPage.value;

  final List<GalleryThumbnail?> _thumbnails;
  final List<GalleryImage?> _images;
  final List<bool> _thumbnailLoading;
  final List<bool> _imageLoading;
  final Map<int, String> _errors = {};

  final Map<int, Completer<GalleryImage>> _imageWaiters = {};
  final Map<int, Completer<GalleryThumbnail?>> _thumbnailWaiters = {};

  final StreamController<int> _imageReady = StreamController.broadcast();
  final StreamController<int> _thumbnailReady = StreamController.broadcast();

  final EHExecutor _executor = EHExecutor(
    concurrency: 100,
    rate: const Rate(10, Duration(milliseconds: 1000)),
  );

  static const int _normalPriority = 10000;

  @override
  bool get isLocal => false;

  @override
  Stream<int> get imageReadyStream => _imageReady.stream;

  @override
  Stream<int> get thumbnailReadyStream => _thumbnailReady.stream;

  @override
  GalleryImage? peekImage(int index) => _images[index];

  @override
  GalleryThumbnail? peekThumbnail(int index) => _thumbnails[index];

  @override
  String? errorFor(int index) => _errors[index];

  @override
  Future<GalleryThumbnail?> getThumbnail(int index) {
    if (_thumbnails[index] != null) {
      return Future.value(_thumbnails[index]);
    }
    final existing = _thumbnailWaiters[index];
    if (existing != null) return existing.future;

    final completer = Completer<GalleryThumbnail?>();
    _thumbnailWaiters[index] = completer;
    _scheduleParseThumbnailBatch(index);
    return completer.future;
  }

  @override
  Future<GalleryImage> getImage(int index, {bool reParse = false, String? reloadKey}) {
    if (_images[index] != null && !reParse) {
      return Future.value(_images[index]);
    }
    final existing = _imageWaiters[index];
    if (existing != null && !reParse) return existing.future;

    final completer = Completer<GalleryImage>();
    _imageWaiters[index] = completer;
    _scheduleParseImage(index, reParse: reParse, reloadKey: reloadKey);
    return completer.future;
  }

  @override
  Future<void> reloadImage(int index) async {
    final cached = _images[index];
    _errors.remove(index);
    if (cached != null) {
      clearDiskCachedImage(cached.url);
    }
    _images[index] = null;
    final waiter = _imageWaiters.remove(index);
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Reload superseded'));
    }
    await getImage(index, reParse: true, reloadKey: cached?.reloadKey);
  }

  void _scheduleParseThumbnailBatch(int index) {
    if (_thumbnailLoading[index]) return;
    _thumbnailLoading[index] = true;
    _executor.scheduleTask(_normalPriority, () => _parseThumbnailBatch(index));
  }

  Future<void> _parseThumbnailBatch(int index) async {
    final pageIndex = index ~/ _thumbnailsCountPerPage;
    DetailPageInfo info;
    try {
      info = await retry(
        () => ehRequest.requestDetailPage(
          galleryUrl: galleryUrl,
          thumbnailsPageIndex: pageIndex,
          parser: EHSpiderParser.detailPage2RangeAndThumbnails,
        ),
        maxAttempts: 3,
        retryIf: (e) => e is DioException,
        onRetry: (e) => log.error('OnlineImageSource: thumbnail batch retry', (e as DioException).errorMsg),
      );
    } catch (e) {
      _failThumbnails(index, _describeError(e));
      return;
    }

    final changed = _thumbnailsCountPerPage != info.thumbnailsCountPerPage;
    _thumbnailsCountPerPage = info.thumbnailsCountPerPage;

    for (int i = info.imageNoFrom; i <= info.imageNoTo; i++) {
      if (i - info.imageNoFrom < info.thumbnails.length && i - 1 < pageCount) {
        _thumbnails[i - 1] = info.thumbnails[i - info.imageNoFrom];
      }
    }

    if (_thumbnails[index] == null) {
      log.warning('OnlineImageSource: thumbnail batch did not populate index $index, reparse (perPage changed=$changed)');
      await ehRequest.removeCacheByGalleryUrlAndPage(galleryUrl, pageIndex);
      _thumbnailLoading[index] = false;
      _scheduleParseThumbnailBatch(index);
      return;
    }

    for (int i = info.imageNoFrom; i <= info.imageNoTo; i++) {
      final idx = i - 1;
      if (idx >= pageCount) continue;
      _thumbnailLoading[idx] = false;
      final waiter = _thumbnailWaiters.remove(idx);
      if (waiter != null && !waiter.isCompleted) waiter.complete(_thumbnails[idx]);
      if (!_thumbnailReady.isClosed) _thumbnailReady.add(idx);
    }
  }

  void _failThumbnails(int index, String message) {
    _thumbnailLoading[index] = false;
    _errors[index] = message;
    final waiter = _thumbnailWaiters.remove(index);
    if (waiter != null && !waiter.isCompleted) waiter.completeError(Exception(message));
  }

  void _scheduleParseImage(int index, {bool reParse = false, String? reloadKey}) {
    if (_imageLoading[index]) return;
    _imageLoading[index] = true;
    _executor.scheduleTask(_normalPriority, () => _parseImage(index, reParse: reParse, reloadKey: reloadKey));
  }

  Future<void> _parseImage(int index, {required bool reParse, String? reloadKey}) async {
    // Ensure thumbnail (which carries the image-page href) is loaded first.
    if (_thumbnails[index] == null) {
      try {
        await getThumbnail(index);
      } catch (e) {
        _failImage(index, _describeError(e));
        return;
      }
    }
    final thumb = _thumbnails[index];
    if (thumb == null) {
      _failImage(index, 'Thumbnail not available');
      return;
    }

    final href = thumb.replacedMPVHref(index + 1);
    GalleryImage image;
    try {
      image = await retry(
        () => ehRequest.requestImagePage(
          href,
          reloadKey: reloadKey,
          parser: EHSpiderParser.imagePage2GalleryImage,
          useCacheIfAvailable: !reParse,
        ),
        maxAttempts: 3,
        retryIf: (e) => e is DioException,
        onRetry: (e) => log.error('OnlineImageSource: image-page retry index=$index', (e as DioException).errorMsg),
      );
    } catch (e) {
      _failImage(index, _describeError(e));
      return;
    }

    _images[index] = image;
    _imageLoading[index] = false;
    _errors.remove(index);
    final waiter = _imageWaiters.remove(index);
    if (waiter != null && !waiter.isCompleted) waiter.complete(image);
    if (!_imageReady.isClosed) _imageReady.add(index);
  }

  void _failImage(int index, String message) {
    _imageLoading[index] = false;
    _errors[index] = message;
    final waiter = _imageWaiters.remove(index);
    if (waiter != null && !waiter.isCompleted) waiter.completeError(Exception(message));
  }

  String _describeError(Object e) {
    if (e is DioException) return 'parsePageFailed'.tr;
    if (e is EHSiteException) return e.message;
    if (e is EHParseException) return e.message.tr;
    return e.toString();
  }

  @override
  void dispose() {
    _executor.close();
    _imageReady.close();
    _thumbnailReady.close();
    for (final c in _imageWaiters.values) {
      if (!c.isCompleted) c.completeError(StateError('Source disposed'));
    }
    for (final c in _thumbnailWaiters.values) {
      if (!c.isCompleted) c.completeError(StateError('Source disposed'));
    }
    _imageWaiters.clear();
    _thumbnailWaiters.clear();
  }
}
