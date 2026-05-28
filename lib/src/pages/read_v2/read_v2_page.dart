import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/mixin/window_widget_mixin.dart';
import 'package:jhentai/src/setting/read_setting.dart';
import 'package:jhentai/src/setting/read_v2_setting.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/screen_size_util.dart';
import 'package:jhentai/src/widget/eh_keyboard_listener.dart';
import 'package:jhentai/src/widget/eh_mouse_button_listener.dart';
import 'package:jhentai/src/widget/eh_read_page_stack.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';

import 'read_v2_logic.dart';
import 'read_v2_state.dart';
import 'slicing/reading_mode.dart';
import 'strategy/reading_strategy.dart';
import 'strategy/strategy_dispatcher.dart';
import 'widget/reader_image.dart';
import 'widget/reader_thumbnail.dart';

class ReadV2Page extends StatefulWidget {
  const ReadV2Page({super.key});

  @override
  State<ReadV2Page> createState() => _ReadV2PageState();
}

class _ReadV2PageState extends State<ReadV2Page> with WindowListener, WindowWidgetMixin {
  final ReadV2Logic logic = Get.put<ReadV2Logic>(ReadV2Logic());
  late final ReadV2State state = Get.find<ReadV2Logic>().state;

  @override
  Brightness? get titleBarBrightness => Brightness.dark;

  @override
  Color? get titleBarColor => Colors.black;

  @override
  double get fullScreenTopPadding => 0;

  @override
  Widget build(BuildContext context) {
    Widget child = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: EHMouseButtonListener(
        onFifthButtonTapDown: (_) => backRoute(),
        child: EHKeyboardListener(
          focusNode: state.focusNode,
          handleEsc: backRoute,
          handleEnd: backRoute,
          handleSpace: logic.toggleMenu,
          handlePageDown: logic.onNextPressed,
          handlePageUp: logic.onPrevPressed,
          handleArrowDown: logic.onNextPressed,
          handleArrowUp: logic.onPrevPressed,
          handleArrowRight: logic.onRightPressed,
          handleArrowLeft: logic.onLeftPressed,
          handleA: logic.onLeftPressed,
          handleD: logic.onRightPressed,
          handleM: logic.toggleDisplayFirstPageAlone,
          handleF11: toggleFullScreen,
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(
                  color: UIConfig.readPageForeGroundColor,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  EHReadPageStack(
                    children: [
                      _buildLayout(),
                      _buildGestureRegion(),
                    ],
                  ),
                  _buildRightBottomInfo(context),
                  _buildTopMenu(context),
                  _buildBottomMenu(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.pageId,
      builder: (_) {
        if (readSetting.enableImmersiveMode.isFalse) {
          return buildWindow(child: child);
        }
        return child;
      },
    );
  }

  @override
  Widget buildWindow({required Widget child}) {
    return GetPlatform.isWindows
        ? buildWindowsTitle(child)
        : GetPlatform.isLinux
            ? buildLinuxTitle(child)
            : GetPlatform.isMacOS
                ? buildMaxOSTitle(child)
                : child;
  }

  /// Main image region — dispatches to the active strategy.
  Widget _buildLayout() {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.layoutId,
      builder: (_) {
        final ctx = ReadingStrategyContext(
          mode: state.mode,
          groups: state.groups,
          initialGroup: state.currentGroup,
          imageBuilder: (imageIndex) => ReaderImage(source: state.source, imageIndex: imageIndex),
          onGroupChanged: logic.onStrategyGroupChanged,
          minScale: readV2Setting.minScale.value,
          maxScale: readV2Setting.maxScale.value,
          imageSpace: readV2Setting.imageSpace.value,
          enablePageAnime: readV2Setting.enablePageTurnAnime.value,
        );
        return buildStrategy(key: state.strategyKey, ctx: ctx);
      },
    );
  }

  /// Tap regions: left/center/right.
  Widget _buildGestureRegion() {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.layoutId,
      builder: (_) {
        if (state.mode.isContinuous) {
          // Continuous modes: a single centered tap zone toggles the menu;
          // scroll/pinch is handled by the inner scrollable underneath.
          return Row(
            children: [
              const Expanded(flex: 1, child: SizedBox()),
              Expanded(
                flex: 2,
                child: GestureDetector(onTap: logic.tapCenterRegion, behavior: HitTestBehavior.opaque),
              ),
              const Expanded(flex: 1, child: SizedBox()),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: GestureDetector(onTap: logic.tapLeftRegion, behavior: HitTestBehavior.opaque)),
            Expanded(child: GestureDetector(onTap: logic.tapCenterRegion, behavior: HitTestBehavior.opaque)),
            Expanded(child: GestureDetector(onTap: logic.tapRightRegion, behavior: HitTestBehavior.opaque)),
          ],
        );
      },
    );
  }

  Widget _buildRightBottomInfo(BuildContext context) {
    return Positioned(
      bottom: 0,
      right: 0,
      child: Obx(() {
        if (readV2Setting.showStatusInfo.isFalse) return const SizedBox();
        Widget body = DefaultTextStyle(
          style: DefaultTextStyle.of(context).style.copyWith(
                color: UIConfig.readPageForeGroundColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
          child: Container(
            decoration: BoxDecoration(
              color: UIConfig.readPageRightBottomRegionColor,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
            ),
            padding: const EdgeInsets.only(right: 32, bottom: 1, top: 3, left: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildPageNoInfo().marginOnly(right: 10),
                _buildCurrentTime(),
              ],
            ),
          ),
        );
        return GetBuilder<ReadV2Logic>(
          id: ReadV2Logic.rightBottomInfoId,
          builder: (_) => state.isMenuOpen ? body.fadeOut() : body.fadeIn(),
        );
      }),
    );
  }

  Widget _buildPageNoInfo() {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.pageNoId,
      builder: (_) => Text('${state.currentImageIndex + 1}/${state.pageCount}'),
    );
  }

