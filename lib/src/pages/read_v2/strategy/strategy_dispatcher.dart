import 'package:flutter/widgets.dart';

import '../slicing/reading_mode.dart';
import 'double_page_strategy.dart';
import 'horizontal_continuous_strategy.dart';
import 'reading_strategy.dart';
import 'single_page_strategy.dart';
import 'vertical_continuous_strategy.dart';

/// Selects the correct strategy widget for a given [ReadingModeV2].
/// The [key] is forwarded so the page logic can hold a stable handle to the
/// mounted strategy's State and dispatch commands (advance / retreat / jump).
Widget buildStrategy({
  required ReadingStrategyKey key,
  required ReadingStrategyContext ctx,
}) {
  switch (ctx.mode) {
    case ReadingModeV2.verticalContinuous:
      return VerticalContinuousStrategy(key: key, ctx: ctx);
    case ReadingModeV2.horizontalContinuousLTR:
    case ReadingModeV2.horizontalContinuousRTL:
      return HorizontalContinuousStrategy(key: key, ctx: ctx);
    case ReadingModeV2.singlePage:
      return SinglePageStrategy(key: key, ctx: ctx);
    case ReadingModeV2.doublePageLTR:
    case ReadingModeV2.doublePageRTL:
      return DoublePageStrategy(key: key, ctx: ctx);
  }
}
