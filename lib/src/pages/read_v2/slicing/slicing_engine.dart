import 'page_group.dart';
import 'reading_mode.dart';

/// Pure transformer from a chronological image index list to a list of
/// renderable groups. Direction (LTR vs RTL) is intentionally *not* applied
/// here — that is the strategy's job.
class SlicingEngine {
  const SlicingEngine._();

  static List<PageGroup> slice({
    required int pageCount,
    required ReadingModeV2 mode,
    required bool displayFirstPageAlone,
  }) {
    if (pageCount <= 0) {
      return const [];
    }

    if (!mode.isDouble) {
      return [for (int i = 0; i < pageCount; i++) PageGroup.single(i)];
    }

    final groups = <PageGroup>[];
    int cursor = 0;

    if (displayFirstPageAlone) {
      groups.add(PageGroup.single(0));
      cursor = 1;
    }

    while (cursor + 1 < pageCount) {
      groups.add(PageGroup.pair(cursor, cursor + 1));
      cursor += 2;
    }
    if (cursor < pageCount) {
      groups.add(PageGroup.single(cursor));
    }

    return groups;
  }

  /// Returns the group index that contains [imageIndex]. -1 if none.
  static int findGroupOf(List<PageGroup> groups, int imageIndex) {
    for (int i = 0; i < groups.length; i++) {
      if (groups[i].contains(imageIndex)) return i;
    }
    return -1;
  }
}
