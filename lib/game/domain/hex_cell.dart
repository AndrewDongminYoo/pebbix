// 📦 Package imports:
import 'package:meta/meta.dart';

/// A cell on the hex grid in axial coordinates `(q, r)`.
///
/// The board uses "odd-r" offset rows visually (odd rows shifted right and
/// one bubble narrower); [HexCell.fromRowCol] and [col] convert between the
/// two representations. Row 0 is the ceiling.
@immutable
class HexCell {
  const new(this.q, this.r);

  /// Creates a cell from visual [row]/[col] (odd-r offset) coordinates.
  factory fromRowCol({required int row, required int col}) => HexCell(col - ((row - (row & 1)) >> 1), row);

  final int q;
  final int r;

  int get row => r;
  int get col => q + ((r - (r & 1)) >> 1);

  static const List<(int, int)> _directions = [
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
  ];

  /// The six axial neighbors, regardless of board bounds.
  List<HexCell> get neighbors => [
    for (final (dq, dr) in _directions) HexCell(q + dq, r + dr),
  ];

  @override
  bool operator ==(Object other) => other is HexCell && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'HexCell($q, $r)';
}
