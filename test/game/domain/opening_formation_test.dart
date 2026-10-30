// 🎯 Dart imports:
import 'dart:math';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

void main() {
  test('seeds a connected non-flat formation', () {
    for (var seed = 0; seed < 64; seed++) {
      final board = BubbleBoard(columns: 8);

      seedOpeningFormation(
        board: board,
        startRows: 7,
        random: Random(seed),
        palette: BubbleColor.values.take(4).toList(growable: false),
      );

      expect(board.bottomRow, 6, reason: 'seed $seed must reach row 6');
      expect(
        board.occupiedCells.length,
        lessThan(53),
        reason: 'seed $seed must not fill all seven rows',
      );
      expect(
        board.occupiedCells.where((cell) => cell.row == 6),
        isNotEmpty,
        reason: 'seed $seed must have a readable peak',
      );
      expect(
        board.floatingBubbles(),
        isEmpty,
        reason: 'seed $seed must start ceiling-connected',
      );
      for (final occupied in board.occupiedCells.where(
        (cell) => cell.row > 0,
      )) {
        expect(
          occupied.neighbors.any(
            (neighbor) => neighbor.row == occupied.row - 1 && board.isOccupied(neighbor),
          ),
          isTrue,
          reason: 'seed $seed leaves $occupied without support above',
        );
      }
    }
  });
}
