// 🎯 Dart imports:
import 'dart:math';

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/aim_assist_notice_component.dart';
import 'package:bubble_shooter/game/components/score_callout_component.dart';
import 'package:bubble_shooter/game/components/special_shot_effect_component.dart';
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/gen/app_localizations_en.dart';

import '../helpers/helpers.dart';

/// Cues the run under test fired, in order. Reset when the game is built,
/// so each test reads only its own.
final firedCues = <String>[];

HexCell cell(int row, int col) => HexCell.fromRowCol(row: row, col: col);

/// A minimal direct-hit shot result onto [landing] with no wall bounces.
ShotResult shotTo(HexCell landing) {
  final center = BubbleShooter.geometry.center(landing);
  return ShotResult(
    path: [
      const Point(BubbleShooter.worldWidth / 2, 720),
      Point(center.x, center.y),
      Point(center.x, center.y),
    ],
    landingCell: landing,
  );
}

/// Swaps in a near-empty board, then lands [count] shots on row 0 in
/// alternating colors so none of them ever forms a three-match. Advances the
/// pressure loop exactly [count] times without tripping victory or defeat.
///
/// The board reset is why chained calls work at all: row 0 only holds
/// [BubbleShooter.columns] cells and `BubbleBoard.place` rejects an occupied
/// one, so board state deliberately does *not* accumulate between calls.
void resetAndLandMisses(
  BubbleShooter game,
  int count, {
  bool completeTransitions = true,
}) {
  game.board = BubbleBoard(columns: BubbleShooter.columns)..place(cell(0, 7), BubbleColor.purple);
  game.boardComponent.syncBoard();

  for (var index = 0; index < count; index++) {
    game
      ..currentColor = index.isEven ? BubbleColor.red : BubbleColor.blue
      ..onShotLanded(shotTo(cell(0, index)));
    if (completeTransitions && game.status == GameStatus.transitioning) {
      game
        ..update(0)
        ..update(0.3);
    }
  }
}

