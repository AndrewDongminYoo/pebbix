// 🎯 Dart imports:
import 'dart:async';
import 'dart:math' as math;

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/aim_assist_notice_component.dart';
import 'package:bubble_shooter/game/components/components.dart';
import 'package:bubble_shooter/game/components/defender_motion.dart';
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

/// Fires a one-shot effect by asset path. Declared here rather than beside
/// the audio cubit so the game stays ignorant of the audio stack — it knows
/// only that something plays a sound.
typedef PlaySfx = void Function(String asset);

enum GameStatus { aiming, transitioning, flying, victory, defeat }

enum AimAssistLevel { full, trajectory, direction, hidden }

extension AimAssistLabel on AimAssistLevel {
  /// The tier's name as the HUD shows it; the descent notice reuses it so
  /// the two can never call one tier by different names.
  String label(AppLocalizations l10n) => switch (this) {
    AimAssistLevel.full => l10n.aimAssistFull,
    AimAssistLevel.trajectory => l10n.aimAssistPath,
    AimAssistLevel.direction => l10n.aimAssistDirection,
    AimAssistLevel.hidden => l10n.aimAssistOff,
  };
}

typedef AimGuideProjection = ({
  List<math.Point<double>>? path,
  bool showLanding,
});

typedef PressureState = ({
  AimAssistLevel aimAssist,
  int ceilingOffset,
  int colorCount,
  int shotsUntilDescent,
});

class BubbleShooter extends FlameGame {
  new({
    required this.l10n,
    required this.playSfx,
    required this.textStyle,
    required Images images,
    this.seed,
  }) : super(
         camera: CameraComponent.withFixedResolution(
           width: worldWidth,
           height: worldHeight,
         ),
       ) {
    this.images = images;
  }

  static const columns = 8;
  static const bubbleRadius = 30.0;
  static const double worldWidth = columns * bubbleRadius * 2;

  /// Aspect 0.462 — a 9:19.5 phone. The previous 800 made it 0.600, so a
  /// width-limited fit letterboxed 240 world-pixels (4.6 rows) away into
  /// bars. Phone-first by decision; other aspects letterbox and the game
  /// surface paints that ground itself.
  static const worldHeight = 1040.0;

  /// Overlay key shown when the game ends (built by the game view).
  static const gameOverOverlayKey = 'gameOver';

  /// Overlay key shown while the run is paused (built by the game view).
  static const pauseOverlayKey = 'pause';

  /// Bubbles at or past this row cross the fail line.
  ///
  /// As low as the shooter allows, at y = 861. Row 17 would sit at y = 913,
  /// which the squad's own art would then have to overlap.
  static const failRow = 16;

  /// At a fixed ceiling offset, rows 7–15 survive and row 16 loses.
  /// The live cadence descends after shot six, so a no-clear stack from the
  /// opening peak survives eight shots and loses on the ninth.
  /// An eighth seeded row would spend one row of both budgets straight back.
  static const startRows = 7;

  /// The ceiling descends one row after this many shots.
  static const shotsPerDescent = 6;
  static const minimumShotsPerDescent = 3;

  /// Assistance is a pure function of how far the ceiling has descended, so
  /// the HUD and the aim guide can never disagree about the current level.
  ///
  /// The thresholds moved one descent later on 2026-09-16; the reason is the
  /// threshold reconciliation in `docs/specs/2026-08-10-vertical-budget-and-run-variety.md`.
  static PressureState _pressureFor(int ceilingOffset, int shotsUntilDescent) => (
    aimAssist: switch (ceilingOffset) {
      0 => AimAssistLevel.full,
      1 || 2 => AimAssistLevel.trajectory,
      3 || 4 => AimAssistLevel.direction,
      _ => AimAssistLevel.hidden,
    },
    ceilingOffset: ceilingOffset,
    colorCount: switch (ceilingOffset) {
      0 || 1 => 4,
      2 || 3 => 5,
      _ => 6,
    },
    shotsUntilDescent: shotsUntilDescent,
  );

