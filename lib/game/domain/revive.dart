// 🎯 Dart imports:
import 'dart:math' as math;

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/bubble_board.dart';
import 'package:bubble_shooter/game/domain/hex_cell.dart';

/// Outcome of a rewarded Continue applied to the board.
class ReviveResult {
  const new({required this.ceilingOffset, required this.cleared});

  /// Ceiling offset after retreating one descent unit (floored at 0).
  final int ceilingOffset;

  /// Cells removed: fail-zone overflow plus clusters that came loose.
  final Set<HexCell> cleared;
}

/// The Continue operation, defined by the failure condition (spec §3):
/// retreat the ceiling exactly one unit, remove whatever still crosses
/// the fail line, then resolve floating clusters normally. Mutates
/// [board] in place; awards no score (scoring stays in the game layer).
ReviveResult applyRevive({
  required BubbleBoard board,
  required int ceilingOffset,
  required int failRow,
}) {
  final retreated = math.max(0, ceilingOffset - 1);
  final overflowing = {
    for (final cell in board.occupiedCells)
      if (cell.r + retreated >= failRow) cell,
  }..forEach(board.remove);
  final floating = board.floatingBubbles()..forEach(board.remove);
  return ReviveResult(
    ceilingOffset: retreated,
    cleared: {...overflowing, ...floating},
  );
}