void main() {
  BubbleShooter createGame({int seed = 42}) {
    firedCues.clear();
    final game = BubbleShooter(
      l10n: AppLocalizationsEn(),
      playSfx: firedCues.add,
      textStyle: const TextStyle(),
      images: Images(prefix: ''),
      seed: seed,
    );
    // Registered by GameWidget in production; tests run without one.
    game.overlays.addEntry(
      BubbleShooter.gameOverOverlayKey,
      (_, _) => const SizedBox(),
    );
    return game;
  }

  group('BubbleShooter', () {
    testWithGame('starts with a readable seeded formation', createGame, (
      game,
    ) async {
      expect(game.status, GameStatus.aiming);
      final fullBandCount = List.generate(
        BubbleShooter.startRows,
        game.board.rowWidth,
      ).reduce((a, b) => a + b);
      expect(
        game.board.occupiedCells.length,
        lessThan(fullBandCount),
      );
      expect(game.board.bottomRow, BubbleShooter.startRows - 1);
      expect(game.board.floatingBubbles(), isEmpty);
      expect(game.score, 0);
      expect(game.pressure.shotsUntilDescent, BubbleShooter.shotsPerDescent);
    });

    testWithGame(
      'same seed regenerates the same board on restart',
      createGame,
      (game) async {
        final before = {
          for (final c in game.board.occupiedCells) c: game.board.bubbleAt(c),
        };
        final firstColor = game.currentColor;
        game.startGame();
        final after = {
          for (final c in game.board.occupiedCells) c: game.board.bubbleAt(c),
        };
        expect(after, before);
        expect(game.currentColor, firstColor);
      },
    );

    testWithGame(
      'same seed reproduces special queue and final state',
      () => createGame(seed: 7),
      (game) async {
        Map<HexCell, BubbleColor> boardSnapshot() => {
          for (final occupied in game.board.occupiedCells) occupied: game.board.bubbleAt(occupied)!,
        };

        void landControlledShot() {
          game
            ..board = (BubbleBoard(columns: BubbleShooter.columns)
              ..place(cell(0, 0), BubbleColor.red)
              ..place(cell(0, 7), BubbleColor.blue))
            ..boardComponent.syncBoard()
            ..onShotLanded(shotTo(cell(1, 3)));
        }

        final opening = boardSnapshot();
        final initialCurrent = game.currentShot;
        final initialNext = game.nextShot;
        final currentShots = <LauncherShot>[];
        final nextShots = <LauncherShot>[];
        final scores = <int>[];
        final pressures = <PressureState>[];
        final boards = <Map<HexCell, BubbleColor>>[];

        for (var turn = 0; turn < 20; turn++) {
          landControlledShot();
          currentShots.add(game.currentShot);
          nextShots.add(game.nextShot);
          scores.add(game.score);
          pressures.add(game.pressure);
          boards.add(boardSnapshot());
        }
        final drawnShots = [initialCurrent, initialNext, ...nextShots];
        expect(drawnShots, const <LauncherShot>[
          (color: BubbleColor.blue, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.bomb),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.bomb),
          (color: BubbleColor.purple, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.purple, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.green, kind: ShotKind.normal),
          (color: BubbleColor.orange, kind: ShotKind.normal),
          (color: BubbleColor.yellow, kind: ShotKind.normal),
          (color: BubbleColor.purple, kind: ShotKind.rainbow),
        ]);

        game.startGame();
        expect(boardSnapshot(), opening);
        expect(game.currentShot, initialCurrent);
        expect(game.nextShot, initialNext);

        for (var turn = 0; turn < 20; turn++) {
          landControlledShot();
          expect(game.currentShot, currentShots[turn]);
          expect(game.nextShot, nextShots[turn]);
          expect(game.score, scores[turn]);
          expect(game.pressure, pressures[turn]);
          expect(boardSnapshot(), boards[turn]);
        }
      },
    );

    testWithGame(
      'aim, fire and land completes one full shot cycle',
      createGame,
      (game) async {
        game.aimAt(Vector2(game.shooterOrigin.x + 1, 0));
        expect(game.aimGuide.path, isNotNull);

        game.fire();
        expect(game.status, GameStatus.flying);

        for (var i = 0; i < 10 && game.status == GameStatus.flying; i++) {
          game.update(0.5);
        }
        expect(game.status, isNot(GameStatus.flying));
        expect(
          game.pressure.shotsUntilDescent,
          BubbleShooter.shotsPerDescent - 1,
        );
      },
    );

    testWithGame('fire without a valid aim does nothing', createGame, (
      game,
    ) async {
      game
        ..aimAt(Vector2(0, BubbleShooter.worldHeight))
        ..fire();
      expect(game.status, GameStatus.aiming);
      expect(game.pressure.shotsUntilDescent, BubbleShooter.shotsPerDescent);
    });

    testWithGame(
      'landing a third same-color bubble pops and scores',
      createGame,
      (game) async {
        final board = BubbleBoard(columns: BubbleShooter.columns)
          ..place(cell(0, 0), BubbleColor.red)
          ..place(cell(1, 0), BubbleColor.red)
          ..place(cell(0, 1), BubbleColor.blue);
        game
          ..board = board
          ..boardComponent.syncBoard()
          ..currentColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(2, 0)));

        expect(game.board.occupiedCells, [cell(0, 1)]);
        expect(game.score, 30);
        expect(game.status, GameStatus.aiming);
        expect(firedCues, [Assets.audio.pop]);
      },
    );

    testWithGame(
      'bomb clears radius and floating cluster with bank scoring',
      createGame,
      (game) async {
        final landing = cell(1, 1);
        final board = BubbleBoard(columns: BubbleShooter.columns)
          ..place(cell(0, 0), BubbleColor.yellow)
          ..place(cell(0, 1), BubbleColor.red)
          ..place(cell(0, 2), BubbleColor.green)
          ..place(cell(1, 0), BubbleColor.blue)
          ..place(cell(2, 0), BubbleColor.purple)
          ..place(cell(3, 0), BubbleColor.orange)
          ..place(cell(0, 7), BubbleColor.blue);
        final center = BubbleShooter.geometry.center(landing);
        game
          ..board = board
          ..boardComponent.syncBoard()
          ..currentShot = const (
            color: BubbleColor.red,
            kind: ShotKind.bomb,
          )
          ..onShotLanded(
            ShotResult(
              path: [
                const Point(240, 720),
                const Point(30, 400),
                Point(center.x, center.y),
                Point(center.x, center.y),
              ],
              landingCell: landing,
            ),
          );

        expect(game.board.isOccupied(landing), isFalse);
        expect(game.board.occupiedCells, containsAll([cell(0, 0), cell(0, 7)]));
        expect(game.board.occupiedCells, hasLength(2));
        // (3 direct * 10 + 2 floating * 20) * 2 for one bank.
        expect(game.score, 140);
        expect(game.status, GameStatus.aiming);
        expect(firedCues, ['assets/audio/bomb.mp3', Assets.audio.pop]);
        await game.ready();
        final feedback = game.boardComponent.children.whereType<SpecialShotEffectComponent>().single;
        expect(game.boardComponent.children.whereType<ParticleSystemComponent>(), isEmpty);
        expect(feedback.kind, ShotKind.bomb);
        expect(feedback.position, Vector2(center.x, center.y));
        expect(
          feedback.clearedOffsets,
          unorderedEquals([
            for (final removed in [cell(0, 1), cell(0, 2), cell(1, 0)])
              Offset(
                BubbleShooter.geometry.center(removed).x - center.x,
                BubbleShooter.geometry.center(removed).y - center.y,
              ),
          ]),
        );
      },
    );

    testWithGame(
      'bomb victory does not advance pressure',
      createGame,
      (game) async {
        const bomb = (color: BubbleColor.red, kind: ShotKind.bomb);
        final before = game.pressure;
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)..place(cell(0, 1), BubbleColor.yellow))
          ..boardComponent.syncBoard()
          ..currentShot = bomb
          ..onShotLanded(shotTo(cell(1, 1)));

        expect(game.board.isEmpty, isTrue);
        expect(game.score, 10);
        expect(game.status, GameStatus.victory);
        expect(game.ceilingOffset, 0);
        expect(game.pressure, before);
      },
    );

    testWithGame(
      'rainbow resolves to the contacted bubble colour',
      createGame,
      (game) async {
        final contact = cell(1, 0);
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(contact, BubbleColor.red)
            ..place(cell(0, 1), BubbleColor.blue))
          ..boardComponent.syncBoard()
          ..currentShot = const (
            color: BubbleColor.green,
            kind: ShotKind.rainbow,
          )
          ..onShotLanded(
            ShotResult(
              path: shotTo(cell(2, 0)).path,
              landingCell: cell(2, 0),
              contactCell: contact,
            ),
          );

        expect(game.board.occupiedCells, [cell(0, 1)]);
        expect(game.score, 30);
        expect(game.status, GameStatus.aiming);
        expect(firedCues, ['assets/audio/rainbow.mp3', Assets.audio.pop]);
        await game.ready();
        final feedback = game.boardComponent.children.whereType<SpecialShotEffectComponent>().single;
        expect(feedback.resolvedColor, BubbleColor.red);
        expect(feedback.contactOffset, isNotNull);
      },
    );

    testWithGame(
      'rainbow ceiling fallback uses its base colour without another draw',
      () => createGame(seed: 7),
      (game) async {
        final landing = cell(1, 0);
        final contact = cell(0, 0);

        void prepareBoard() {
          game
            ..board = (BubbleBoard(columns: BubbleShooter.columns)
              ..place(contact, BubbleColor.red)
              ..place(cell(0, 2), BubbleColor.yellow)
              ..place(cell(0, 4), BubbleColor.green)
              ..place(cell(0, 6), BubbleColor.blue))
            ..boardComponent.syncBoard()
            ..currentShot = const (
              color: BubbleColor.green,
              kind: ShotKind.rainbow,
            );
        }

        prepareBoard();
        game.onShotLanded(
          ShotResult(
            path: shotTo(landing).path,
            landingCell: landing,
            contactCell: contact,
          ),
        );
        final nextAfterContact = game.nextShot;

        game.startGame();
        prepareBoard();
        game.onShotLanded(shotTo(landing));

        expect(game.board.bubbleAt(landing), BubbleColor.green);
        expect(game.nextShot, nextAfterContact);
        await game.ready();
        final feedback = game.boardComponent.children.whereType<SpecialShotEffectComponent>().single;
        expect(feedback.resolvedColor, BubbleColor.green);
        expect(feedback.contactOffset, isNull);
      },
    );

    testWithGame('empty bomb still signals its activation without a pop', createGame, (game) async {
      game
        ..board = (BubbleBoard(columns: BubbleShooter.columns)..place(cell(0, 7), BubbleColor.blue))
        ..boardComponent.syncBoard()
        ..currentShot = (color: BubbleColor.red, kind: ShotKind.bomb)
        ..onShotLanded(shotTo(cell(0, 0)));

      expect(game.score, 0);
      expect(game.board.occupiedCells, [cell(0, 7)]);
      expect(firedCues, ['assets/audio/bomb.mp3']);
    });

    testWithGame('non-matching rainbow signals conversion without a pop', createGame, (game) async {
      final landing = cell(1, 0);
      final contact = cell(0, 0);
      game
        ..board = (BubbleBoard(columns: BubbleShooter.columns)..place(contact, BubbleColor.red))
        ..boardComponent.syncBoard()
        ..currentShot = (color: BubbleColor.green, kind: ShotKind.rainbow)
        ..onShotLanded(ShotResult(path: shotTo(landing).path, landingCell: landing, contactCell: contact));

      expect(game.board.bubbleAt(landing), BubbleColor.red);
      expect(game.score, 0);
      expect(firedCues, ['assets/audio/rainbow.mp3']);
    });

    testWithGame('consecutive special activations retain both effects until their own expiry', createGame, (
      game,
    ) async {
      game.boardComponent
        ..showSpecialShotFeedback(
          shot: (color: BubbleColor.red, kind: ShotKind.bomb),
          result: shotTo(cell(8, 0)),
          resolvedColor: null,
          popped: {},
        )
        ..showSpecialShotFeedback(
          shot: (color: BubbleColor.green, kind: ShotKind.rainbow),
          result: shotTo(cell(8, 2)),
          resolvedColor: BubbleColor.green,
          popped: {},
        );
      await game.ready();
      final effects = game.boardComponent.children.whereType<SpecialShotEffectComponent>().toList();
      expect(effects, hasLength(2));
      effects.first.update(1);
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), [effects.last]);
      game.boardComponent.showSpecialShotFeedback(
        shot: (color: BubbleColor.red, kind: ShotKind.bomb),
        result: shotTo(cell(8, 0)),
        resolvedColor: null,
        popped: {},
      );
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), hasLength(2));
      game.startGame();
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), isEmpty);
    });

    testWithGame('restart clears feedback even before it mounts', createGame, (game) async {
      game
        ..currentShot = (color: BubbleColor.red, kind: ShotKind.bomb)
        ..onShotLanded(shotTo(cell(8, 0)))
        ..startGame();
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), isEmpty);
    });

    testWithGame('active feedback follows the board and expires', createGame, (game) async {
      game
        ..currentShot = (color: BubbleColor.red, kind: ShotKind.bomb)
        ..onShotLanded(shotTo(cell(8, 0)));
      await game.ready();
      final feedback = game.boardComponent.children.whereType<SpecialShotEffectComponent>().single;
      final localPosition = feedback.position.clone();
      game.boardComponent.position.y = 100;
      expect(feedback.position, localPosition);
      expect(feedback.absolutePosition.y, localPosition.y + 100);
      game.update(1);
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), isEmpty);
    });

    testWithGame('restart removes mounted feedback', createGame, (game) async {
      game
        ..currentShot = (color: BubbleColor.red, kind: ShotKind.bomb)
        ..onShotLanded(shotTo(cell(8, 0)));
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), hasLength(1));
      game.startGame();
      await game.ready();
      expect(game.boardComponent.children.whereType<SpecialShotEffectComponent>(), isEmpty);
    });

    testWithGame('wall bounces multiply the score', createGame, (game) async {
      final board = BubbleBoard(columns: BubbleShooter.columns)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red)
        ..place(cell(0, 1), BubbleColor.blue);
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red;

      final center = BubbleShooter.geometry.center(cell(2, 0));
      final banked = ShotResult(
        // origin + one wall bounce + contact + landing.
        path: [
          const Point(240, 720),
          const Point(30, 400),
          Point(center.x, center.y),
          Point(center.x, center.y),
        ],
        landingCell: cell(2, 0),
      );
      game.onShotLanded(banked);

      expect(game.score, 60);
    });

    group('score feedback', () {
      /// A shot onto [landing] that touched a wall [bounces] times first.
      ShotResult bankedTo(HexCell landing, {int bounces = 1}) {
        final center = BubbleShooter.geometry.center(landing);
        return ShotResult(
          path: [
            const Point(240, 720),
            for (var index = 0; index < bounces; index++) Point(index.isEven ? 30.0 : 450.0, 600.0 - index * 100),
            Point(center.x, center.y),
            Point(center.x, center.y),
          ],
          landingCell: landing,
        );
      }

      /// Two reds at the top of column 0, so a red landing under them pops
      /// three, and a blue that keeps the board from emptying into victory.
      void seedRedPair(BubbleShooter game) {
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(1, 0), BubbleColor.red)
            ..place(cell(0, 4), BubbleColor.blue))
          ..boardComponent.syncBoard()
          ..currentShot = (color: BubbleColor.red, kind: ShotKind.normal);
      }

      List<ScoreCalloutComponent> callouts(BubbleShooter game) =>
          game.boardComponent.children.whereType<ScoreCalloutComponent>().toList();

      List<AimAssistNoticeComponent> notices(BubbleShooter game) =>
          game.world.children.whereType<AimAssistNoticeComponent>().toList();

      testWithGame('a direct clear calls out the points it added', createGame, (game) async {
        seedRedPair(game);
        game.onShotLanded(shotTo(cell(2, 0)));
        await game.ready();

        final callout = callouts(game).single;
        expect(callout.points, game.score);
        expect(callout.points, 30);
        expect(callout.bankLabel, isNull);
        expect(callout.ruleText, isNull);
        // A wall landing pulls the text inward instead of cutting it off.
        expect(callout.position.x, greaterThan(BubbleShooter.geometry.center(cell(2, 0)).x));
        expect(callout.position.x - callout.size.x / 2, greaterThanOrEqualTo(0));
      });

      testWithGame('a bank shot names its multiplier, and the first one explains it', createGame, (game) async {
        seedRedPair(game);
        game.onShotLanded(bankedTo(cell(2, 0), bounces: 2));
        await game.ready();

        final first = callouts(game).single;
        expect(first.points, 90);
        expect(first.points, game.score);
        expect(first.bankLabel, 'Bank ×3');
        expect(first.ruleText, 'Wall bounces multiply points');

        seedRedPair(game);
        final before = game.score;
        game.onShotLanded(bankedTo(cell(2, 0)));
        await game.ready();

        final second = callouts(game).last;
        expect(second.points, game.score - before);
        expect(second.bankLabel, 'Bank ×2');
        expect(second.ruleText, isNull, reason: 'the rule is explained once per run');

        game.startGame();
        seedRedPair(game);
        game.onShotLanded(bankedTo(cell(2, 0)));
        await game.ready();
        expect(callouts(game).single.ruleText, isNotNull, reason: 'a new run explains it again');
      });

      testWithGame('a bank shot that clears nothing spends no explanation', createGame, (game) async {
        seedRedPair(game);
        game
          ..currentShot = (color: BubbleColor.green, kind: ShotKind.normal)
          ..onShotLanded(bankedTo(cell(2, 0)));
        await game.ready();
        expect(callouts(game), isEmpty);

        seedRedPair(game);
        game.onShotLanded(bankedTo(cell(2, 0)));
        await game.ready();
        expect(callouts(game).single.ruleText, isNotNull);
      });

      testWithGame('Continue keeps the run, so the rule is not explained twice', createGame, (game) async {
        seedRedPair(game);
        game
          ..onShotLanded(bankedTo(cell(2, 0)))
          ..board = BubbleBoard(columns: BubbleShooter.columns);
        fillBelowFailLine(game.board, overshoot: 1);
        game
          ..boardComponent.syncBoard()
          ..currentShot = (color: BubbleColor.purple, kind: ShotKind.normal)
          ..onShotLanded(shotTo(failingCell(overshoot: 1)));
        expect(game.status, GameStatus.defeat);
        expect(game.revive(), isTrue);
        game
          ..update(0)
          ..update(0.3);

        seedRedPair(game);
        game.onShotLanded(bankedTo(cell(2, 0)));
        await game.ready();
        expect(callouts(game).last.ruleText, isNull);
      });

      /// Sets the run one shot before the descent from offset 2 (Path) to 3
      /// (Direction).
      void oneShotBeforeDirection(BubbleShooter game) => game
        ..ceilingOffset = 2
        ..pressureNotifier.value = (
          aimAssist: AimAssistLevel.trajectory,
          ceilingOffset: 2,
          colorCount: 5,
          shotsUntilDescent: 1,
        );

      testWithGame('a descent that ends the run announces nothing', createGame, (game) async {
        // A stack one row short of the line: the descent itself loses.
        game.board = BubbleBoard(columns: BubbleShooter.columns);
        fillBelowFailLine(game.board, ceilingOffset: 3);
        oneShotBeforeDirection(game);
        game
          ..boardComponent.syncBoard()
          ..currentShot = (color: BubbleColor.purple, kind: ShotKind.normal)
          ..onShotLanded(shotTo(failingCell(ceilingOffset: 3)));
        await game.ready();
        expect(game.status, GameStatus.defeat);
        expect(game.pressure.aimAssist, AimAssistLevel.direction);
        expect(notices(game), isEmpty);
      });

      testWithGame('Continue withdraws a notice for the tier it takes back', createGame, (game) async {
        oneShotBeforeDirection(game);
        resetAndLandMisses(game, 1, completeTransitions: false);
        await game.ready();
        expect(notices(game).single.label, 'Aim: Direction');

        // The very next shot loses without a descent, while that notice is
        // still showing; the retreat then hands Path back.
        game.board = BubbleBoard(columns: BubbleShooter.columns);
        fillBelowFailLine(game.board, ceilingOffset: 3, overshoot: 1);
        game
          ..update(0)
          ..update(0.3)
          ..boardComponent.syncBoard()
          ..currentShot = (color: BubbleColor.purple, kind: ShotKind.normal)
          ..onShotLanded(shotTo(failingCell(ceilingOffset: 3, overshoot: 1)));
        expect(game.status, GameStatus.defeat);
        expect(notices(game), hasLength(1));

        expect(game.revive(), isTrue);
        await game.ready();
        expect(game.pressure.aimAssist, AimAssistLevel.trajectory);
        expect(notices(game), isEmpty);
      });

      testWithGame('a lower aim tier is announced once, with its label', createGame, (game) async {
        resetAndLandMisses(game, 6);
        await game.ready();
        expect(game.pressure.aimAssist, AimAssistLevel.trajectory);
        final notice = notices(game).single;
        expect(notice.title, 'Aim help reduced');
        expect(notice.label, 'Aim: Path');

        game.update(AimAssistNoticeComponent.duration);
        await game.ready();
        expect(notices(game), isEmpty);

        // Offset 2 keeps the path tier: a descent alone is not a change.
        resetAndLandMisses(game, 5);
        await game.ready();
        expect(game.ceilingOffset, 2);
        expect(notices(game), isEmpty);

        resetAndLandMisses(game, 4);
        await game.ready();
        expect(notices(game).single.label, 'Aim: Direction');
      });

      testWithGame('a replay with feedback still on screen reaches the same run', createGame, (game) async {
        ({int score, PressureState pressure, LauncherShot current, LauncherShot next}) play() {
          game.startGame();
          seedRedPair(game);
          game.onShotLanded(bankedTo(cell(2, 0)));
          resetAndLandMisses(game, 6);
          return (score: game.score, pressure: game.pressure, current: game.currentShot, next: game.nextShot);
        }

        final first = play();
        await game.ready();
        expect(callouts(game), isNotEmpty);
        expect(notices(game), isNotEmpty);
        expect(play(), first);
      });

      testWithGame('restart clears callouts and notices, mounted or not', createGame, (game) async {
        seedRedPair(game);
        game.onShotLanded(bankedTo(cell(2, 0)));
        resetAndLandMisses(game, 6);
        await game.ready();
        expect(callouts(game), hasLength(1));
        expect(notices(game), hasLength(1));

        game.startGame();
        await game.ready();
        expect(callouts(game), isEmpty);
        expect(notices(game), isEmpty);

        seedRedPair(game);
        game
          ..onShotLanded(shotTo(cell(2, 0)))
          ..startGame();
        resetAndLandMisses(game, 6);
        game.startGame();
        await game.ready();
        expect(callouts(game), isEmpty);
        expect(notices(game), isEmpty);
      });
    });

    testWithGame('popping the whole board wins', createGame, (game) async {
      final board = BubbleBoard(columns: BubbleShooter.columns)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red);
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red
        ..onShotLanded(shotTo(cell(2, 0)));

      expect(game.board.isEmpty, isTrue);
      expect(game.status, GameStatus.victory);
      expect(game.overlays.isActive(BubbleShooter.gameOverOverlayKey), isTrue);

      game.startGame();
      expect(game.status, GameStatus.aiming);
      expect(game.score, 0);
      expect(
        game.overlays.isActive(BubbleShooter.gameOverOverlayKey),
        isFalse,
      );
    });

    testWithGame('dropped floating clusters score double', createGame, (
      game,
    ) async {
      final board = BubbleBoard(columns: BubbleShooter.columns)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red)
        // Green hangs below the red stem only.
        ..place(cell(2, 0), BubbleColor.green)
        ..place(cell(0, 4), BubbleColor.blue);
      // Landing red at (1, 1) connects to both reds: (0,0)-(1,0)-(1,1).
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red
        ..onShotLanded(shotTo(cell(1, 1)));

      // 3 pops * 10 + 1 drop * 20 = 50.
      expect(game.score, 50);
      expect(game.board.occupiedCells, [cell(0, 4)]);
    });

    testWithGame('a bubble crossing the fail line loses the game', createGame, (
      game,
    ) async {
      final board = BubbleBoard(columns: BubbleShooter.columns);
      // Alternating column: never three in a row.
      fillBelowFailLine(board);
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.green
        ..onShotLanded(shotTo(failingCell()));

      expect(game.status, GameStatus.defeat);
      expect(game.overlays.isActive(BubbleShooter.gameOverOverlayKey), isTrue);
    });

    testWithGame(
      'v1 pressure budget survives eight stacking shots and loses on the ninth',
      createGame,
      (game) async {
        final peak = game.board.occupiedCells.firstWhere(
          (candidate) => candidate.row == BubbleShooter.startRows - 1 && candidate.col < BubbleShooter.columns - 1,
        );

        for (var addition = 1; addition <= 8; addition++) {
          game
            ..currentColor = addition.isOdd ? BubbleColor.purple : BubbleColor.orange
            ..onShotLanded(
              shotTo(cell(peak.row + addition, peak.col)),
            );
          if (game.status == GameStatus.transitioning) {
            game
              ..update(0)
              ..update(0.3);
          }
          expect(game.status, GameStatus.aiming);
        }

        expect(game.ceilingOffset, 1);

        game
          ..currentColor = BubbleColor.purple
          ..onShotLanded(
            shotTo(cell(peak.row + 9, peak.col)),
          );

        expect(game.board.bottomRow, BubbleShooter.failRow - 1);
        expect(game.ceilingOffset, 1);
        expect(game.status, GameStatus.defeat);
      },
    );

    testWithGame(
      'pressure cadence accelerates to a three-shot floor',
      createGame,
      (game) async {
        expect(
          game.pressure,
          (
            aimAssist: AimAssistLevel.full,
            ceilingOffset: 0,
            colorCount: 4,
            shotsUntilDescent: BubbleShooter.shotsPerDescent,
          ),
        );

        resetAndLandMisses(game, 6);
        expect(game.ceilingOffset, 1);
        expect(game.pressure.shotsUntilDescent, 5);

        resetAndLandMisses(game, 5);
        expect(game.ceilingOffset, 2);
        expect(game.pressure.shotsUntilDescent, 4);

        resetAndLandMisses(game, 4);
        expect(game.ceilingOffset, 3);
        expect(
          game.pressure.shotsUntilDescent,
          BubbleShooter.minimumShotsPerDescent,
        );

        resetAndLandMisses(game, 3);
        expect(game.ceilingOffset, 4);
        expect(game.pressure.shotsUntilDescent, 3);
      },
    );

    testWithGame('active colour count follows ceiling depth', createGame, (
      game,
    ) async {
      expect(game.pressure.colorCount, 4);

      resetAndLandMisses(game, 6);
      resetAndLandMisses(game, 5);
      expect(game.ceilingOffset, 2);
      expect(game.pressure.colorCount, 5);

      resetAndLandMisses(game, 4);
      resetAndLandMisses(game, 3);
      expect(game.ceilingOffset, 4);
      expect(game.pressure.colorCount, 6);
    });

    testWithGame(
      'newly unlocked colours enter the queue before repeats',
      createGame,
      (game) async {
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(0, 1), BubbleColor.yellow)
            ..place(cell(0, 2), BubbleColor.green)
            ..place(cell(0, 3), BubbleColor.blue))
          ..boardComponent.syncBoard()
          ..ceilingOffset = 1
          ..pressureNotifier.value = (
            aimAssist: AimAssistLevel.trajectory,
            ceilingOffset: 1,
            colorCount: 4,
            shotsUntilDescent: 1,
          )
          ..currentColor = BubbleColor.red
          ..nextColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(0, 4)));

        expect(game.pressure.colorCount, 5);
        expect(game.nextColor, BubbleColor.purple);

        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(0, 1), BubbleColor.yellow)
            ..place(cell(0, 2), BubbleColor.green)
            ..place(cell(0, 3), BubbleColor.blue)
            ..place(cell(0, 4), BubbleColor.purple))
          ..boardComponent.syncBoard()
          ..ceilingOffset = 3
          ..pressureNotifier.value = (
            aimAssist: AimAssistLevel.direction,
            ceilingOffset: 3,
            colorCount: 5,
            shotsUntilDescent: 1,
          )
          ..currentColor = BubbleColor.red
          ..nextColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(0, 5)));

        expect(game.pressure.colorCount, 6);
        expect(game.nextColor, BubbleColor.orange);
      },
    );

    testWithGame(
      'aim guide withholds one capability at each depth',
      createGame,
      (game) async {
        final target = Vector2(-1000, 500);

        ShotResult solveCurrentShot() {
          final boardOriginY = game.shooterOrigin.y - game.ceilingOffset * BubbleShooter.geometry.rowHeight;
          return BubbleShooter.solver.solve(
            board: game.board,
            origin: Point(game.shooterOrigin.x, boardOriginY),
            direction: Point(
              target.x - game.shooterOrigin.x,
              target.y - game.shooterOrigin.y,
            ),
          )!;
        }

        final fullShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.full);
        expect(game.aimGuide.showLanding, isTrue);
        expect(game.aimGuide.path, fullShot.path);

        resetAndLandMisses(game, 6);
        expect(game.ceilingOffset, 1);
        final pathOnlyShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.trajectory);
        expect(game.aimGuide.showLanding, isFalse);
        expect(game.aimGuide.path, pathOnlyShot.path);

        // The reflected path survives the second descent (2026-09-16): the
        // line stops solving bank shots at the third descent, not the second.
        resetAndLandMisses(game, 5);
        expect(game.ceilingOffset, 2);
        final stillPathOnlyShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.trajectory);
        expect(game.aimGuide.showLanding, isFalse);
        expect(game.aimGuide.path, stillPathOnlyShot.path);

        resetAndLandMisses(game, 4);
        expect(game.ceilingOffset, 3);
        final directShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.direction);
        expect(game.aimGuide.showLanding, isFalse);
        expect(game.aimGuide.path, directShot.path.take(2));

        resetAndLandMisses(game, 3);
        expect(game.ceilingOffset, 4);
        final stillDirectShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.direction);
        expect(game.aimGuide.path, stillDirectShot.path.take(2));

        resetAndLandMisses(game, 3);
        expect(game.ceilingOffset, 5);
        game.currentColor = BubbleColor.purple;
        final hiddenShot = solveCurrentShot();
        game.aimAt(target);
        expect(game.pressure.aimAssist, AimAssistLevel.hidden);
        expect(game.aimGuide.path, isNull);
        game.fire();
        expect(game.status, GameStatus.flying);

        for (var index = 0; index < 10 && game.status == GameStatus.flying; index++) {
          game.update(0.5);
        }
        expect(game.status, GameStatus.aiming);
        expect(game.board.bubbleAt(hiddenShot.landingCell), BubbleColor.purple);
      },
    );

    testWithGame(
      'direct assistance keeps a straight shot honest',
      createGame,
      (game) async {
        resetAndLandMisses(game, 6);
        resetAndLandMisses(game, 5);
        resetAndLandMisses(game, 4);
        expect(game.ceilingOffset, 3);
        expect(game.pressure.aimAssist, AimAssistLevel.direction);
        final target = Vector2(game.shooterOrigin.x, 0);
        final boardOriginY = game.shooterOrigin.y - game.ceilingOffset * BubbleShooter.geometry.rowHeight;
        final solved = BubbleShooter.solver.solve(
          board: game.board,
          origin: Point(game.shooterOrigin.x, boardOriginY),
          direction: Point(0, -game.shooterOrigin.y),
        )!;

        game.aimAt(target);

        expect(game.aimGuide.showLanding, isFalse);
        expect(game.aimGuide.path, solved.path.take(2));
      },
    );

    testWithGame(
      'blocks aim and fire until the current ceiling slide completes',
      createGame,
      (game) async {
        resetAndLandMisses(game, 6, completeTransitions: false);

        expect(game.status, GameStatus.transitioning);
        final currentShot = game.currentShot;
        final nextShot = game.nextShot;
        final shotCount = game.shotCount;
        final guidePath = game.aimGuide.path;
        final cues = List<String>.of(firedCues);
        final receivedEvents = <GameEvent>[];
        final subscription = game.events.listen(receivedEvents.add);
        addTearDown(subscription.cancel);

        game
          ..aimAt(Vector2(game.shooterOrigin.x + 1, 0))
          ..fire();
        await Future<void>.delayed(Duration.zero);

        expect(game.status, GameStatus.transitioning);
        expect(game.hasAimedShot, isFalse);
        expect(game.aimGuide.path, guidePath);
        expect(game.currentShot, currentShot);
        expect(game.nextShot, nextShot);
        expect(game.shotCount, shotCount);
        expect(firedCues, cues);
        expect(receivedEvents.whereType<ShotFired>(), isEmpty);
        expect(
          game.boardComponent.children.whereType<ProjectileComponent>(),
          isEmpty,
        );

        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.aiming);
      },
    );

    testWithGame(
      'a stale ceiling slide cannot overwrite victory',
      createGame,
      (game) async {
        resetAndLandMisses(game, 6, completeTransitions: false);
        expect(game.status, GameStatus.transitioning);
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(1, 0), BubbleColor.red))
          ..boardComponent.syncBoard()
          ..currentColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(2, 0)));

        expect(game.status, GameStatus.victory);
        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.victory);
      },
    );

    testWithGame('winning shot does not advance pressure', createGame, (
      game,
    ) async {
      final board = BubbleBoard(columns: BubbleShooter.columns)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(1, 0), BubbleColor.red);
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red
        ..onShotLanded(shotTo(cell(2, 0)));

      expect(game.status, GameStatus.victory);
      expect(game.ceilingOffset, 0);
      expect(game.pressure.shotsUntilDescent, 6);
    });

    testWithGame(
      'restart restores initial pressure and full aim assistance',
      createGame,
      (game) async {
        resetAndLandMisses(game, 6);
        expect(game.pressure.aimAssist, AimAssistLevel.trajectory);

        game.startGame();

        expect(game.ceilingOffset, 0);
        expect(
          game.pressure,
          (
            aimAssist: AimAssistLevel.full,
            ceilingOffset: 0,
            colorCount: 4,
            shotsUntilDescent: 6,
          ),
        );
        game.aimAt(Vector2(game.shooterOrigin.x + 1, 0));
        expect(game.aimGuide.showLanding, isTrue);
        expect(game.aimGuide.path, isNotNull);
      },
    );

    testWithGame('restart cancels an in-flight ceiling slide', createGame, (
      game,
    ) async {
      resetAndLandMisses(game, 6, completeTransitions: false);
      expect(game.status, GameStatus.transitioning);
      game
        ..update(0)
        ..update(0.1);
      expect(game.boardComponent.position.y, greaterThan(0));

      game.startGame();
      expect(game.boardComponent.position, Vector2.zero());
      expect(game.status, GameStatus.aiming);

      game.update(0.3);
      expect(game.boardComponent.position, Vector2.zero());
      expect(game.status, GameStatus.aiming);
    });

    testWithGame('restart drops a shot still in flight', createGame, (
      game,
    ) async {
      game
        ..aimAt(Vector2(BubbleShooter.worldWidth / 2, 100))
        ..fire();
      await game.ready();
      expect(
        game.boardComponent.children.whereType<ProjectileComponent>(),
        isNotEmpty,
      );

      // A surviving projectile would finish its path over the fresh board
      // and commit the previous run's landing to it.
      game.startGame();
      await game.ready();

      expect(
        game.boardComponent.children.whereType<ProjectileComponent>(),
        isEmpty,
      );
      expect(game.shotCount, 0);
    });
  });

  group('events and run stats', () {
    testWithGame('startGame emits RunStarted', createGame, (game) async {
      final events = <GameEvent>[];
      final sub = game.events.listen(events.add);
      game.startGame();
      await Future<void>.delayed(Duration.zero);
      expect(events, contains(const RunStarted()));
      await sub.cancel();
    });

    testWithGame('an aimed fire emits ShotFired', createGame, (game) async {
      final events = <GameEvent>[];
      final sub = game.events.listen(events.add);
      game
        ..aimAt(Vector2(game.shooterOrigin.x + 1, 0))
        ..fire();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<ShotFired>(), hasLength(1));
      await sub.cancel();
    });

    testWithGame(
      'an unaimed fire emits no ShotFired',
      createGame,
      (game) async {
        final events = <GameEvent>[];
        final sub = game.events.listen(events.add);
        game.fire();
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<ShotFired>(), isEmpty);
        await sub.cancel();
      },
    );

    testWithGame('defeat emits GameOverReached with run stats', createGame, (
      game,
    ) async {
      final events = <GameEvent>[];
      final sub = game.events.listen(events.add);
      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board, ceilingOffset: 2);
      game
        ..ceilingOffset = 2
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell(ceilingOffset: 2)));
      await Future<void>.delayed(Duration.zero);
      expect(game.status, GameStatus.defeat);
      final stats = events.whereType<GameOverReached>().single.stats;
      expect(stats.reason, GameOverReason.defeat);
      expect(stats.shotCount, 1);
      expect(stats.continued, isFalse);
      // The shot that ends the run is the deepest thing on the board, and it
      // lands on the fail line by construction.
      expect(stats.maxOccupiedRows, BubbleShooter.failRow);
      expect(stats.ceilingDepth, 2);
      await sub.cancel();
    });

    testWithGame(
      'a popped deepest landing still records its depth',
      createGame,
      (game) async {
        final board = BubbleBoard(columns: BubbleShooter.columns);
        for (var row = 0; row <= 4; row++) {
          board.place(
            cell(row, 0),
            row.isEven ? BubbleColor.blue : BubbleColor.yellow,
          );
        }
        board
          ..place(cell(5, 0), BubbleColor.red)
          ..place(cell(5, 1), BubbleColor.red);
        game
          ..board = board
          ..maxOccupiedRows = 0
          ..boardComponent.syncBoard()
          ..currentColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(5, 2)));
        // The red triple at row 5 popped, but the run still reached row 5.
        expect(game.board.bottomRow, 4);
        expect(game.maxOccupiedRows, 5);
      },
    );

    testWithGame(
      'a descent without defeat records the deeper world row',
      createGame,
      (game) async {
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(1, 0), BubbleColor.blue))
          ..maxOccupiedRows = 0
          ..boardComponent.syncBoard()
          ..pressureNotifier.value = (
            aimAssist: AimAssistLevel.full,
            ceilingOffset: 0,
            colorCount: 4,
            shotsUntilDescent: 1,
          )
          ..currentColor = BubbleColor.purple
          ..onShotLanded(shotTo(cell(0, 1)));
        expect(game.ceilingOffset, 1);
        expect(game.status, GameStatus.transitioning);
        expect(game.maxOccupiedRows, game.board.bottomRow + 1);
        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.aiming);
      },
    );

    testWithGame('victory emits GameOverReached', createGame, (game) async {
      final events = <GameEvent>[];
      final sub = game.events.listen(events.add);
      final board = BubbleBoard(columns: BubbleShooter.columns)
        ..place(cell(0, 0), BubbleColor.red)
        ..place(cell(0, 1), BubbleColor.red);
      game
        ..board = board
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red
        ..onShotLanded(shotTo(cell(0, 2)));
      await Future<void>.delayed(Duration.zero);
      expect(game.status, GameStatus.victory);
      final stats = events.whereType<GameOverReached>().single.stats;
      expect(stats.reason, GameOverReason.victory);
      expect(stats.ceilingDepth, 0);
      await sub.cancel();
    });
  });

  group('sound cues', () {
    testWithGame('an aimed fire launches the shoot cue', createGame, (
      game,
    ) async {
      game
        ..aimAt(Vector2(game.shooterOrigin.x + 1, 0))
        ..fire();

      expect(firedCues, [Assets.audio.shoot]);
    });

    testWithGame('an unaimed fire stays silent', createGame, (game) async {
      // Level and downward aims resolve to nothing, and a cue on a shot
      // that never leaves would read as a misfire.
      game
        ..aimAt(Vector2(game.shooterOrigin.x + 1, game.shooterOrigin.y + 1))
        ..fire();

      expect(firedCues, isEmpty);
    });

    testWithGame(
      'a landing that pops and descends sounds both cues',
      createGame,
      (game) async {
        game
          ..board = (BubbleBoard(columns: BubbleShooter.columns)
            ..place(cell(0, 0), BubbleColor.red)
            ..place(cell(1, 0), BubbleColor.red)
            ..place(cell(0, 1), BubbleColor.blue))
          ..boardComponent.syncBoard()
          ..pressureNotifier.value = (
            aimAssist: AimAssistLevel.full,
            ceilingOffset: 0,
            colorCount: 4,
            shotsUntilDescent: 1,
          )
          ..currentColor = BubbleColor.red
          ..onShotLanded(shotTo(cell(2, 0)));

        // The overlap the one-shot-per-cue design exists for: on a shared
        // player the descent warning would cut the pop, or never be heard.
        expect(firedCues, [Assets.audio.pop, Assets.audio.descent]);
      },
    );

    testWithGame('a shot short of the cadence never warns', createGame, (
      game,
    ) async {
      resetAndLandMisses(game, 1);

      expect(game.ceilingOffset, 0);
      expect(firedCues, isEmpty);
    });

    testWithGame('victory sounds the game over cue', createGame, (game) async {
      game
        ..board = (BubbleBoard(columns: BubbleShooter.columns)
          ..place(cell(0, 0), BubbleColor.red)
          ..place(cell(0, 1), BubbleColor.red))
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.red
        ..onShotLanded(shotTo(cell(0, 2)));

      expect(game.status, GameStatus.victory);
      expect(firedCues, [Assets.audio.pop, Assets.audio.gameover]);
    });

    testWithGame('defeat sounds the same cue as victory', createGame, (
      game,
    ) async {
      game.board = BubbleBoard(columns: BubbleShooter.columns);
      for (var row = 0; row < BubbleShooter.failRow; row++) {
        game.board.place(cell(row, 0), BubbleColor.red);
      }
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(cell(BubbleShooter.failRow, 0)));

      expect(game.status, GameStatus.defeat);
      expect(firedCues, [Assets.audio.gameover]);
    });
  });

  group('revive', () {
    /// Fills column 0 as deep as the descended ceiling allows and lands a
    /// purple shot one row *past* the fail line, leaving the game defeated.
    ///
    /// The overshoot is the point: `revive()` retreats the ceiling by one, so
    /// a board that failed by exactly one row would come back playable with
    /// nothing to clear, and these tests are about what the clearing does.
    void reachDefeat(BubbleShooter game, {required int ceilingOffset}) {
      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(
        game.board,
        ceilingOffset: ceilingOffset,
        overshoot: 1,
      );
      game
        ..ceilingOffset = ceilingOffset
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(
          shotTo(failingCell(ceilingOffset: ceilingOffset, overshoot: 1)),
        );
      expect(game.status, GameStatus.defeat);
    }

    testWithGame(
      'restores a board after a special-shot defeat',
      createGame,
      (game) async {
        final board = BubbleBoard(columns: BubbleShooter.columns);
        fillBelowFailLine(board);
        const queued = (
          color: BubbleColor.blue,
          kind: ShotKind.rainbow,
        );
        game
          ..board = board
          ..boardComponent.syncBoard()
          ..pressureNotifier.value = (
            aimAssist: AimAssistLevel.full,
            ceilingOffset: 0,
            colorCount: 4,
            shotsUntilDescent: 1,
          )
          ..currentShot = const (
            color: BubbleColor.red,
            kind: ShotKind.bomb,
          )
          ..nextShot = queued
          ..onShotLanded(shotTo(cell(1, 5)));

        expect(game.status, GameStatus.defeat);
        expect(game.ceilingOffset, 1);
        expect(game.currentShot.kind, ShotKind.bomb);
        expect(game.nextShot, queued);
        expect(game.score, 0);
        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.defeat);

        expect(game.revive(), isTrue);
        expect(game.status, GameStatus.transitioning);
        expect(game.ceilingOffset, 0);
        expect(game.currentShot, queued);
        expect(game.score, 0);
        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.aiming);
      },
    );

    testWithGame(
      'retreats, clears the fail zone, and resumes aiming',
      createGame,
      (game) async {
        reachDefeat(game, ceilingOffset: 2);
        final revived = game.revive();
        expect(revived, isTrue);
        expect(game.status, GameStatus.transitioning);
        expect(game.ceilingOffset, 1);
        // The landing sat one row past the line, so even after the retreat it
        // is still at or beyond failRow — which is what clears it.
        expect(
          game.board.isOccupied(failingCell(ceilingOffset: 2, overshoot: 1)),
          isFalse,
        );
        expect(game.continuedThisRun, isTrue);
        expect(
          game.overlays.isActive(BubbleShooter.gameOverOverlayKey),
          isFalse,
        );
        game
          ..update(0)
          ..update(0.3);
        expect(game.status, GameStatus.aiming);
      },
    );

    testWithGame('cleared bubbles award no score', createGame, (game) async {
      reachDefeat(game, ceilingOffset: 2);
      final before = game.score;
      game.revive();
      expect(game.score, before);
    });

    testWithGame('is rejected outside defeat and on second use', createGame, (
      game,
    ) async {
      expect(game.revive(), isFalse); // aiming
      reachDefeat(game, ceilingOffset: 2);
      expect(game.revive(), isTrue);
      reachDefeat(game, ceilingOffset: game.ceilingOffset);
      expect(game.revive(), isFalse); // already continued this run
    });

    testWithGame('startGame resets the continue flag', createGame, (
      game,
    ) async {
      reachDefeat(game, ceilingOffset: 2);
      game
        ..revive()
        ..startGame();
      expect(game.continuedThisRun, isFalse);
      expect(game.shotCount, 0);
    });
  });
}