  static const geometry = BoardGeometry(
    columns: columns,
    bubbleRadius: bubbleRadius,
  );
  static const solver = TrajectorySolver(geometry: geometry);

  final AppLocalizations l10n;
  final PlaySfx playSfx;
  final TextStyle textStyle;

  /// Fixed seed reproduces the same board and queue; null is random.
  final int? seed;

  /// As low as the squad's art allows: at the shooter's scale its body bottom
  /// lands at y = 1030 in a 1040-tall world, and its arm still clears the
  /// fail line at y = 861. Every row the shooter moves down is a row of
  /// stacking grace, so this is pushed as far as the art permits.
  final Vector2 shooterOrigin = Vector2(worldWidth / 2, 970);

  late BubbleBoard board;
  late math.Random _random;
  GameStatus status = GameStatus.aiming;
  int _transitionGeneration = 0;

  /// Current score; listen for HUD updates.
  final ValueNotifier<int> scoreNotifier = ValueNotifier(0);
  final ValueNotifier<PressureState> pressureNotifier = ValueNotifier(
    _pressureFor(0, shotsPerDescent),
  );

  /// Shots landed this run.
  int shotCount = 0;

  /// Deepest world row (board row + ceiling offset) reached this run.
  int maxOccupiedRows = 0;

  /// Whether the rewarded Continue was already used this run.
  bool continuedThisRun = false;

  /// Whether this run's first scoring bank shot already explained the rule.
  /// Per run, not per install: Continue keeps it, restart clears it.
  bool _bankRuleExplained = false;

  /// The assistance notice's center: 90 above the fail row's center
  /// (y = 861), where the aim guide it describes is drawn.
  static const assistNoticeY = 771.0;
  final List<AimAssistNoticeComponent> _assistNotices = [];

  final StreamController<GameEvent> _events = StreamController.broadcast();

  /// Domain events for the session layer; the game never learns who listens.
  Stream<GameEvent> get events => _events.stream;

  int get score => scoreNotifier.value;
  PressureState get pressure => pressureNotifier.value;

  /// Changes whenever an active gesture must not survive into later input.
  int get inputGeneration => _transitionGeneration;

  /// Rows the ceiling has descended; board-local row r sits at world row
  /// `r + ceilingOffset`.
  int ceilingOffset = 0;
  late LauncherShot currentShot;
  late LauncherShot nextShot;

  BubbleColor get currentColor => currentShot.color;
  set currentColor(BubbleColor value) {
    currentShot = (color: value, kind: ShotKind.normal);
  }

  BubbleColor get nextColor => nextShot.color;
  set nextColor(BubbleColor value) {
    nextShot = (color: value, kind: ShotKind.normal);
  }

  late final BoardComponent boardComponent;
  late final AimGuideComponent aimGuide;

  final DefenderMotion defenderMotion = DefenderMotion();

  /// Per-color engraved bubble art; a missing entry falls back to
  /// procedural gloss (tests, pre-preload frames).
  final Map<BubbleColor, Sprite> _bubbleSprites = {};

  /// Squad body layers and the rotating launcher arm; null skips the
  /// mascot entirely (tests, pre-preload frames).
  Sprite? shooterBodyIdle;
  Sprite? shooterBodyShooting;
  Sprite? shooterArm;

  /// Radians from straight up, positive toward the right wall; the launcher
  /// arm is the permanent aim cue, so this survives assist degradation.
  double aimAngle = 0;

  ShotResult? _aimedShot;

  /// Whether releasing right now would fire. The launcher arm ghosts while
  /// this is false, so a rejected aim (level or downward) can never present
  /// a valid-looking direction that fires nothing.
  bool get hasAimedShot => _aimedShot != null;

  Sprite? bubbleSpriteFor(BubbleColor color) => _bubbleSprites[color];

