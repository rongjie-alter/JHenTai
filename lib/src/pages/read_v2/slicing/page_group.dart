/// A renderable unit produced by the slicing engine.
///
/// Holds 1 image index for single-page modes / continuous modes,
/// or 2 image indices for double-page modes.
///
/// Indices are stored in chronological order (low to high). Left-to-right
/// versus right-to-left ordering is the reading strategy's responsibility.
class PageGroup {
  final List<int> indices;

  const PageGroup(this.indices);

  PageGroup.single(int index) : indices = [index];

  PageGroup.pair(int left, int right) : indices = [left, right];

  bool get isDouble => indices.length == 2;

  int get first => indices.first;

  int get last => indices.last;

  bool contains(int imageIndex) => indices.contains(imageIndex);

  @override
  String toString() => 'PageGroup($indices)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PageGroup) return false;
    if (other.indices.length != indices.length) return false;
    for (int i = 0; i < indices.length; i++) {
      if (other.indices[i] != indices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(indices);
}
