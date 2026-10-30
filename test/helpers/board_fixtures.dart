// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';

/// Fills [col] from the ceiling down to the last row that still survives, so
/// the next bubble landing at [failingCell] loses the game.
///
/// Colours alternate so the stack never matches three and pops itself.
/// Pass the [ceilingOffset] the game will be at: defeat is
/// `bottomRow + ceilingOffset >= failRow`, so a descended ceiling needs a
/// shallower stack to reach it.
///
/// Derived from [BubbleShooter.failRow] on purpose: a test that hard-codes
/// the row silently stops testing a defeat the moment the fail line moves.
void fillBelowFailLine(
  BubbleBoard board, {
  int col = 0,
  int ceilingOffset = 0,
  int overshoot = 0,
}) {
  final landing = BubbleShooter.failRow - ceilingOffset + overshoot;
  for (var row = 0; row < landing; row++) {
    board.place(
      HexCell.fromRowCol(row: row, col: col),
      row.isEven ? BubbleColor.red : BubbleColor.blue,
    );
  }
}

/// The board-local cell whose occupation crosses the fail line at
/// [ceilingOffset] — the shot [fillBelowFailLine] leaves room for.
///
/// [overshoot] lands it that many rows *past* the line, which is what a test
/// needs when it wants the board still failing after `revive()` retreats the
/// ceiling by one. Both functions must be given the same values.
HexCell failingCell({int col = 0, int ceilingOffset = 0, int overshoot = 0}) => HexCell.fromRowCol(
  row: BubbleShooter.failRow - ceilingOffset + overshoot,
  col: col,
);