  @override
  Color backgroundColor() => const Color(0xFF16213E);

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    for (final color in BubbleColor.values) {
      final sprite = _spriteIfCached(color.spriteAsset);
      if (sprite != null) _bubbleSprites[color] = sprite;
    }
    shooterBodyIdle = _spriteIfCached(Assets.images.shooterBodyIdle);
    shooterBodyShooting = _spriteIfCached(Assets.images.shooterBodyShooting);
    shooterArm = _spriteIfCached(Assets.images.shooterArm);
    boardComponent = BoardComponent();
    aimGuide = AimGuideComponent();
    await world.addAll([
      BackgroundComponent(),
      boardComponent,
      AimInputComponent(),
      ShooterComponent(),
    ]);
    await boardComponent.add(aimGuide);
    startGame();
  }

  /// Wraps a preloaded image in a [Sprite], or null when it was never cached
  /// (tests, pre-preload frames). `fromCache` throws on a miss, so the
  /// `containsKey` guard is required.
  Sprite? _spriteIfCached(AssetGenImage asset) =>
      images.containsKey(asset.path) ? Sprite(images.fromCache(asset.path)) : null;

  void startGame() {
    _transitionGeneration++;
    defenderMotion.reset();
    _random = math.Random(seed);
    scoreNotifier.value = 0;
    ceilingOffset = 0;
    pressureNotifier.value = _pressureFor(ceilingOffset, shotsPerDescent);
    board = BubbleBoard(columns: columns);
    seedOpeningFormation(
      board: board,
      startRows: startRows,
      random: _random,
      palette: _activeColors,
    );
    boardComponent.resetPosition();
    currentShot = _drawShot();
    nextShot = _drawShot();
    status = GameStatus.aiming;
    shotCount = 0;
    maxOccupiedRows = board.bottomRow;
    continuedThisRun = false;
    _bankRuleExplained = false;
    _clearAssistNotices();
    _events.add(const RunStarted());
    _aimedShot = null;
    aimAngle = 0;
    aimGuide
      ..path = null
      ..showLanding = true;
    overlays.remove(gameOverOverlayKey);
    boardComponent.syncBoard();
  }

  List<BubbleColor> get _activeColors => BubbleColor.values.take(pressure.colorCount).toList(growable: false);

  LauncherShot _drawShot() {
    final roll = _random.nextInt(16);
    final kind = switch (roll) {
      0 => ShotKind.bomb,
      1 => ShotKind.rainbow,
      _ => ShotKind.normal,
    };
    return (color: _drawColor(), kind: kind);
  }

  /// Introduces newly unlocked colors, then draws from active board colors.
  BubbleColor _drawColor() {
    final active = _activeColors;
    final activeSet = active.toSet();
    final present = board.occupiedCells.map(board.bubbleAt).nonNulls.where(activeSet.contains).toSet();
    final missing = active.where((color) => !present.contains(color)).toList();
    final candidates = missing.isNotEmpty
        ? missing
        : present.isEmpty
        ? active
        : (present.toList()..sort((a, b) => a.index.compareTo(b.index)));
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Updates the aim guide toward [target] (world coordinates). The solver
  /// runs in board-local coordinates, offset by the descended ceiling.
  void aimAt(Vector2 target) {
    if (status != GameStatus.aiming) return;
    final direction = target - shooterOrigin;
    if (direction.y < 0) {
      // Mirror the solver's clamp so the arm cue and the resolved shot agree.
      aimAngle = math
          .atan2(direction.x, -direction.y)
          .clamp(-TrajectorySolver.maxAimAngle, TrajectorySolver.maxAimAngle);
    }
    final boardOriginY = shooterOrigin.y - ceilingOffset * geometry.rowHeight;
    _aimedShot = solver.solve(
      board: board,
      origin: math.Point(shooterOrigin.x, boardOriginY),
      direction: math.Point(direction.x, direction.y),
    );
    final projection = _aimGuideFor(_aimedShot);
    aimGuide
      ..showLanding = projection.showLanding
      ..path = projection.path;
  }

  /// Fires the currently aimed shot, if any.
  void fire() {
    if (status != GameStatus.aiming) return;
    final shot = _aimedShot;
    _aimedShot = null;
    aimGuide.path = null;
    if (shot == null) return;
    status = GameStatus.flying;
    _events.add(const ShotFired());
    playSfx(Assets.audio.shoot);
    final projectile = ProjectileComponent.shot(result: shot, shot: currentShot);
    defenderMotion.beginShot(flightSeconds: projectile.flightSeconds);
    boardComponent.add(projectile);
  }

  /// Commits the board mutation for a landed shot: pop matches, drop
  /// floating clusters, update score, then advance the queue.
  void onShotLanded(ShotResult result) {
    shotCount++;
    final shot = currentShot;
    HexCell? landing;
    BubbleColor? landingColor;
    var popped = <HexCell>{};
    var dropped = <HexCell>{};
    var reachedDepth = board.bottomRow + ceilingOffset;

    if (shot.kind == ShotKind.bomb) {
      popped = {
        for (final neighbor in result.landingCell.neighbors)
          if (board.isOccupied(neighbor)) neighbor,
      }..forEach(board.remove);
      dropped = board.floatingBubbles()..forEach(board.remove);
    } else {
      landing = result.landingCell;
      landingColor = shot.kind == ShotKind.rainbow && result.contactCell != null
          ? board.bubbleAt(result.contactCell!)!
          : shot.color;
      board.place(landing, landingColor);
      reachedDepth = board.bottomRow + ceilingOffset;
      final match = board.matchGroup(landing);
      if (match.length >= 3) {
        popped = match..forEach(board.remove);
        dropped = board.floatingBubbles()..forEach(board.remove);
      }
    }
    // Sample after placement but before the common end-of-turn path. A
    // removed landing still reached that depth; bombs retain the pre-blast
    // board depth because they never occupy their landing cell.
    maxOccupiedRows = math.max(
      maxOccupiedRows,
      reachedDepth,
    );

    switch (shot.kind) {
      case ShotKind.bomb:
        playSfx(Assets.audio.bomb);
      case ShotKind.rainbow:
        playSfx(Assets.audio.rainbow);
      case ShotKind.normal:
        break;
    }
    var gained = 0;
    var multiplier = 1;
    if (popped.isNotEmpty || dropped.isNotEmpty) {
      // path = origin, one point per wall bounce, contact, landing.
      final bounces = result.path.length - 3;
      multiplier = bounces + 1;
      gained = (popped.length * 10 + dropped.length * 20) * multiplier;
      scoreNotifier.value += gained;
      playSfx(Assets.audio.pop);
    }
    boardComponent
      ..applyShot(
        landing: landing,
        color: landingColor,
        popped: popped,
        dropped: dropped,
        kind: shot.kind,
      )
      ..showSpecialShotFeedback(
        shot: shot,
        result: result,
        resolvedColor: landingColor,
        popped: popped,
      );
    if (gained > 0) {
      final explainRule = multiplier > 1 && !_bankRuleExplained;
      _bankRuleExplained |= explainRule;
      boardComponent.showScoreCallout(
        landing: result.landingCell,
        points: gained,
        multiplier: multiplier,
        explainRule: explainRule,
      );
    }

    defenderMotion.finishShot(scored: gained > 0, dropped: dropped.isNotEmpty);
    if (board.isEmpty) {
      status = GameStatus.victory;
      defenderMotion.endRun(victory: true);
      _events.add(GameOverReached(_stats(GameOverReason.victory)));
      playSfx(Assets.audio.gameover);
      overlays.add(gameOverOverlayKey);
      return;
    }

    final previousAssist = pressure.aimAssist;
    _advancePressure();
    // Sample again after a possible descent: the surviving board now sits
    // one world row deeper whether or not that crosses the fail line.
    maxOccupiedRows = math.max(
      maxOccupiedRows,
      board.bottomRow + ceilingOffset,
    );

    if (board.bottomRow + ceilingOffset >= failRow) {
      status = GameStatus.defeat;
      defenderMotion.endRun(victory: false);
      _events.add(GameOverReached(_stats(GameOverReason.defeat)));
      playSfx(Assets.audio.gameover);
      overlays.add(gameOverOverlayKey);
    } else {
      // Announced only once the run survives the descent: a tier the player
      // will never aim with is noise over the game-over panel.
      if (pressure.aimAssist.index > previousAssist.index) _announceAssist();
      currentShot = nextShot;
      nextShot = _drawShot();
      if (status != GameStatus.transitioning) {
        status = GameStatus.aiming;
      }
    }
  }

  GameOverStats _stats(GameOverReason reason) => GameOverStats(
    score: score,
    shotCount: shotCount,
    maxOccupiedRows: maxOccupiedRows,
    ceilingDepth: ceilingOffset,
    continued: continuedThisRun,
    reason: reason,
  );

  /// Applies the rewarded Continue (spec §3). Returns false — the typed
  /// failure — when the game is not defeated or was already continued.
  bool revive() {
    if (status != GameStatus.defeat || continuedThisRun) return false;
    defenderMotion.reset();
    continuedThisRun = true;
    final result = applyRevive(
      board: board,
      ceilingOffset: ceilingOffset,
      failRow: failRow,
    );
    ceilingOffset = result.ceilingOffset;
    // The retreat can raise the tier again, so a notice for the lower one
    // would now contradict the HUD and the guide.
    _clearAssistNotices();
    boardComponent.syncBoard();
    pressureNotifier.value = _pressureFor(
      ceilingOffset,
      math.max(minimumShotsPerDescent, shotsPerDescent - ceilingOffset),
    );
    // The defeated shot consumed the current launcher shot; advance once.
    currentShot = nextShot;
    nextShot = _drawShot();
    overlays.remove(gameOverOverlayKey);
    _startCeilingTransition();
    return true;
  }

  void _startCeilingTransition() {
    final generation = ++_transitionGeneration;
    status = GameStatus.transitioning;
    boardComponent.slideToCeilingOffset(
      onComplete: () {
        if (generation == _transitionGeneration && status == GameStatus.transitioning) {
          status = GameStatus.aiming;
        }
      },
    );
  }

  AimGuideProjection _aimGuideFor(ShotResult? shot) {
    switch (pressure.aimAssist) {
      case AimAssistLevel.full:
        return (path: shot?.path, showLanding: true);
      case AimAssistLevel.trajectory:
        return (path: shot?.path, showLanding: false);
      case AimAssistLevel.direction:
        final path = shot?.path;
        return (
          path: path?.take(2).toList(growable: false),
          showLanding: false,
        );
      case AimAssistLevel.hidden:
        return (path: null, showLanding: false);
    }
  }

  void _advancePressure() {
    final remaining = pressure.shotsUntilDescent - 1;
    if (remaining > 0) {
      pressureNotifier.value = _pressureFor(ceilingOffset, remaining);
      return;
    }

    ceilingOffset++;
    // Only the branch that actually descends. Firing above the early
    // return would sound the warning every shot and mean nothing.
    playSfx(Assets.audio.descent);
    _startCeilingTransition();
    pressureNotifier.value = _pressureFor(
      ceilingOffset,
      math.max(minimumShotsPerDescent, shotsPerDescent - ceilingOffset),
    );
  }

  void _clearAssistNotices() {
    for (final notice in _assistNotices) {
      notice.removeFromParent();
    }
    _assistNotices.clear();
  }

  /// Names the tier a descent just lowered assistance to, above the fail
  /// line where the aim guide is drawn.
  void _announceAssist() {
    _assistNotices.removeWhere((notice) => notice.isRemoved);
    final notice = AimAssistNoticeComponent(
      title: l10n.aimAssistReduced,
      label: pressure.aimAssist.label(l10n),
      style: textStyle,
      position: Vector2(worldWidth / 2, assistNoticeY),
    );
    _assistNotices.add(notice);
    world.add(notice);
  }
}
