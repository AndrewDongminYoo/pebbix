// 🎯 Dart imports:
import 'dart:math';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/bubble_board.dart';
import 'package:bubble_shooter/game/domain/bubble_color.dart';
import 'package:bubble_shooter/game/domain/hex_cell.dart';

/// Seeds a ceiling-connected opening whose visible columns are five to seven
/// rows deep, with a guaranteed peak and valley.
void seedOpeningFormation({
  required BubbleBoard board,
  required int startRows,
  required Random random,
  required List<BubbleColor> palette,
}) {
  assert(board.isEmpty, 'opening formation requires an empty board');
  assert(board.columns >= 3, 'opening formation requires at least 3 columns');
  assert(startRows >= 3, 'opening formation requires at least 3 rows');
  assert(palette.isNotEmpty, 'opening formation requires at least one colour');

  final depths = List.generate(
    board.columns,
    (_) => startRows - random.nextInt(3),
  );
  final commonColumns = board.columns - 1;
  final peak = random.nextInt(commonColumns);
  var valley = random.nextInt(commonColumns - 1);
  if (valley >= peak) valley++;
  depths[peak] = startRows;
  depths[valley] = startRows - 2;

  for (var row = 0; row < startRows; row++) {
    for (var col = 0; col < board.rowWidth(row); col++) {
      if (row >= depths[col]) continue;
      final cell = HexCell.fromRowCol(row: row, col: col);
      final supported =
          row == 0 ||
          cell.neighbors.any(
            (neighbor) => neighbor.row == row - 1 && board.isOccupied(neighbor),
          );
      if (!supported) continue;
      board.place(cell, palette[random.nextInt(palette.length)]);
    }
  }
}
