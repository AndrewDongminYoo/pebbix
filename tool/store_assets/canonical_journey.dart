// 🎯 Dart imports:
import 'dart:math';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/aim_assist_notice_component.dart';
import 'package:bubble_shooter/game/components/score_callout_component.dart';
import 'package:bubble_shooter/game/game.dart';

typedef NormalizedWorldAction = ({double x, double y});
typedef CanonicalShotOutcome = ({int bounces, int popped, int dropped, int scoreGain});

enum CanonicalScene {
  aim(
    fileName: '01-aim.png',
    actionIndex: 0,
    timeout: Duration(seconds: 2),
  ),
  bankShot(
    fileName: '02-bank-shot.png',
    actionIndex: 1,
    timeout: Duration(seconds: 2),
  ),
  clusterDrop(
    fileName: '03-cluster-drop.png',
    actionIndex: 1,
    timeout: Duration(seconds: 3),
  ),
  pressure(
    fileName: '04-pressure.png',
    actionIndex: 10,
    timeout: Duration(seconds: 3),
  ),
  highScore(
    fileName: '05-high-score.png',
    actionIndex: 14,
    timeout: Duration(seconds: 3),
  );

  new({
    required this.fileName,
    required this.actionIndex,
    required this.timeout,
  });

  final String fileName;
  final int actionIndex;
  final Duration timeout;
}

const canonicalJourneySeed = 0;
const canonicalFreshHighScore = 0;
const canonicalJourneyActions = <NormalizedWorldAction>[
  (x: 300 / BubbleShooter.worldWidth, y: 720 / BubbleShooter.worldHeight),
  (x: 40 / BubbleShooter.worldWidth, y: 880 / BubbleShooter.worldHeight),
  (x: 300 / BubbleShooter.worldWidth, y: 320 / BubbleShooter.worldHeight),
  (x: 180 / BubbleShooter.worldWidth, y: 480 / BubbleShooter.worldHeight),
  (x: 480 / BubbleShooter.worldWidth, y: 880 / BubbleShooter.worldHeight),
  (x: 180 / BubbleShooter.worldWidth, y: 480 / BubbleShooter.worldHeight),
  (x: 180 / BubbleShooter.worldWidth, y: 480 / BubbleShooter.worldHeight),
  (x: 140 / BubbleShooter.worldWidth, y: 240 / BubbleShooter.worldHeight),
  (x: 120 / BubbleShooter.worldWidth, y: 240 / BubbleShooter.worldHeight),
  (x: 120 / BubbleShooter.worldWidth, y: 240 / BubbleShooter.worldHeight),
  (x: 280 / BubbleShooter.worldWidth, y: 640 / BubbleShooter.worldHeight),
  (x: 0, y: 800 / BubbleShooter.worldHeight),
  (x: 0, y: 800 / BubbleShooter.worldHeight),
  (x: 40 / BubbleShooter.worldWidth, y: 400 / BubbleShooter.worldHeight),
  (x: 0, y: 80 / BubbleShooter.worldHeight),
];

const canonicalClusterDropBoardSignature =
    '0:0:blue,0:1:green,0:2:red,0:3:red,0:4:blue,0:5:green,0:6:yellow,0:7:yellow,'
    '1:0:red,1:1:yellow,1:2:blue,1:3:blue,1:4:green,1:5:yellow,1:6:red,'
    '2:0:green,2:1:yellow,2:2:red,2:3:red,2:4:green,2:5:green,2:6:green,2:7:red,'
    '3:0:green,3:1:red,3:2:red,3:3:red,3:4:red,3:5:red,3:6:yellow,'
    '4:0:red,4:1:green,4:2:red,4:3:green,4:4:red,4:5:yellow,4:6:green,4:7:green,'
    '5:0:green,5:1:red,5:2:green,5:4:red,6:0:blue,6:1:yellow';

Vector2 canonicalWorldPoint(NormalizedWorldAction action) => Vector2(
  action.x * BubbleShooter.worldWidth,
  action.y * BubbleShooter.worldHeight,
);

String canonicalBoardSignature(BubbleShooter game) {
  final cells = game.board.occupiedCells.toList()
    ..sort((left, right) {
      final row = left.row.compareTo(right.row);
      return row != 0 ? row : left.col.compareTo(right.col);
    });
  return cells.map((cell) => '${cell.row}:${cell.col}:${game.board.bubbleAt(cell)!.name}').join(',');
}

bool isCanonicalPreciseAim({
  required AimAssistLevel aimAssist,
  required bool hasAimedShot,
  required List<Point<double>>? path,
  required bool showLanding,
}) => aimAssist == AimAssistLevel.full && hasAimedShot && path != null && path.length >= 3 && showLanding;

bool hasCanonicalWallReflection(List<Point<double>>? path) {
  if (path == null || path.length < 4) return false;
  final reflectionPoints = path.sublist(1, path.length - 2);
  const leftWall = BubbleShooter.bubbleRadius;
  const rightWall = BubbleShooter.worldWidth - BubbleShooter.bubbleRadius;
  return reflectionPoints.any(
    (point) => (point.x - leftWall).abs() < 0.000001 || (point.x - rightWall).abs() < 0.000001,
  );
}

bool isCanonicalClusterDrop({
  required CanonicalShotOutcome outcome,
  required int score,
  required String boardSignature,
  required bool visualStable,
}) =>
    outcome.dropped > 0 &&
    outcome.popped == 5 &&
    outcome.scoreGain == 280 &&
    score == 280 &&
    boardSignature == canonicalClusterDropBoardSignature &&
    visualStable;

bool isCanonicalPressureScene({
  required int ceilingOffset,
  required AimAssistLevel aimAssist,
  required int colorCount,
  required int shotsUntilDescent,
  required ShotKind currentShotKind,
}) =>
    ceilingOffset == 1 &&
    aimAssist == AimAssistLevel.trajectory &&
    colorCount == 4 &&
    shotsUntilDescent == 1 &&
    currentShotKind == ShotKind.bomb;

bool isCanonicalHighScore({
  required GameStatus status,
  required GameOverStats? stats,
  required int freshHighScore,
}) =>
    status == GameStatus.defeat &&
    stats != null &&
    stats.reason == GameOverReason.defeat &&
    stats.score > freshHighScore;

bool hasStableCanonicalClusterVisual(BubbleShooter game) =>
    game.boardComponent.children.whereType<BubbleComponent>().length == game.board.occupiedCells.length &&
    game.boardComponent.children.whereType<ParticleSystemComponent>().isEmpty;

/// Whether a shot's score callout is on the board. The cluster drop is the
/// run's first scoring bank shot, so its capture shows the multiplier, the
/// points, and the rule (`docs/specs/2026-10-01-bank-shot-feedback.md`).
bool hasCanonicalScoreCallout(BubbleShooter game) =>
    game.boardComponent.children.whereType<ScoreCalloutComponent>().isNotEmpty;

/// Whether every score callout and assist notice has expired, so a scene
/// whose capture moment depends on timing cannot catch one by chance.
bool hasNoTransientFeedback(BubbleShooter game) =>
    !hasCanonicalScoreCallout(game) && game.world.children.whereType<AimAssistNoticeComponent>().isEmpty;
