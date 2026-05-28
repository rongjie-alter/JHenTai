import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/model/read_page_info.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/service/read_progress_service.dart';
import 'package:jhentai/src/setting/read_setting.dart';
import 'package:jhentai/src/setting/read_v2_setting.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data/local_image_source.dart';
import 'data/online_image_source.dart';
import 'read_v2_state.dart';
import 'slicing/page_group.dart';
import 'slicing/reading_mode.dart';
import 'slicing/slicing_engine.dart';
import 'strategy/reading_strategy.dart';

class ReadV2Logic extends GetxController {
  static const String pageId = 'readV2/page';
  static const String layoutId = 'readV2/layout';
  static const String topMenuId = 'readV2/topMenu';
  static const String bottomMenuId = 'readV2/bottomMenu';
  static const String rightBottomInfoId = 'readV2/rightBottomInfo';
  static const String pageNoId = 'readV2/pageNo';
  static const String thumbnailNoId = 'readV2/thumbnailNo';
  static const String sliderId = 'readV2/slider';
  static const String currentTimeId = 'readV2/currentTime';

  final ReadV2State state = ReadV2State();

  late Worker _modeListener;
  late Worker _displayFirstPageAloneListener;
  late Worker _immersiveListener;
  Timer? _progressFlushTimer;

  @override
  void onInit() {
    super.onInit();
    state.mode = readV2Setting.readingMode.value;
    state.displayFirstPageAlone = readV2Setting.displayFirstPageAlone.value;

    _buildSource();
    _rebuildGroups();

    state.currentGroup = SlicingEngine.findGroupOf(state.groups, state.readPageInfo.initialIndex);
    if (state.currentGroup < 0) state.currentGroup = 0;
  }

  @override
  void onReady() {
    super.onReady();
    _applyImmersiveMode();
    if (readSetting.keepScreenAwakeWhenReading.isTrue) {
      WakelockPlus.enable();
    }

    _modeListener = ever(readV2Setting.readingMode, (ReadingModeV2 mode) {
      if (state.mode == mode) return;
      state.mode = mode;
      _rebuildGroupsPreservingPosition();
      state.strategyKey = GlobalKey<ReadingStrategyState>();
      updateSafely([layoutId, topMenuId, bottomMenuId]);
    });

    _displayFirstPageAloneListener = ever(readV2Setting.displayFirstPageAlone, (bool value) {
      if (state.displayFirstPageAlone == value) return;
      state.displayFirstPageAlone = value;
      _rebuildGroupsPreservingPosition();
      state.strategyKey = GlobalKey<ReadingStrategyState>();
      updateSafely([layoutId, topMenuId, bottomMenuId]);
    });

    _immersiveListener = ever(readSetting.enableImmersiveMode, (_) => _applyImmersiveMode());

    _progressFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flushProgress());
  }

  @override
  void onClose() {
    _modeListener.dispose();
    _displayFirstPageAloneListener.dispose();
    _immersiveListener.dispose();
    _progressFlushTimer?.cancel();
    state.focusNode.dispose();
    state.source.dispose();
    WakelockPlus.disable();
    _restoreImmersiveMode();
    _flushProgress();
    super.onClose();
  }

  void _buildSource() {
    final info = state.readPageInfo;
    switch (info.mode) {
      case ReadMode.online:
        state.source = OnlineImageSource(galleryUrl: info.galleryUrl!, pageCount: info.pageCount);
        break;
      case ReadMode.downloaded:
        state.source = DownloadedImageSource.fromService(info.gid!);
        break;
      case ReadMode.archive:
      case ReadMode.local:
        state.source = ArchiveImageSource(images: info.images!);
        break;
    }
  }

  void _rebuildGroups() {
    state.groups = SlicingEngine.slice(
      pageCount: state.pageCount,
      mode: state.mode,
      displayFirstPageAlone: state.displayFirstPageAlone,
    );
  }

  void _rebuildGroupsPreservingPosition() {
    final lastImage = state.currentImageIndex;
    _rebuildGroups();
    state.currentGroup = max(0, SlicingEngine.findGroupOf(state.groups, lastImage));
  }

  /// Called by the active strategy when its visible group changes.
  void onStrategyGroupChanged(int newGroup) {
    if (state.currentGroup == newGroup) return;
    state.currentGroup = newGroup;
    state.readPageInfo.currentImageIndex = state.currentImageIndex;
    updateSafely([sliderId, pageNoId, thumbnailNoId]);
  }

  void advance() {
    state.strategyKey.currentState?.advance();
  }

  void retreat() {
    state.strategyKey.currentState?.retreat();
  }

  void jumpToImageIndex(int imageIndex) {
    final groupIndex = SlicingEngine.findGroupOf(state.groups, imageIndex);
    if (groupIndex < 0) return;
    state.strategyKey.currentState?.jumpToGroup(groupIndex);
  }

  void toggleMenu() {
    state.isMenuOpen = !state.isMenuOpen;
    updateSafely([topMenuId, bottomMenuId, rightBottomInfoId]);
  }

  void tapLeftRegion() {
    if (state.mode.isRightToLeft) {
      advance();
    } else {
      retreat();
    }
  }

  void tapRightRegion() {
    if (state.mode.isRightToLeft) {
      retreat();
    } else {
      advance();
    }
  }

  void tapCenterRegion() => toggleMenu();

  /// Maps a "physical" direction press to retreat/advance based on RTL.
  void onLeftPressed() => tapLeftRegion();
  void onRightPressed() => tapRightRegion();

  /// Vertical mode arrows + PageUp/PageDown: always semantic prev/next.
  void onPrevPressed() => retreat();
  void onNextPressed() => advance();

  void handleSlide(double pageNo) {
    final group = SlicingEngine.findGroupOf(state.groups, (pageNo - 1).toInt());
    if (group < 0) return;
    state.currentGroup = group;
    state.readPageInfo.currentImageIndex = state.currentImageIndex;
    updateSafely([sliderId, pageNoId]);
  }

  void handleSlideEnd(double pageNo) {
    jumpToImageIndex((pageNo - 1).toInt());
  }

  void toggleDisplayFirstPageAlone() {
    readV2Setting.saveDisplayFirstPageAlone(!state.displayFirstPageAlone);
  }

  Future<PageGroup?> peekGroup(int index) async {
    if (index < 0 || index >= state.groups.length) return null;
    return state.groups[index];
  }

  void _applyImmersiveMode() {
    if (readSetting.enableImmersiveMode.isTrue) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _restoreImmersiveMode() {
    if (GetPlatform.isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _flushProgress() async {
    readProgressService.updateReadProgress(
      state.readPageInfo.readProgressRecordStorageKey,
      state.currentImageIndex,
    );
  }

  /// Helper used by the page widget to log debug info on entry.
  void debugDump() {
    log.debug(
      'ReadV2Logic: mode=${state.mode.name} groups=${state.groups.length} '
      'currentGroup=${state.currentGroup} pageCount=${state.pageCount}',
    );
  }
}
