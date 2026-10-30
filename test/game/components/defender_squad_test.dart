// 🎯 Dart imports:
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/gen/app_localizations_en.dart';

void main() {
  BubbleShooter createGame() {
    final game = BubbleShooter(
      l10n: AppLocalizationsEn(),
      playSfx: (_) {},
      textStyle: const TextStyle(),
      images: Images(prefix: ''),
      seed: 7,
    );
    game.overlays.addEntry(BubbleShooter.gameOverOverlayKey, (_, _) => const SizedBox());
    return game;
  }

  HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);

  ShotResult landingAt(HexCell landing) {
    final center = BubbleShooter.geometry.center(landing);
    return ShotResult(
      path: [const Point(240, 970), center, center],
      landingCell: landing,
    );
  }

  testWithGame('real fire starts carrying the actual next shot without consuming it', createGame, (game) async {
    const next = (color: BubbleColor.purple, kind: ShotKind.rainbow);
    game
      ..nextShot = next
      ..aimAt(Vector2(240, 0))
      ..fire();
    expect(game.status, GameStatus.flying);
    game.update(0.1);
    expect(game.defenderMotion.bubblePosition, inExclusiveRange(0, 1));
    expect(game.nextShot, next);
    for (var i = 0; i < 20 && game.status == GameStatus.flying; i++) {
      game.update(0.05);
    }
    expect(game.currentShot, next);
    game
      ..aimAt(Vector2(240, 0))
      ..fire();
    expect(game.status, GameStatus.flying, reason: 'Returning animation must not delay input');
  });

  testWithGame('a rejected aim does not trigger loading or recoil', createGame, (game) async {
    game
      ..aimAt(Vector2(240, 1040))
      ..fire()
      ..update(0.1);
    expect(game.status, GameStatus.aiming);
    expect(game.defenderMotion.loaderPose, 0);
    expect(game.defenderMotion.mechanicPose(game.aimAngle), 0);
  });

  testWithGame('a scored match triggers the crew and restart cancels it', createGame, (game) async {
    game
      ..board = (BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red)
        ..place(cell(0, 7), BubbleColor.blue))
      ..boardComponent.syncBoard()
      ..currentColor = BubbleColor.red
      ..onShotLanded(landingAt(cell(2, 0)))
      ..update(0.25);
    expect(game.score, 30);
    expect(game.defenderMotion.cheerLift(), greaterThan(0));
    game.startGame();
    expect(game.defenderMotion.cheerLift(), 0);
    expect(game.defenderMotion.loaderPose, 0);
    expect(game.defenderMotion.loaderPosition, 1);
  });

  testWithGame('victory celebrates and defeat stops the crew until revive', createGame, (game) async {
    game
      ..board = (BubbleBoard(columns: 8)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red))
      ..boardComponent.syncBoard()
      ..currentColor = BubbleColor.red
      ..onShotLanded(landingAt(cell(2, 0)))
      ..update(0.25);
    expect(game.status, GameStatus.victory);
    expect(game.defenderMotion.cheerLift(), greaterThan(0));

    game
      ..startGame()
      ..board = (BubbleBoard(columns: 8)..place(cell(0, 7), BubbleColor.blue))
      ..boardComponent.syncBoard()
      ..onShotLanded(landingAt(cell(16, 0)))
      ..update(0.25);
    expect(game.status, GameStatus.defeat);
    expect(game.defenderMotion.idleLift(), 0);
    expect(game.revive(), isTrue);
    game.update(0.1);
    expect(game.defenderMotion.idleLift(), greaterThan(0));
  });

  testWidgets('legacy body remains visible when the squad atlas is unavailable', (tester) async {
    final game = createGame();
    await tester.runAsync(
      () => game.images.loadAll(
        Assets.images.values
            .where((asset) => asset.path != Assets.images.defenderSquad.path)
            .map((asset) => asset.path)
            .toList(),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await tester.pump();
    final idle = await _captureSquad(tester, game);
    expect(idle.indexed.any((entry) => entry.$1 % 4 == 3 && entry.$2 > 0), isTrue);
    game
      ..aimAt(Vector2(240, 0))
      ..fire();
    expect(await _captureSquad(tester, game), isNot(orderedEquals(idle)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real sprite pixels animate, freeze when paused, and respect reduced motion', (tester) async {
    final game = createGame();
    await tester.runAsync(() => game.images.loadAll(Assets.images.values.map((asset) => asset.path).toList()));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await tester.pump();
    final initial = await _captureSquad(tester, game);
    game.update(0.8);
    final breathing = await _captureSquad(tester, game);
    expect(breathing, isNot(orderedEquals(initial)), reason: 'An idle pose swap must change the rendered crew');

    game.pauseEngine();
    await tester.pump(const Duration(seconds: 1));
    expect(await _captureSquad(tester, game), orderedEquals(breathing));

    game.defenderMotion.reducedMotion = true;
    final reduced = await _captureSquad(tester, game);
    game.update(3.45);
    expect(await _captureSquad(tester, game), orderedEquals(reduced));

    game.defenderMotion.reducedMotion = false;
    game
      ..aimAt(Vector2(80, 0))
      ..fire();
    final beforeCarry = await _captureSquad(tester, game);
    game.update(0.12);
    expect(await _captureSquad(tester, game), isNot(orderedEquals(beforeCarry)));
    await tester.pumpWidget(const SizedBox());
  });
}

Future<Uint8List> _captureSquad(WidgetTester tester, BubbleShooter game) async {
  final shooter = game.world.children.whereType<ShooterComponent>().single;
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    shooter.render(Canvas(recorder)..translate(240, 115));
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 190);
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    return bytes;
  }))!;
}
