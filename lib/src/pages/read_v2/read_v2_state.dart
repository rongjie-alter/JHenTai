import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:jhentai/src/model/read_page_info.dart';

import 'data/reader_image_source.dart';
import 'slicing/page_group.dart';
import 'slicing/reading_mode.dart';
import 'strategy/reading_strategy.dart';

class ReadV2State {
  ReadV2State() {
    readPageInfo = Get.arguments as ReadPageInfo;
  }

  late final ReadPageInfo readPageInfo;
  late ReaderImageSource source;
  late ReadingModeV2 mode;
  late bool displayFirstPageAlone;

  List<PageGroup> groups = const [];
  int currentGroup = 0;

  bool isMenuOpen = false;

  final FocusNode focusNode = FocusNode();

  /// Handle to the currently-mounted strategy's state, used for advance/retreat.
  /// Replaced when [mode] changes.
  ReadingStrategyKey strategyKey = GlobalKey<ReadingStrategyState>();

  /// Thumbnail strip controllers — match v1's structure so the copied UI works.
  final ItemPositionsListener thumbnailPositionsListener = ItemPositionsListener.create();
  final ItemScrollController thumbnailsScrollController = ItemScrollController();
  final ScrollOffsetController thumbnailsScrollOffsetController = ScrollOffsetController();

  /// Current image index (resolves [currentGroup] into its first index for
  /// progress tracking + the thumbnail strip highlight).
  int get currentImageIndex {
    if (groups.isEmpty) return readPageInfo.initialIndex;
    final clamped = currentGroup.clamp(0, groups.length - 1);
    return groups[clamped].first;
  }

  int get pageCount => readPageInfo.pageCount;
}
