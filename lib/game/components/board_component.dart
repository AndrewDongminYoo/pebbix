// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flame/effects.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/game/components/projectile_component.dart';
import 'package:bubble_shooter/game/components/score_callout_component.dart';
import 'package:bubble_shooter/game/components/special_shot_effect_component.dart';
import 'package:bubble_shooter/game/domain/domain.dart';

/// The moving bubble grid. Its world y-offset is the descended ceiling;
/// all children (bubbles, aim guide, projectile) live in board-local
/// coordinates, which is also the trajectory solver's space.
class BoardComponent extends PositionComponent with HasGameReference<BubbleShooter> {
  new()
    : super(
        size: Vector2(BubbleShooter.worldWidth, BubbleShooter.worldHeight),
      );

  final Map<HexCell, BubbleComponent> _bubbles = {};
  MoveToEffect? _ceilingSlide;
  final List<SpecialShotEffectComponent> _specialShotEffects = [];
  final List<ScoreCalloutComponent> _scoreCallouts = [];

  /// Rebuilds all bubble components from the domain board state.
  void syncBoard() {
    for (final bubble in {..._bubbles.values, ...children.whereType<BubbleComponent>()}) {
      bubble.removeFromParent();
    }
    _bubbles.clear();
    for (final cell in game.board.occupiedCells) {
      _addBubble(cell, game.board.bubbleAt(cell)!);
    }
  }

  /// Applies the visual diff of one landed shot.
  void applyShot({
    required HexCell? landing,
    required BubbleColor? color,
    required Set<HexCell> popped,
    required Set<HexCell> dropped,
    ShotKind kind = ShotKind.normal,
  }) {
    assert(
      (landing == null) == (color == null),
      'landing and color must both be present or absent',
    );
    if (landing != null && color != null) {
      _addBubble(landing, color);
      if (!popped.contains(landing)) {
        _bubbles[landing]?.settle();
      }
    }
    for (final cell in popped) {
      _bubbles
          .remove(cell)
          ?.pop(
            emitParticles: kind == ShotKind.normal,
            delay: kind == ShotKind.rainbow ? SpecialShotEffectComponent.rainbowConversionTime : 0,
          );
    }
    for (final cell in dropped) {
      _bubbles.remove(cell)?.drop();
    }
  }

  /// Presents the captured outcome without consulting the mutated board.
  void showSpecialShotFeedback({
    required LauncherShot shot,
    required ShotResult result,
    required BubbleColor? resolvedColor,
    required Set<HexCell> popped,
  }) {
    if (shot.kind == ShotKind.normal) return;
    final landing = BubbleShooter.geometry.center(result.landingCell);
    Offset relativeCenter(HexCell cell) {
      final center = BubbleShooter.geometry.center(cell);
      return Offset(center.x - landing.x, center.y - landing.y);
    }

    _specialShotEffects.removeWhere((effect) => effect.isRemoved);
    final color = resolvedColor ?? shot.color;
    final effect = SpecialShotEffectComponent(
      kind: shot.kind,
      resolvedColor: color,
      position: Vector2(landing.x, landing.y),
      contactOffset: result.contactCell == null ? null : relativeCenter(result.contactCell!),
      clearedOffsets: popped.map(relativeCenter).toList(),
      resolvedSprite: game.bubbleSpriteFor(color),
    );
    _specialShotEffects.add(effect);
    add(effect);
  }

  /// Shows what a scoring shot added at [landing]: the points, the bank
  /// multiplier when [multiplier] is above one, and the rule itself when
  /// [explainRule] is set.
  void showScoreCallout({
    required HexCell landing,
    required int points,
    required int multiplier,
    required bool explainRule,
  }) {
    final center = BubbleShooter.geometry.center(landing);
    _scoreCallouts.removeWhere((callout) => callout.isRemoved);
    final callout = ScoreCalloutComponent(
      points: points,
      style: game.textStyle,
      position: Vector2(center.x, center.y),
      bankLabel: multiplier > 1 ? game.l10n.scoreCalloutBank(multiplier) : null,
      ruleText: explainRule ? game.l10n.scoreCalloutBankRule : null,
    );
    _scoreCallouts.add(callout);
    add(callout);
  }

  /// Animates the grid to its current ceiling offset.
  void slideToCeilingOffset({void Function()? onComplete}) {
    _ceilingSlide?.removeFromParent();
    _ceilingSlide = MoveToEffect(
      Vector2(0, game.ceilingOffset * BubbleShooter.geometry.rowHeight),
      EffectController(duration: 0.3),
      onComplete: onComplete,
    );
    add(_ceilingSlide!);
  }

  /// Immediately resets the grid position and drops any shot still in
  /// flight (new game). A surviving projectile would finish its path over
  /// the freshly seeded board and commit the previous run's landing to it.
  void resetPosition() {
    for (final effect in _specialShotEffects) {
      effect.removeFromParent();
    }
    _specialShotEffects.clear();
    for (final callout in _scoreCallouts) {
      callout.removeFromParent();
    }
    _scoreCallouts.clear();
    _ceilingSlide?.removeFromParent();
    _ceilingSlide = null;
    position = Vector2.zero();
    for (final projectile in children.whereType<ProjectileComponent>()) {
      projectile.removeFromParent();
    }
  }

  void _addBubble(HexCell cell, BubbleColor color) {
    final center = BubbleShooter.geometry.center(cell);
    final bubble = BubbleComponent(
      color: color,
      position: Vector2(center.x, center.y),
    );
    _bubbles[cell] = bubble;
    add(bubble);
  }
}
