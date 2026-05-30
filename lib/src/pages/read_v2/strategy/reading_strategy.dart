import 'package:flutter/widgets.dart';

import '../data/reader_image_source.dart';
import '../slicing/page_group.dart';
import '../slicing/reading_mode.dart';

/// Read-only context handed to a strategy at build-time.
class ReadingStrategyContext {
  const ReadingStrategyContext({
    required this.mode,
    required this.groups,
    required this.initialGroup,
    required this.source,
    required this.imageBuilder,
    required this.onGroupChanged,
    required this.minScale,
    required this.maxScale,
    required this.imageSpace,
    required this.enablePageAnime,
  });

  final ReadingModeV2 mode;
  final List<PageGroup> groups;
  final int initialGroup;

  /// Image source for the gallery being read. Strategies use it to peek
  /// per-image metadata (dimensions, thumbnails) for size-locking.
  final ReaderImageSource source;

  /// Builds the widget rendering image at index [imageIndex].
  final Widget Function(int imageIndex) imageBuilder;

  /// Called by the strategy when the current group changes due to internal
  /// scroll or page transition. The logic uses this to update progress.
  final void Function(int newGroup) onGroupChanged;

  final double minScale;
  final double maxScale;
  final int imageSpace;
  final bool enablePageAnime;
}

/// Abstract state class for all strategies. Allows the page logic to hold a
/// single `GlobalKey<ReadingStrategyState>` and dispatch advance / retreat /
/// jump-to-group commands without caring which concrete strategy is mounted.
abstract class ReadingStrategyState<T extends StatefulWidget> extends State<T> {
  /// Move forward by one group (page modes) or roughly one screen (continuous).
  void advance();

  /// Move backward by one group / one screen.
  void retreat();

  /// Jump to the group containing a specific group index. Continuous strategies
  /// scroll the corresponding image into view; page strategies animate to it.
  void jumpToGroup(int group);
}

/// Convenience typedef for the page logic.
typedef ReadingStrategyKey = GlobalKey<ReadingStrategyState>;