  Widget _buildCurrentTime() {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.currentTimeId,
      builder: (_) => Text(DateFormat('HH:mm').format(DateTime.now())),
    );
  }

  Widget _buildTopMenu(BuildContext context) {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.topMenuId,
      builder: (_) => AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
        height: state.isMenuOpen ? UIConfig.appBarHeight + context.mediaQuery.padding.top : 0,
        width: fullScreenWidth,
        child: AppBar(
          backgroundColor: UIConfig.readPageMenuColor,
          title: Text(state.readPageInfo.galleryTitle, style: const TextStyle(color: UIConfig.readPageButtonColor)),
          leading: const BackButton(color: UIConfig.readPageButtonColor),
          actions: [
            if (state.mode.isDouble)
              Obx(() => IconButton(
                    icon: Icon(
                      Icons.looks_one,
                      color: readV2Setting.displayFirstPageAlone.value
                          ? UIConfig.readPageActiveButtonColor(context)
                          : UIConfig.readPageButtonColor,
                    ),
                    onPressed: logic.toggleDisplayFirstPageAlone,
                  )),
            PopupMenuButton<ReadingModeV2>(
              icon: const Icon(Icons.view_carousel, color: UIConfig.readPageButtonColor),
              initialValue: state.mode,
              itemBuilder: (_) => ReadingModeV2.values
                  .map((m) => PopupMenuItem<ReadingModeV2>(value: m, child: Text(_readingModeLabel(m))))
                  .toList(),
              onSelected: (m) => readV2Setting.saveReadingMode(m),
            ),
          ],
        ),
      ),
    );
  }

  String _readingModeLabel(ReadingModeV2 m) {
    switch (m) {
      case ReadingModeV2.verticalContinuous:
        return 'Vertical';
      case ReadingModeV2.horizontalContinuousLTR:
        return 'Horizontal (LTR)';
      case ReadingModeV2.horizontalContinuousRTL:
        return 'Horizontal (RTL)';
      case ReadingModeV2.singlePage:
        return 'Single page';
      case ReadingModeV2.doublePageLTR:
        return 'Double page (LTR)';
      case ReadingModeV2.doublePageRTL:
        return 'Double page (RTL)';
    }
  }

  Widget _buildBottomMenu(BuildContext context) {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.bottomMenuId,
      builder: (_) => Obx(() {
        final showThumbs = readV2Setting.showThumbnails.value;
        final extraSpacing = max(MediaQuery.of(context).viewPadding.bottom, UIConfig.readPageBottomSpacingHeight);
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          bottom: state.isMenuOpen
              ? 0
              : (showThumbs ? -UIConfig.readPageBottomThumbnailsRegionHeight : 0) -
                  UIConfig.readPageBottomSliderHeight -
                  extraSpacing,
          child: ColoredBox(
            color: UIConfig.readPageMenuColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showThumbs) _buildThumbnails(context),
                _buildSlider(),
                SizedBox(height: extraSpacing),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildThumbnails(BuildContext context) {
    return SizedBox(
      width: fullScreenWidth,
      height: UIConfig.readPageBottomThumbnailsRegionHeight,
      child: ScrollablePositionedList.separated(
            scrollDirection: Axis.horizontal,
            reverse: state.mode.isRightToLeft,
            physics: const ClampingScrollPhysics(),
            minCacheExtent: fullScreenWidth,
            initialScrollIndex: state.readPageInfo.initialIndex,
            itemCount: state.pageCount,
            itemScrollController: state.thumbnailsScrollController,
            itemPositionsListener: state.thumbnailPositionsListener,
            scrollOffsetController: state.thumbnailsScrollOffsetController,
            itemBuilder: (_, imageIndex) => GetBuilder<ReadV2Logic>(
              id: ReadV2Logic.thumbnailNoId,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  SizedBox(
                    height: UIConfig.readPageThumbnailHeight,
                    width: UIConfig.readPageThumbnailWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => logic.jumpToImageIndex(imageIndex),
                      child: ReaderThumbnail(
                        source: state.source,
                        imageIndex: imageIndex,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color: state.currentImageIndex == imageIndex
                            ? UIConfig.readPageBottomCurrentImageHighlightBackgroundColor(context)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (imageIndex + 1).toString(),
                        style: TextStyle(
                          fontSize: 9,
                          color: state.currentImageIndex == imageIndex
                              ? UIConfig.readPageBottomCurrentImageHighlightForegroundColor(context)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
            separatorBuilder: (_, __) => const SizedBox(width: 6),
          ),
    );
  }

  Widget _buildSlider() {
    return GetBuilder<ReadV2Logic>(
      id: ReadV2Logic.sliderId,
      builder: (_) {
        final isRtl = state.mode.isRightToLeft;
        final current = state.currentImageIndex + 1;
        return SizedBox(
          height: UIConfig.readPageBottomSliderHeight,
          width: fullScreenWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(isRtl ? state.pageCount.toString() : current.toString()).marginOnly(left: 36, right: 4),
              Expanded(
                child: ExcludeFocus(
                  child: Material(
                    color: Colors.transparent,
                    child: RotatedBox(
                      quarterTurns: isRtl ? 2 : 0,
                      child: Slider(
                        min: 1,
                        max: state.pageCount.toDouble(),
                        value: current.toDouble().clamp(1, state.pageCount.toDouble()),
                        thumbColor: UIConfig.readPageForeGroundColor,
                        onChanged: logic.handleSlide,
                        onChangeEnd: logic.handleSlideEnd,
                      ),
                    ),
                  ),
                ),
              ),
              Text(isRtl ? current.toString() : state.pageCount.toString()).marginOnly(right: 36, left: 4),
            ],
          ),
        );
      },
    );
  }
}
