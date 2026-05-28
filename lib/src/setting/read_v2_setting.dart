import 'dart:convert';

import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/pages/read_v2/slicing/reading_mode.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/log.dart';

ReadV2Setting readV2Setting = ReadV2Setting();

/// Mode-specific settings for the v2 reader.
///
/// Cross-cutting user preferences (immersive mode, custom brightness,
/// keep-screen-awake) are intentionally read from the existing
/// [`readSetting`](read_setting.dart) — those shouldn't differ between v1/v2.
class ReadV2Setting with JHLifeCircleBeanWithConfigStorage implements JHLifeCircleBean {
  Rx<ReadingModeV2> readingMode =
      (GetPlatform.isMobile ? ReadingModeV2.verticalContinuous : ReadingModeV2.horizontalContinuousLTR).obs;

  RxBool displayFirstPageAlone = true.obs;
  RxInt imageSpace = 6.obs;
  RxInt preloadDistance = 1.obs;
  RxInt preloadDistanceLocal = GetPlatform.isIOS ? 3.obs : 8.obs;
  RxBool showThumbnails = true.obs;
  RxBool showStatusInfo = true.obs;
  RxBool enableBottomMenu = false.obs;
  RxBool enablePageTurnAnime = true.obs;

  RxDouble minScale = 1.0.obs;
  RxDouble maxScale = 5.0.obs;

  @override
  ConfigEnum get configEnum => ConfigEnum.readV2Setting;

  @override
  Future<void> doInitBean() async {}

  @override
  void doAfterBeanReady() {}

  @override
  void applyBeanConfig(String configString) {
    Map map = jsonDecode(configString);
    readingMode.value = ReadingModeV2.values[map['readingMode'] ?? readingMode.value.index];
    displayFirstPageAlone.value = map['displayFirstPageAlone'] ?? displayFirstPageAlone.value;
    imageSpace.value = map['imageSpace'] ?? imageSpace.value;
    preloadDistance.value = map['preloadDistance'] ?? preloadDistance.value;
    preloadDistanceLocal.value = map['preloadDistanceLocal'] ?? preloadDistanceLocal.value;
    showThumbnails.value = map['showThumbnails'] ?? showThumbnails.value;
    showStatusInfo.value = map['showStatusInfo'] ?? showStatusInfo.value;
    enableBottomMenu.value = map['enableBottomMenu'] ?? enableBottomMenu.value;
    enablePageTurnAnime.value = map['enablePageTurnAnime'] ?? enablePageTurnAnime.value;
    minScale.value = (map['minScale'] as num?)?.toDouble() ?? minScale.value;
    maxScale.value = (map['maxScale'] as num?)?.toDouble() ?? maxScale.value;
  }

  @override
  String toConfigString() {
    return jsonEncode({
      'readingMode': readingMode.value.index,
      'displayFirstPageAlone': displayFirstPageAlone.value,
      'imageSpace': imageSpace.value,
      'preloadDistance': preloadDistance.value,
      'preloadDistanceLocal': preloadDistanceLocal.value,
      'showThumbnails': showThumbnails.value,
      'showStatusInfo': showStatusInfo.value,
      'enableBottomMenu': enableBottomMenu.value,
      'enablePageTurnAnime': enablePageTurnAnime.value,
      'minScale': minScale.value,
      'maxScale': maxScale.value,
    });
  }

  Future<void> saveReadingMode(ReadingModeV2 value) async {
    log.debug('saveReadingMode:${value.name}');
    readingMode.value = value;
    await saveBeanConfig();
  }

  Future<void> saveDisplayFirstPageAlone(bool value) async {
    log.debug('saveDisplayFirstPageAlone(v2):$value');
    displayFirstPageAlone.value = value;
    await saveBeanConfig();
  }

  Future<void> saveImageSpace(int value) async {
    log.debug('saveImageSpace(v2):$value');
    imageSpace.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadDistance(int value) async {
    log.debug('savePreloadDistance(v2):$value');
    preloadDistance.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadDistanceLocal(int value) async {
    log.debug('savePreloadDistanceLocal(v2):$value');
    preloadDistanceLocal.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowThumbnails(bool value) async {
    log.debug('saveShowThumbnails(v2):$value');
    showThumbnails.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowStatusInfo(bool value) async {
    log.debug('saveShowStatusInfo(v2):$value');
    showStatusInfo.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableBottomMenu(bool value) async {
    log.debug('saveEnableBottomMenu(v2):$value');
    enableBottomMenu.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnablePageTurnAnime(bool value) async {
    log.debug('saveEnablePageTurnAnime(v2):$value');
    enablePageTurnAnime.value = value;
    await saveBeanConfig();
  }

  Future<void> saveMinScale(double value) async {
    log.debug('saveMinScale(v2):$value');
    minScale.value = value;
    await saveBeanConfig();
  }

  Future<void> saveMaxScale(double value) async {
    log.debug('saveMaxScale(v2):$value');
    maxScale.value = value;
    await saveBeanConfig();
  }
}
