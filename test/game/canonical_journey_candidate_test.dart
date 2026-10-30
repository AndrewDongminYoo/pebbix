// 🎯 Dart imports:
import 'dart:math';

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/l10n/gen/app_localizations_en.dart';

import '../../tool/store_assets/canonical_journey.dart';

BubbleShooter _createGame() {
  final game = BubbleShooter(
    l10n: AppLocalizationsEn(),
    playSfx: (_) {},
    textStyle: const TextStyle(),
    images: Images(prefix: ''),
    seed: canonicalJourneySeed,
  );
  game.overlays.addEntry(BubbleShooter.gameOverOverlayKey, (_, _) => const SizedBox());
  return game;
}

void _advanceUntil(
  BubbleShooter game, {
  required bool Function() predicate,
  required String expected,
  required int maximumFrames,
  required double frameStep,
}) {
  for (var frame = 0; frame < maximumFrames; frame++) {
    if (predicate()) return;
    game.update(frameStep);
  }
  if (predicate()) return;
  throw TestFailure(
    'Candidate journey timed out waiting for $expected. '
    'status=${game.status}, score=${game.score}, shotCount=${game.shotCount}, '
    'ceilingOffset=${game.ceilingOffset}, aimAssist=${game.pressure.aimAssist}, '
    'colorCount=${game.pressure.colorCount}, shotsUntilDescent=${game.pressure.shotsUntilDescent}, '
    'boardBottomRow=${game.board.bottomRow}, aimPathPointCount=${game.aimGuide.path?.length ?? 0}, '
    'sessionPhase=not-applicable-pure-game-candidate',
  );
}

CanonicalShotOutcome? _fireAndLand(BubbleShooter game) {
  final path = game.aimGuide.path == null ? null : List<Point<double>>.of(game.aimGuide.path!);
  final boardCountBefore = game.board.occupiedCells.length;
  final scoreBefore = game.score;
  final addsLanding = game.currentShot.kind == ShotKind.bomb ? 0 : 1;
  game
    ..fire()
    ..update(0);
  _advanceUntil(
    game,
    predicate: () => game.status != GameStatus.flying,
    expected: 'the fired shot to land',
    maximumFrames: 50,
    frameStep: 0.1,
  );
  if (game.status == GameStatus.transitioning) {
    _advanceUntil(
      game,
      predicate: () => game.status != GameStatus.transitioning,
      expected: 'the ceiling transition to finish',
      maximumFrames: 10,
      frameStep: 0.05,
    );
  }

  if (path == null || path.length < 3) return null;
  final scoreGain = game.score - scoreBefore;
  final multiplier = path.length - 2;
  final removed = boardCountBefore + addsLanding - game.board.occupiedCells.length;
  expect(scoreGain % (multiplier * 10), 0);
  final weightedRemoved = scoreGain ~/ (multiplier * 10);
  final dropped = weightedRemoved - removed;
  return (
    bounces: path.length - 3,
    popped: removed - dropped,
    dropped: dropped,
    scoreGain: scoreGain,
  );
}

