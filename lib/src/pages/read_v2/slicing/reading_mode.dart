/// Reading modes supported by the v2 reader.
enum ReadingModeV2 {
  verticalContinuous,
  horizontalContinuousLTR,
  horizontalContinuousRTL,
  singlePage,
  doublePageLTR,
  doublePageRTL;

  bool get isContinuous =>
      this == verticalContinuous ||
      this == horizontalContinuousLTR ||
      this == horizontalContinuousRTL;

  bool get isPageBased => this == singlePage || this == doublePageLTR || this == doublePageRTL;

  bool get isDouble => this == doublePageLTR || this == doublePageRTL;

  bool get isRightToLeft => this == horizontalContinuousRTL || this == doublePageRTL;

  bool get isHorizontal =>
      this == horizontalContinuousLTR ||
      this == horizontalContinuousRTL ||
      this == singlePage ||
      this == doublePageLTR ||
      this == doublePageRTL;
}
