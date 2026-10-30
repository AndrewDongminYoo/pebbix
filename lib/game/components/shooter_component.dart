// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/game/components/defender_squad.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

/// Draws the defender squad, the rotating launcher arm, the current bubble
/// at the launch position, and the next-up preview.
///
/// The squad body never rotates; only the arm turns with the aim, so its
/// orientation stays readable as the permanent direction cue after the
/// trajectory preview degrades away (spec §5).
class ShooterComponent extends PositionComponent with HasGameReference<BubbleShooter> {
  new();

  DefenderSquad? _squad;

  /// Source canvas edge of the body and arm layers.
  static const _canvasSize = 1254.0;

  /// The body layers seat by their socket-ring eyelet, which measures
  /// (627, 901) on the idle sprite and (627, 905) on the shooting sprite —
  /// close enough for one shared anchor per state pair
  /// (docs/notes/art/and-102-production-art-pack.md, "Registration alignment").
  static const _bodyAnchor = Offset(627, 903);

  /// The arm rotates around its hub knob, whose circular bulge centers at
  /// (627, ~920) by row-width profile; the AND-101 layer contract records
  /// (627, 925). The two differ from the body eyelet, so the arm keeps its
  /// own pivot instead of sharing the body anchor.
  static const _armPivot = Offset(627, 925);

  /// Topmost source row the arm layer covers, so the tip reaches
  /// `_armPivot.dy - _armTop` above the pivot at full elevation.
  static const _armTop = 611.0;

  /// World units per source-canvas pixel.
  ///
  /// Measured, not eyeballed: the body art occupies source rows 658-1104
  /// around its 903 anchor and the arm 611-979 around its 925 pivot, so at a
  /// given scale the arm reaches `314 * scale` above the launch point. From
  /// the shooter's y = 970 the old 0.42 put the tip at y = 838, above the
  /// fail row's center at y = 861 — the launcher poked into the play area.
  /// At 0.30 the tip sits at 876 and clears it, while the squad's bottom
  /// lands at 1030 in a 1040-tall world, which is what lets the shooter sit
  /// low enough for a tenth row of stacking grace (AND-121).
  static const _artScale = 0.30;

  /// How far above the launch point the arm tip reaches at full elevation.
  ///
  /// Public so the clearance over the fail row is pinned by a test instead of
  /// by the arithmetic in the comment above — a retune of [_artScale] or of
  /// [BubbleShooter.failRow] has to keep the launcher out of the play area.
  static final double armReach = (_armPivot.dy - _armTop) * _artScale;

  /// Layer placement is invariant (derived from compile-time constants), so it
  /// is computed once instead of per frame. All are read-only in [render].
  static final Vector2 _bodyOffset = Vector2(
    -_bodyAnchor.dx * _artScale,
    -_bodyAnchor.dy * _artScale,
  );
  static final Vector2 _armOffset = Vector2(
    -_armPivot.dx * _artScale,
    -_armPivot.dy * _artScale,
  );
  static final Vector2 _layerSize = Vector2.all(_canvasSize * _artScale);

  /// Ghost treatment for the arm while no shot is armed — a rejected aim
  /// must never look ready to fire.
  static final Paint _disarmedPaint = Paint()..color = const Color(0x73FFFFFF);

  @override
  Future<void> onLoad() async {
    position = game.shooterOrigin.clone();
    if (game.images.containsKey(Assets.images.defenderSquad.path)) {
      _squad = DefenderSquad(game.images.fromCache(Assets.images.defenderSquad.path));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    game.defenderMotion.update(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderMascot(canvas);
    if (game.status == GameStatus.victory || game.status == GameStatus.defeat) {
      return;
    }
    if (game.status == GameStatus.aiming || game.status == GameStatus.transitioning) {
      paintLauncherShot(
        canvas,
        Offset.zero,
        BubbleShooter.bubbleRadius,
        game.currentShot,
        sprite: game.bubbleSpriteFor(game.currentColor),
      );
    }
    if (_squad == null) {
      paintLauncherShot(
        canvas,
        const Offset(-90, 30),
        BubbleShooter.bubbleRadius * 0.55,
        game.nextShot,
        sprite: game.bubbleSpriteFor(game.nextColor),
      );
    }
  }

  /// Body first, seated by its own anchor; then the arm, rotated about its own
  /// hub pivot. Each layer's anchor maps to this component's local origin (the
  /// launch position).
  void _renderMascot(Canvas canvas) {
    final squad = _squad;
    if (squad != null) {
      squad.render(canvas, game);
    } else {
      final body = game.status == GameStatus.flying
          ? (game.shooterBodyShooting ?? game.shooterBodyIdle)
          : game.shooterBodyIdle;
      body?.render(canvas, position: _bodyOffset, size: _layerSize);
    }

    final arm = game.shooterArm;
    if (arm == null) return;
    canvas
      ..save()
      ..rotate(game.aimAngle);
    arm.render(
      canvas,
      position: _armOffset,
      size: _layerSize,
      overridePaint: game.hasAimedShot ? null : _disarmedPaint,
    );
    canvas.restore();
  }
}
