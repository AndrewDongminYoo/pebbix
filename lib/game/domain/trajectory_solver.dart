// 🎯 Dart imports:
import 'dart:math';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/board_geometry.dart';
import 'package:bubble_shooter/game/domain/bubble_board.dart';
import 'package:bubble_shooter/game/domain/hex_cell.dart';

/// The fully resolved outcome of one shot: the polyline the projectile
/// travels (origin, wall bounce points, contact point, landing cell center)
/// and the cell it snaps into.
class ShotResult {
  const new({
    required this.path,
    required this.landingCell,
    this.contactCell,
  });

  final List<Point<double>> path;
  final HexCell landingCell;
  final HexCell? contactCell;
}

/// Deterministically resolves a shot before anything moves on screen.
///
/// Same board + same origin/direction always produce the same [ShotResult].
/// Rendering only animates along [ShotResult.path]; the board mutation
/// happens once, on arrival.
class TrajectorySolver {
  const new({required this.geometry});

  final BoardGeometry geometry;

  static const _maxBounces = 8;

  /// Widest angle from vertical a shot may take. A flatter ray ping-pongs
  /// across the board more than [_maxBounces] times before it reaches a
  /// bubble, so without this clamp shallow aims resolve to no shot at all
  /// and the input silently dies.
  static const double maxAimAngle = 75 * pi / 180;

  static final double _maxAimSin = sin(maxAimAngle);
  static final double _maxAimCos = cos(maxAimAngle);

  /// Returns null when the shot is invalid (not aimed upward) or the board
  /// has no empty cell at the contact point. Upward shots flatter than
  /// [maxAimAngle] are clamped to it rather than rejected.
  ShotResult? solve({
    required BubbleBoard board,
    required Point<double> origin,
    required Point<double> direction,
  }) {
    final length = direction.magnitude;
    if (length == 0) return null;
    var dx = direction.x / length;
    var dy = direction.y / length;
    if (dy >= 0) return null;
    if (dx.abs() > _maxAimSin) {
      dx = dx.isNegative ? -_maxAimSin : _maxAimSin;
      dy = -_maxAimCos;
    }

    final r = geometry.bubbleRadius;
    final minX = r;
    final maxX = geometry.width - r;
    var x = origin.x;
    var y = origin.y;
    final path = <Point<double>>[Point(x, y)];

    for (var bounce = 0; bounce <= _maxBounces; bounce++) {
      var tWall = double.infinity;
      if (dx < 0) {
        tWall = (minX - x) / dx;
      } else if (dx > 0) {
        tWall = (maxX - x) / dx;
      }

      var tHit = (r - y) / dy;
      HexCell? hitCell;
      for (final cell in board.occupiedCells) {
        final c = geometry.center(cell);
        final t = _rayCircleEntry(x - c.x, y - c.y, dx, dy, 2 * r);
        if (t != null && t < tHit) {
          tHit = t;
          hitCell = cell;
        }
      }

      if (tWall < tHit) {
        x += dx * tWall;
        y += dy * tWall;
        path.add(Point(x, y));
        dx = -dx;
        continue;
      }

      final contact = Point(x + dx * tHit, y + dy * tHit);
      final landing = _snap(board, contact, hitCell);
      if (landing == null) return null;
      path
        ..add(contact)
        ..add(geometry.center(landing));
      return ShotResult(
        path: path,
        landingCell: landing,
        contactCell: hitCell,
      );
    }
    return null;
  }

  /// Smallest positive t where the ray (relative origin, unit direction)
  /// enters a circle of [radius] centered at the relative origin's frame.
  double? _rayCircleEntry(
    double ox,
    double oy,
    double dx,
    double dy,
    double radius,
  ) {
    final b = 2 * (ox * dx + oy * dy);
    final c = ox * ox + oy * oy - radius * radius;
    final disc = b * b - 4 * c;
    if (disc < 0) return null;
    final t = (-b - sqrt(disc)) / 2;
    return t > 0 ? t : null;
  }

  HexCell? _snap(BubbleBoard board, Point<double> contact, HexCell? hitCell) {
    final candidates = hitCell != null
        ? board.emptyNeighbors(hitCell)
        : [
            for (var col = 0; col < board.rowWidth(0); col++)
              if (!board.isOccupied(HexCell.fromRowCol(row: 0, col: col))) HexCell.fromRowCol(row: 0, col: col),
          ];
    if (candidates.isEmpty) return null;
    var best = candidates.first;
    var bestDistance = geometry.center(best).squaredDistanceTo(contact);
    for (final cell in candidates.skip(1)) {
      final d = geometry.center(cell).squaredDistanceTo(contact);
      if (d < bestDistance) {
        best = cell;
        bestDistance = d;
      }
    }
    return best;
  }
}
