// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

void main() {
  group('HexCell', () {
    test('fromRowCol converts odd-r offset to axial and back', () {
      const cases = [(0, 0), (0, 3), (1, 0), (1, 2), (2, 0), (3, 4), (7, 6)];
      for (final (row, col) in cases) {
        final cell = HexCell.fromRowCol(row: row, col: col);
        expect(cell.row, row);
        expect(cell.col, col);
      }
    });

    test('row 2 col 0 maps to negative q', () {
      final cell = HexCell.fromRowCol(row: 2, col: 0);
      expect(cell.q, -1);
      expect(cell.r, 2);
    });

    test('has six axial neighbors', () {
      const cell = HexCell(0, 0);
      expect(cell.neighbors, hasLength(6));
      expect(
        cell.neighbors,
        containsAll(const [
          HexCell(1, 0),
          HexCell(1, -1),
          HexCell(0, -1),
          HexCell(-1, 0),
          HexCell(-1, 1),
          HexCell(0, 1),
        ]),
      );
    });

    test('supports value equality', () {
      expect(const HexCell(2, 3), const HexCell(2, 3));
      expect(const HexCell(2, 3).hashCode, const HexCell(2, 3).hashCode);
      expect(const HexCell(2, 3), isNot(const HexCell(3, 2)));
    });
  });
}