void main() {
  group('candidate scene predicates', () {
    test('precise aiming rejects an invalid aim', () {
      expect(
        isCanonicalPreciseAim(
          aimAssist: AimAssistLevel.full,
          hasAimedShot: false,
          path: const [Point(240, 970), Point(240, 100), Point(240, 60)],
          showLanding: true,
        ),
        isFalse,
      );
    });

    test('bank shot rejects a direct path', () {
      expect(
        hasCanonicalWallReflection(const [Point(240, 970), Point(240, 100), Point(240, 60)]),
        isFalse,
      );
    });

    test('cluster drop rejects a shot with no disconnected removal', () {
      expect(
        isCanonicalClusterDrop(
          outcome: (bounces: 3, popped: 5, dropped: 0, scoreGain: 280),
          score: 280,
          boardSignature: canonicalClusterDropBoardSignature,
          visualStable: true,
        ),
        isFalse,
      );
    });

    test('ceiling pressure rejects the opening pressure state', () {
      expect(
        isCanonicalPressureScene(
          ceilingOffset: 0,
          aimAssist: AimAssistLevel.full,
          colorCount: 4,
          shotsUntilDescent: BubbleShooter.shotsPerDescent,
          currentShotKind: ShotKind.bomb,
        ),
        isFalse,
      );
    });

    test('ceiling pressure rejects a normal launcher bubble', () {
      expect(
        isCanonicalPressureScene(
          ceilingOffset: 1,
          aimAssist: AimAssistLevel.trajectory,
          colorCount: 4,
          shotsUntilDescent: 1,
          currentShotKind: ShotKind.normal,
        ),
        isFalse,
      );
    });

    test('high score rejects an unfinished run', () {
      expect(
        isCanonicalHighScore(status: GameStatus.aiming, stats: null, freshHighScore: canonicalFreshHighScore),
        isFalse,
      );
    });
  });

  testWithGame('seed 0 and one normalized action script reach all candidate scenes', _createGame, (game) async {
    final gameOverFuture = game.events
        .firstWhere((event) => event is GameOverReached)
        .then((event) => event as GameOverReached);

    for (var index = 0; index < canonicalJourneyActions.length; index++) {
      game.aimAt(canonicalWorldPoint(canonicalJourneyActions[index]));

      if (index == 0) {
        expect(
          isCanonicalPreciseAim(
            aimAssist: game.pressure.aimAssist,
            hasAimedShot: game.hasAimedShot,
            path: game.aimGuide.path,
            showLanding: game.aimGuide.showLanding,
          ),
          isTrue,
        );
      }
      if (index == 1) {
        expect(hasCanonicalWallReflection(game.aimGuide.path), isTrue);
      }
      if (index == 10) {
        expect(game.currentShot.kind, ShotKind.bomb);
        expect(
          isCanonicalPressureScene(
            ceilingOffset: game.ceilingOffset,
            aimAssist: game.pressure.aimAssist,
            colorCount: game.pressure.colorCount,
            shotsUntilDescent: game.pressure.shotsUntilDescent,
            currentShotKind: game.currentShot.kind,
          ),
          isTrue,
        );
      }

      final outcome = _fireAndLand(game);
      expect(game.shotCount, index + 1);

      if (index == 1) {
        expect(outcome, isNotNull);
        final clusterOutcome = outcome!;
        expect(clusterOutcome.bounces, 3);
        _advanceUntil(
          game,
          predicate: () => hasStableCanonicalClusterVisual(game),
          expected: 'cluster-drop particles and falling bubbles to disappear',
          maximumFrames: 12,
          frameStep: 0.05,
        );
        // In game time the board settles while the callout still shows, so
        // the capture can require both; only a stalled device can miss it.
        expect(hasCanonicalScoreCallout(game), isTrue);
        expect(hasNoTransientFeedback(game), isFalse);
        expect(
          isCanonicalClusterDrop(
            outcome: clusterOutcome,
            score: game.score,
            boardSignature: canonicalBoardSignature(game),
            visualStable: hasStableCanonicalClusterVisual(game),
          ),
          isTrue,
        );
      }

      if (index < canonicalJourneyActions.length - 1) {
        expect(game.status, GameStatus.aiming);
      }
    }

    final gameOver = await gameOverFuture.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw TestFailure(
        'Candidate journey timed out waiting for GameOverReached. '
        'status=${game.status}, score=${game.score}, shotCount=${game.shotCount}, '
        'ceilingOffset=${game.ceilingOffset}, aimAssist=${game.pressure.aimAssist}, '
        'colorCount=${game.pressure.colorCount}, shotsUntilDescent=${game.pressure.shotsUntilDescent}, '
        'boardBottomRow=${game.board.bottomRow}, aimPathPointCount=${game.aimGuide.path?.length ?? 0}, '
        'sessionPhase=not-applicable-pure-game-candidate',
      ),
    );
    final stats = gameOver.stats;
    expect(
      isCanonicalHighScore(status: game.status, stats: stats, freshHighScore: canonicalFreshHighScore),
      isTrue,
    );
    expect(stats.score, 440);
    expect(stats.shotCount, canonicalJourneyActions.length);
    expect(stats.maxOccupiedRows, 17);
    expect(stats.continued, isFalse);
  });
}
