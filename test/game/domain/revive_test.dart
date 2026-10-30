// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);

void main() {
  group('applyRevive', () {
    test('retreats the ceiling one unit and clears fail-zone bubbles', () {
      // Column 0 filled rows 0..10 (no 3-match: alternating colors);
      // after retreating from offset 2 to 1, row 10 sits at world row 11
      // (>= failRow, cleared) while row 9 sits at 10 and survives.
      final board = BubbleBoard(columns: 8);
      for (var row = 0; row <= 10; row++) {
        board.place(
          cell(row, 0),
          row.isEven ? BubbleColor.red : BubbleColor.blue,
        );
      }
      final result = applyRevive(board: board, ceilingOffset: 2, failRow: 11);
      expect(result.ceilingOffset, 1);
      expect(result.cleared, {cell(10, 0)});
      expect(board.isOccupied(cell(10, 0)), isFalse);
      expect(board.isOccupied(cell(9, 0)), isTrue);
      expect(board.bottomRow, 9);
    });

    test('clears nothing when no bubble crosses the fail line', () {
      final board = BubbleBoard(columns: 8)..place(cell(0, 0), BubbleColor.red);
      final result = applyRevive(board: board, ceilingOffset: 3, failRow: 11);
      expect(result.ceilingOffset, 2);
      expect(result.cleared, isEmpty);
      expect(board.isOccupied(cell(0, 0)), isTrue);
    });

    test('does not retreat below zero', () {
      final board = BubbleBoard(columns: 8)..place(cell(0, 0), BubbleColor.red);
      final result = applyRevive(board: board, ceilingOffset: 0, failRow: 11);
      expect(result.ceilingOffset, 0);
    });

    test('drops clusters detached by the clearing', () {
      // Column 0 anchors rows 0..11. A column-3 chain (rows 5..10) hangs
      // from the ceiling ONLY via a row-11 bridge, so clearing row 11
      // must detach and drop the whole chain as a floating cluster.
      final board = BubbleBoard(columns: 8);
      for (var row = 0; row <= 11; row++) {
        board.place(
          cell(row, 0),
          row.isEven ? BubbleColor.red : BubbleColor.blue,
        );
      }
      board
        ..place(cell(11, 1), BubbleColor.green)
        ..place(cell(11, 2), BubbleColor.green);
      for (var row = 5; row <= 10; row++) {
        board.place(cell(row, 3), BubbleColor.purple);
      }
      // Sanity: nothing floats before the revive.
      expect(board.floatingBubbles(), isEmpty);

      final result = applyRevive(board: board, ceilingOffset: 2, failRow: 12);
      expect(result.ceilingOffset, 1);
      // Row 11 (world row 12 >= failRow) clears as overflow...
      expect(
        result.cleared,
        containsAll([cell(11, 0), cell(11, 1), cell(11, 2)]),
      );
      // ...and the column-3 chain, now unanchored, drops with it.
      expect(
        result.cleared,
        containsAll([for (var r = 5; r <= 10; r++) cell(r, 3)]),
      );
      expect(board.isOccupied(cell(10, 3)), isFalse);
      expect(board.isOccupied(cell(10, 0)), isTrue);
      expect(board.bottomRow, 10);
    });

    test('is deterministic for identical inputs', () {
      BubbleBoard build() {
        final board = BubbleBoard(columns: 8);
        for (var row = 0; row <= 9; row++) {
          board.place(
            cell(row, 0),
            row.isEven ? BubbleColor.red : BubbleColor.blue,
          );
        }
        return board;
      }

      final a = build();
      final b = build();
      final ra = applyRevive(board: a, ceilingOffset: 2, failRow: 11);
      final rb = applyRevive(board: b, ceilingOffset: 2, failRow: 11);
      expect(ra.ceilingOffset, rb.ceilingOffset);
      expect(ra.cleared, rb.cleared);
      expect(a.occupiedCells.toSet(), b.occupiedCells.toSet());
    });
  });
}
