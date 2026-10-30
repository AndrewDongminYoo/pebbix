// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/bubble_color.dart';
import 'package:bubble_shooter/game/domain/hex_cell.dart';

/// Mutable state of the bubble grid.
///
/// Even rows hold [columns] bubbles, odd rows one fewer (odd-r offset
/// layout). Row 0 is the ceiling; bubbles not connected to row 0 are
/// "floating" and fall.
class BubbleBoard {
  new({required this.columns, Map<HexCell, BubbleColor>? bubbles}) : _bubbles = {...?bubbles};

  /// Bubbles per even row; odd rows hold `columns - 1`.
  final int columns;

  final Map<HexCell, BubbleColor> _bubbles;

  int rowWidth(int row) => row.isOdd ? columns - 1 : columns;

  bool isValidCell(HexCell cell) => cell.r >= 0 && cell.col >= 0 && cell.col < rowWidth(cell.r);

  bool isOccupied(HexCell cell) => _bubbles.containsKey(cell);

  BubbleColor? bubbleAt(HexCell cell) => _bubbles[cell];

  Iterable<HexCell> get occupiedCells => _bubbles.keys;

  bool get isEmpty => _bubbles.isEmpty;

  /// The largest occupied row, or -1 on an empty board.
  int get bottomRow => _bubbles.keys.fold(-1, (max, cell) => cell.r > max ? cell.r : max);

  void place(HexCell cell, BubbleColor color) {
    assert(isValidCell(cell), 'cell $cell is outside the board');
    assert(!isOccupied(cell), 'cell $cell is already occupied');
    _bubbles[cell] = color;
  }

  BubbleColor? remove(HexCell cell) => _bubbles.remove(cell);

  /// Valid, unoccupied neighbors of [cell].
  List<HexCell> emptyNeighbors(HexCell cell) => [
    for (final n in cell.neighbors)
      if (isValidCell(n) && !isOccupied(n)) n,
  ];

  /// All occupied cells connected to [start] sharing its color, including
  /// [start] itself. Empty set if [start] is unoccupied.
  Set<HexCell> matchGroup(HexCell start) {
    final color = _bubbles[start];
    if (color == null) return {};
    return _flood([start], (cell) => _bubbles[cell] == color);
  }

  /// Occupied cells not connected to the ceiling (row 0) through other
  /// bubbles.
  Set<HexCell> floatingBubbles() {
    final anchored = _flood(
      [
        for (final cell in _bubbles.keys)
          if (cell.r == 0) cell,
      ],
      isOccupied,
    );
    return _bubbles.keys.toSet().difference(anchored);
  }

  Set<HexCell> _flood(List<HexCell> seeds, bool Function(HexCell) predicate) {
    final visited = <HexCell>{...seeds};
    final queue = [...seeds];
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      for (final n in cell.neighbors) {
        if (!visited.contains(n) && isValidCell(n) && predicate(n)) {
          visited.add(n);
          queue.add(n);
        }
      }
    }
    return visited;
  }
}
