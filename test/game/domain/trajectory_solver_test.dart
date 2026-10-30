// 🎯 Dart imports:
import 'dart:math';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);

void main() {
  // columns: 8, radius: 10 → board width 160, row 0 centers at
  // x = 10, 30, …, 150, y = 10.
  const geometry = BoardGeometry(columns: 8, bubbleRadius: 10);
  const solver = TrajectorySolver(geometry: geometry);

  group('TrajectorySolver', () {
    test(
      'straight shot on an empty board lands in the nearest ceiling cell',
      () {
        final result = solver.solve(
          board: BubbleBoard(columns: 8),
          origin: const Point(70, 300),
          direction: const Point(0, -1),
        );
        expect(result, isNotNull);
        expect(result!.landingCell, cell(0, 3));
        expect(result.contactCell, isNull);
        expect(result.path.last, geometry.center(cell(0, 3)));
      },
    );

    test('is deterministic for identical input', () {
      final board = BubbleBoard(columns: 8)..place(cell(0, 3), BubbleColor.red);
      final a = solver.solve(
        board: board,
        origin: const Point(72, 200),
        direction: const Point(0.1, -1),
      );
      final b = solver.solve(
        board: board,
        origin: const Point(72, 200),
        direction: const Point(0.1, -1),
      );
      expect(a!.landingCell, b!.landingCell);
      expect(a.path, b.path);
    });

    test('reflects off the left wall before reaching the ceiling', () {
      final result = solver.solve(
        board: BubbleBoard(columns: 8),
        origin: const Point(35, 100),
        direction: const Point(-1, -1),
      );
      expect(result, isNotNull);
      // Bounce at x = bubbleRadius, then travels up-right to x = 75.
      expect(result!.path[1].x, closeTo(10, 1e-9));
      expect(result.path[1].y, closeTo(75, 1e-9));
      expect(result.landingCell, cell(0, 3));
    });

    test('snaps to the empty neighbor closest to the contact point', () {
      final board = BubbleBoard(columns: 8)..place(cell(0, 3), BubbleColor.red);
      final result = solver.solve(
        board: board,
        origin: const Point(72, 200),
        direction: const Point(0, -1),
      );
      // Contact slightly right of the occupied bubble → snaps below-right.
      expect(result!.landingCell, cell(1, 3));
      expect(result.contactCell, cell(0, 3));
    });

    test('rejects shots not aimed upward', () {
      final board = BubbleBoard(columns: 8);
      expect(
        solver.solve(
          board: board,
          origin: const Point(80, 200),
          direction: const Point(1, 0),
        ),
        isNull,
      );
      expect(
        solver.solve(
          board: board,
          origin: const Point(80, 200),
          direction: const Point(0, 1),
        ),
        isNull,
      );
      expect(
        solver.solve(
          board: board,
          origin: const Point(80, 200),
          direction: const Point(0, 0),
        ),
        isNull,
      );
    });

    // Real game geometry: 8 columns at radius 30 (480 wide), shooter at
    // (240, 720). Guards the shallow-aim dead zone — before the aim clamp,
    // angles within ~6° of horizontal (~14° on a sparse board) exhausted the
    // bounce budget and returned null, so the guide vanished and firing was
    // a silent no-op.
    test('every upward aim resolves, full board and sparse board alike', () {
      const gameGeometry = BoardGeometry(columns: 8, bubbleRadius: 30);
      const gameSolver = TrajectorySolver(geometry: gameGeometry);
      const origin = Point<double>(240, 720);

      final full = BubbleBoard(columns: 8);
      for (var row = 0; row < 5; row++) {
        for (var col = 0; col < full.rowWidth(row); col++) {
          full.place(cell(row, col), BubbleColor.red);
        }
      }
      final sparse = BubbleBoard(columns: 8)..place(cell(0, 0), BubbleColor.red);

      for (final board in [full, sparse]) {
        for (var degrees = 1; degrees <= 179; degrees++) {
          final radians = degrees * pi / 180;
          final result = gameSolver.solve(
            board: board,
            origin: origin,
            direction: Point(cos(radians), -sin(radians)),
          );
          expect(result, isNotNull, reason: 'aim at $degrees° returned null');
          expect(board.isOccupied(result!.landingCell), isFalse);
        }
      }
    });

    test('aims flatter than maxAimAngle collapse onto the clamp', () {
      final board = BubbleBoard(columns: 8);
      const shallow = Point<double>(1, -0.01);
      final clamped = Point<double>(
        sin(TrajectorySolver.maxAimAngle),
        -cos(TrajectorySolver.maxAimAngle),
      );

      final a = solver.solve(
        board: board,
        origin: const Point(80, 200),
        direction: shallow,
      );
      final b = solver.solve(
        board: board,
        origin: const Point(80, 200),
        direction: clamped,
      );

      expect(a, isNotNull);
      expect(a!.landingCell, b!.landingCell);
      expect(a.path, b.path);
    });
  });

  group('BoardGeometry', () {
    test('centers follow hex packing with odd rows shifted right', () {
      expect(geometry.center(cell(0, 0)), const Point<double>(10, 10));
      expect(geometry.center(cell(0, 3)), const Point<double>(70, 10));
      final oddRow = geometry.center(cell(1, 0));
      expect(oddRow.x, closeTo(20, 1e-9));
      expect(oddRow.y, closeTo(10 + 10 * sqrt(3), 1e-9));
    });

    test('nearestCell inverts center for every valid cell', () {
      for (var row = 0; row < 6; row++) {
        for (var col = 0; col < geometry.rowWidth(row); col++) {
          final c = cell(row, col);
          expect(geometry.nearestCell(geometry.center(c)), c);
        }
      }
    });
  });
}
