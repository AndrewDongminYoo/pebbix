// 🎯 Dart imports:
import 'dart:math';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/hex_cell.dart';

/// Converts between hex cells and world coordinates.
///
/// World space: origin at the board's top-left, x to the right, y downward.
/// The board spans `[0, width]` horizontally; row 0 bubble centers sit at
/// `y = bubbleRadius`.
class BoardGeometry {
  const new({required this.columns, required this.bubbleRadius});

  final int columns;
  final double bubbleRadius;

  double get width => columns * bubbleRadius * 2;

  /// Vertical distance between adjacent rows (hex circle packing).
  double get rowHeight => bubbleRadius * sqrt(3);

  int rowWidth(int row) => row.isOdd ? columns - 1 : columns;

  Point<double> center(HexCell cell) => Point(
    bubbleRadius * (2 * cell.col + 1) + (cell.r.isOdd ? bubbleRadius : 0),
    bubbleRadius + cell.r * rowHeight,
  );

  /// The in-bounds cell whose center is closest to [point].
  HexCell nearestCell(Point<double> point) {
    final row = max(0, ((point.y - bubbleRadius) / rowHeight).round());
    final shift = row.isOdd ? bubbleRadius : 0.0;
    final col = ((point.x - bubbleRadius - shift) / (2 * bubbleRadius)).round().clamp(
      0,
      rowWidth(row) - 1,
    );
    var best = HexCell.fromRowCol(row: row, col: col);
    var bestDistance = center(best).squaredDistanceTo(point);
    for (final n in best.neighbors) {
      if (n.r < 0 || n.col < 0 || n.col >= rowWidth(n.r)) continue;
      final d = center(n).squaredDistanceTo(point);
      if (d < bestDistance) {
        best = n;
        bestDistance = d;
      }
    }
    return best;
  }
}
