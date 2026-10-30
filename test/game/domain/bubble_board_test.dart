// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);

void main() {
  group('BubbleBoard', () {
    test('even rows hold columns bubbles, odd rows one fewer', () {
      final board = BubbleBoard(columns: 8);
      expect(board.rowWidth(0), 8);
      expect(board.rowWidth(1), 7);
      expect(board.isValidCell(cell(0, 7)), isTrue);
      expect(board.isValidCell(cell(0, 8)), isFalse);
      expect(board.isValidCell(cell(1, 6)), isTrue);
      expect(board.isValidCell(cell(1, 7)), isFalse);
      expect(board.isValidCell(const HexCell(0, -1)), isFalse);
    });

    test('place, read and remove bubbles', () {
      final board = BubbleBoard(columns: 8)..place(cell(0, 0), BubbleColor.red);
      expect(board.bubbleAt(cell(0, 0)), BubbleColor.red);
      expect(board.isOccupied(cell(0, 0)), isTrue);
      expect(board.bottomRow, 0);
      expect(board.remove(cell(0, 0)), BubbleColor.red);
      expect(board.isEmpty, isTrue);
      expect(board.bottomRow, -1);
    });

    test('matchGroup finds connected same-color bubbles across rows', () {
      final board = BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red)
        ..place(cell(2, 0), BubbleColor.red)
        ..place(cell(0, 1), BubbleColor.blue);
      expect(
        board.matchGroup(cell(1, 0)),
        {cell(0, 0), cell(1, 0), cell(2, 0)},
      );
      expect(board.matchGroup(cell(0, 1)), {cell(0, 1)});
      expect(board.matchGroup(cell(5, 5)), isEmpty);
    });

    test('floatingBubbles returns groups disconnected from the ceiling', () {
      final board = BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.blue)
        ..place(cell(3, 3), BubbleColor.green)
        ..place(cell(3, 4), BubbleColor.green);
      expect(board.floatingBubbles(), {cell(3, 3), cell(3, 4)});
    });

    test('removing an anchor makes its subtree float', () {
      final board = BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.blue);
      expect(board.floatingBubbles(), isEmpty);
      board.remove(cell(0, 0));
      expect(board.floatingBubbles(), {cell(1, 0)});
    });

    test('emptyNeighbors excludes occupied and out-of-bounds cells', () {
      final board = BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(0, 1), BubbleColor.blue);
      final neighbors = board.emptyNeighbors(cell(0, 0));
      expect(neighbors, [cell(1, 0)]);
    });
  });
}
