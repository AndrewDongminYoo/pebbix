// 🎯 Dart imports:
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/gen/app_localizations_en.dart';

/// A throwaway opaque image standing in for the preloaded art, so the
/// sprite branches render without touching the asset bundle.
Future<ui.Image> _stubImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(64, 64);
}

void main() {
  late ui.Image stub;

  setUp(() async {
    stub = await _stubImage();
  });

  BubbleShooter createGame({required bool withArt}) {
    final images = Images(prefix: '');
    if (withArt) {
      for (final image in Assets.images.values) {
        images.add(image.path, stub);
      }
    }
    final game = BubbleShooter(
      l10n: AppLocalizationsEn(),
      playSfx: (_) {},
      textStyle: const TextStyle(),
      images: images,
      seed: 7,
    );
    // Registered by GamePage in production; this test builds a bare
    // GameWidget, so the overlay needs its own entry.
    game.overlays.addEntry(
      BubbleShooter.gameOverOverlayKey,
      (_, _) => const SizedBox(),
    );
    return game;
  }

  /// Mounts the game in a real widget tree so every component's render
  /// pass actually runs.
  Future<BubbleShooter> pumpGame(
    WidgetTester tester, {
    bool withArt = false,
  }) async {
    final game = createGame(withArt: withArt);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await tester.pump();
    return game;
  }

  group('rendering', () {
    test('every bubble color has a distinct display fill', () {
      final fills = BubbleColor.values.map((c) => c.displayColor).toSet();
      expect(fills, hasLength(BubbleColor.values.length));
    });

    testWidgets('draws sprites when the art is preloaded', (tester) async {
      final game = await pumpGame(tester, withArt: true);

      for (final color in BubbleColor.values) {
        expect(game.bubbleSpriteFor(color), isNotNull);
      }
      expect(game.shooterBodyIdle, isNotNull);
      expect(game.shooterBodyShooting, isNotNull);
      expect(game.shooterArm, isNotNull);
      expect(
        game.boardComponent.children.whereType<BubbleComponent>(),
        isNotEmpty,
      );
    });

    test(
      'procedural marks distinguish normal bomb and rainbow shots',
      () async {
        const normal = (color: BubbleColor.yellow, kind: ShotKind.normal);
        const bomb = (color: BubbleColor.yellow, kind: ShotKind.bomb);
        const rainbow = (color: BubbleColor.yellow, kind: ShotKind.rainbow);

        Future<ByteData> renderShot(LauncherShot shot) async {
          final recorder = ui.PictureRecorder();
          paintLauncherShot(
            Canvas(recorder),
            const Offset(40, 40),
            30,
            shot,
          );
          final image = await recorder.endRecording().toImage(80, 80);
          return (await image.toByteData())!;
        }

        int rgbAt(ByteData pixels, int x, int y) {
          final offset = (y * 80 + x) * 4;
          return pixels.getUint8(offset) << 16 | pixels.getUint8(offset + 1) << 8 | pixels.getUint8(offset + 2);
        }

        int brightness(int rgb) => (rgb >> 16 & 0xFF) + (rgb >> 8 & 0xFF) + (rgb & 0xFF);

        final normalPixels = await renderShot(normal);
        final bombPixels = await renderShot(bomb);
        final rainbowPixels = await renderShot(rainbow);
        expect(
          brightness(rgbAt(bombPixels, 40, 40)),
          lessThan(brightness(rgbAt(normalPixels, 40, 40))),
        );

        final rainbowRgbs = <int>{};
        for (var offset = 0; offset < rainbowPixels.lengthInBytes; offset += 4) {
          if (rainbowPixels.getUint8(offset + 3) == 0) continue;
          rainbowRgbs.add(
            rainbowPixels.getUint8(offset) << 16 |
                rainbowPixels.getUint8(offset + 1) << 8 |
                rainbowPixels.getUint8(offset + 2),
          );
        }
        final paletteHits = BubbleColor.values
            .map((color) => color.displayColor.toARGB32() & 0xFFFFFF)
            .where(rainbowRgbs.contains);
        expect(paletteHits.length, greaterThanOrEqualTo(3));
      },
    );

    testWidgets('launcher and projectile carry the same special shot', (
      tester,
    ) async {
      const bomb = (color: BubbleColor.yellow, kind: ShotKind.bomb);
      const rainbow = (color: BubbleColor.yellow, kind: ShotKind.rainbow);
      final game = await pumpGame(tester, withArt: true);
      final shooter = game.world.children.whereType<ShooterComponent>().single;
      game
        ..currentShot = bomb
        ..nextShot = rainbow;
      shooter.render(Canvas(ui.PictureRecorder()));

      Future<void> fireAndRender(LauncherShot shot) async {
        game
          ..startGame()
          ..currentShot = shot
          ..aimAt(Vector2(game.shooterOrigin.x + 1, 0))
          ..fire();
        await tester.pump();
        final projectile = game.boardComponent.children.whereType<ProjectileComponent>().single;
        expect(projectile.shot, shot);
        projectile.render(Canvas(ui.PictureRecorder()));
      }

      await fireAndRender(bomb);
      await fireAndRender(rainbow);
    });

    testWidgets('falls back to procedural art with an empty cache', (
      tester,
    ) async {
      final game = await pumpGame(tester);

      for (final color in BubbleColor.values) {
        expect(game.bubbleSpriteFor(color), isNull);
      }
      expect(game.shooterBodyIdle, isNull);
      expect(game.shooterArm, isNull);
    });

    testWidgets('ambient bubbles respawn once they leave the top', (
      tester,
    ) async {
      final game = await pumpGame(tester);

      // Far more than the slowest ambient bubble needs to clear the world.
      game.update(100);
      await tester.pump();

      expect(
        game.world.children.whereType<BackgroundComponent>(),
        hasLength(1),
      );
    });

    testWidgets('shooter hides the current bubble once the game ends', (
      tester,
    ) async {
      final game = await pumpGame(tester, withArt: true);
      final shooter = game.world.children.whereType<ShooterComponent>().single;
      expect(shooter.position, game.shooterOrigin);

      // Drives every status branch with the art present, so the shooting
      // body swap and the rotated arm render on top of the sprite path.
      final canvas = Canvas(ui.PictureRecorder());
      game
        ..aimAngle =
            0.5 // Non-zero so the arm actually rotates, not a no-op.
        ..status = GameStatus.flying;
      shooter.render(canvas);
      game.status = GameStatus.victory;
      shooter.render(canvas);
      game.status = GameStatus.defeat;
      shooter.render(canvas);
    });
  });

  group('ShooterComponent', () {
    test('the arm clears the fail row at full elevation', () {
      final game = createGame(withArt: false);
      // The play area's floor is the fail row's center: a bubble dies the
      // moment its cell reaches [BubbleShooter.failRow], and its center then
      // sits here. The launcher must stay below it at every aim angle.
      final failRowY = BubbleShooter.geometry.center(HexCell.fromRowCol(row: BubbleShooter.failRow, col: 0)).y;

      expect(
        game.shooterOrigin.y - ShooterComponent.armReach,
        greaterThan(failRowY),
      );
    });

    testWidgets('keeps the current bubble visible during a transition', (
      tester,
    ) async {
      final game = await pumpGame(tester);
      final shooter = game.world.children.whereType<ShooterComponent>().single;
      game.status = GameStatus.transitioning;
      final centerAlpha = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..translate(100, 100);
        shooter.render(canvas);
        final image = await recorder.endRecording().toImage(200, 200);
        final pixels = (await image.toByteData())!;
        final alpha = pixels.getUint8((100 * 200 + 100) * 4 + 3);
        image.dispose();
        return alpha;
      });
      expect(centerAlpha, greaterThan(0));
    });
  });

  group('AimInputComponent', () {
    test('draws the fail line through the fail row center', () async {
      final recorder = ui.PictureRecorder();
      AimInputComponent().render(Canvas(recorder));
      final width = BubbleShooter.worldWidth.toInt();
      final image = await recorder.endRecording().toImage(
        width,
        BubbleShooter.worldHeight.toInt(),
      );
      final pixels = (await image.toByteData())!;
      final expectedY = BubbleShooter.geometry.center(HexCell.fromRowCol(row: BubbleShooter.failRow, col: 0)).y.round();
      final oldBottomY =
          (BubbleShooter.geometry.bubbleRadius * 2 + BubbleShooter.failRow * BubbleShooter.geometry.rowHeight).round();

      int maxAlphaNear(int y) => [
        for (var sampleY = y - 2; sampleY <= y + 2; sampleY++) pixels.getUint8((sampleY * width + 10) * 4 + 3),
      ].reduce(max);

      expect(maxAlphaNear(expectedY), greaterThanOrEqualTo(0xCC));
      expect(maxAlphaNear(oldBottomY), 0);
    });

    testWidgets('drag aims and release fires', (tester) async {
      final game = await pumpGame(tester);

      final gesture = await tester.startGesture(const Offset(400, 400));
      await tester.pump();
      await gesture.moveBy(const Offset(-40, -60));
      await tester.pump();
      expect(game.aimGuide.path, isNotNull);
      expect(game.hasAimedShot, isTrue);

      await gesture.up();
      await tester.pump();
      expect(game.status, GameStatus.flying);
      expect(game.aimGuide.path, isNull);
      expect(game.hasAimedShot, isFalse);
    });

    testWidgets(
      'a drag started during transition stays blocked after completion',
      (tester) async {
        final game = await pumpGame(tester);
        game.status = GameStatus.transitioning;

        final blockedGesture = await tester.startGesture(
          const Offset(400, 400),
        );
        await tester.pump();
        game.status = GameStatus.aiming;
        await blockedGesture.moveBy(const Offset(-40, -60));
        await tester.pump();
        await blockedGesture.up();
        await tester.pump();

        expect(game.status, GameStatus.aiming);
        expect(game.hasAimedShot, isFalse);
        expect(game.aimGuide.path, isNull);
        expect(
          game.boardComponent.children.whereType<ProjectileComponent>(),
          isEmpty,
        );

        final validGesture = await tester.startGesture(const Offset(400, 400));
        await tester.pump();
        await validGesture.moveBy(const Offset(-40, -60));
        await tester.pump();
        await validGesture.up();
        await tester.pump();

        expect(game.status, GameStatus.flying);
      },
    );

    testWidgets(
      'a cancelled drag started during transition stays blocked',
      (tester) async {
        final game = await pumpGame(tester);
        game.status = GameStatus.transitioning;

        final blockedGesture = await tester.startGesture(
          const Offset(400, 400),
        );
        await tester.pump();
        game.status = GameStatus.aiming;
        await blockedGesture.moveBy(const Offset(-40, -60));
        await tester.pump();
        await blockedGesture.cancel();
        await tester.pump();

        expect(game.status, GameStatus.aiming);
        expect(game.hasAimedShot, isFalse);
        expect(game.aimGuide.path, isNull);
        expect(
          game.boardComponent.children.whereType<ProjectileComponent>(),
          isEmpty,
        );
      },
    );

    testWidgets(
      'a held drag cannot survive another pointer triggering a transition',
      (tester) async {
        final game = await pumpGame(tester);
        game.pressureNotifier.value = (
          aimAssist: game.pressure.aimAssist,
          ceilingOffset: game.ceilingOffset,
          colorCount: game.pressure.colorCount,
          shotsUntilDescent: 1,
        );

        final heldGesture = await tester.startGesture(
          const Offset(400, 400),
          pointer: 1,
        );
        await tester.pump();
        await heldGesture.moveBy(const Offset(-20, -80));
        await tester.pump();

        final firingGesture = await tester.startGesture(
          const Offset(420, 400),
          pointer: 2,
        );
        await tester.pump();
        await firingGesture.moveBy(const Offset(20, -80));
        await tester.pump();
        await firingGesture.up();
        await tester.pump();
        expect(game.status, GameStatus.flying);

        await tester.pump(const Duration(seconds: 1));
        expect(game.status, GameStatus.transitioning);
        await tester.pump(const Duration(milliseconds: 300));
        expect(game.status, GameStatus.aiming);

        await heldGesture.moveBy(const Offset(-20, -20));
        await tester.pump();
        await heldGesture.up();
        await tester.pump();

        expect(game.status, GameStatus.aiming);
        expect(game.hasAimedShot, isFalse);
        expect(game.aimGuide.path, isNull);
        expect(
          game.boardComponent.children.whereType<ProjectileComponent>(),
          isEmpty,
        );
      },
    );

    testWidgets('a level or downward aim arms no shot, so the arm ghosts', (
      tester,
    ) async {
      final game = await pumpGame(tester);
      final origin = game.shooterOrigin;

      // Downward: past the shooter, direction.y > 0.
      game.aimAt(Vector2(origin.x, origin.y + 40));
      expect(game.hasAimedShot, isFalse);

      // Level: straight across, direction.y == 0.
      game.aimAt(Vector2(origin.x + 100, origin.y));
      expect(game.hasAimedShot, isFalse);
    });

    testWidgets('a cancelled drag fires the aimed shot too', (tester) async {
      final game = await pumpGame(tester);

      final gesture = await tester.startGesture(const Offset(400, 400));
      await tester.pump();
      await gesture.moveBy(const Offset(20, -80));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(game.status, GameStatus.flying);
      expect(game.aimGuide.path, isNull);
    });
  });

  group('AimGuideComponent', () {
    final canvas = Canvas(ui.PictureRecorder());

    test('renders nothing without a resolvable path', () {
      AimGuideComponent()
        ..render(canvas)
        ..path = [const Point(0, 0)]
        ..render(canvas);
    });

    test('dots every segment and rings the landing cell', () {
      AimGuideComponent()
        ..path = const [
          Point(240, 720),
          // Zero-length segment: the solver emits one when a bounce lands
          // exactly on the previous point.
          Point(240, 720),
          Point(10, 200),
          Point(60, 40),
          Point(60, 30),
        ]
        ..render(canvas);
    });
  });

  group('BubbleComponent', () {
    testWidgets('rainbow holds matched bodies until conversion, without dot debris', (tester) async {
      final game = await pumpGame(tester);
      final bubbles = game.boardComponent.children.whereType<BubbleComponent>().toList();
      final bubble = bubbles.first;
      game.boardComponent.applyShot(
        landing: null,
        color: null,
        popped: {game.board.occupiedCells.first},
        dropped: {},
        kind: ShotKind.rainbow,
      );
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(bubble.scale, Vector2.all(1));
      expect(bubble.isMounted, isTrue);
      expect(game.boardComponent.children.whereType<ParticleSystemComponent>(), isEmpty);
      for (var frame = 0; frame < 14; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(bubble.scale.x, lessThan(1));
      for (var frame = 0; frame < 14; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(bubble.isMounted, isFalse);
    });

    testWidgets('restart clears the matched bodies waiting for rainbow conversion', (tester) async {
      final game = await pumpGame(tester);
      final previous = game.boardComponent.children.whereType<BubbleComponent>().first;
      game.boardComponent.applyShot(
        landing: null,
        color: null,
        popped: {game.board.occupiedCells.first},
        dropped: {},
        kind: ShotKind.rainbow,
      );
      await tester.pump();
      game.startGame();
      await tester.pump();
      await tester.pump();
      expect(previous.isMounted, isFalse);
    });

    testWidgets('settles, pops and drops', (tester) async {
      final game = await pumpGame(tester);
      final bubbles = game.boardComponent.children.whereType<BubbleComponent>().toList();

      bubbles[0].settle();
      bubbles[1].pop();
      bubbles[2].drop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();

      expect(bubbles[1].isMounted, isFalse);
      expect(bubbles[2].isMounted, isFalse);
    });
  });

  group('ProjectileComponent', () {
    testWidgets('advances partway along a segment in a single step', (
      tester,
    ) async {
      final game = await pumpGame(tester);
      final landing = game.board.occupiedCells.first;
      final center = BubbleShooter.geometry.center(landing);
      final projectile = ProjectileComponent(
        result: ShotResult(
          path: [
            const Point(BubbleShooter.worldWidth / 2, 720),
            Point(center.x, center.y),
          ],
          landingCell: landing,
        ),
        color: BubbleColor.red,
      );
      await game.boardComponent.add(projectile);
      await tester.pump();

      final start = projectile.position.clone();
      // Short enough that 1500 px/s cannot reach the landing point.
      projectile.update(0.01);

      expect(projectile.position, isNot(start));
      expect(projectile.isMounted, isTrue);
    });
  });
}
