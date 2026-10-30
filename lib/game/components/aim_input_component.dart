// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flame/events.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';

/// Fixed full-screen layer that owns aim input and draws the world-fixed
/// fail line. Press (or drag) anywhere to aim from the shooter, release to
/// fire — a plain tap is just a zero-length drag, so [DragCallbacks] alone
/// covers both gestures (mixing in TapCallbacks as well makes the two
/// recognizers fight in the gesture arena and swallow the release event).
class AimInputComponent extends PositionComponent with HasGameReference<BubbleShooter>, DragCallbacks {
  new()
    : super(
        size: Vector2(BubbleShooter.worldWidth, BubbleShooter.worldHeight),
      );

  Vector2 _aimPoint = Vector2.zero();
  final Map<int, int> _eligibleDragGenerations = {};

  static final _failLinePaint = Paint()
    ..color = const Color(0xCCE94560)
    ..strokeWidth = 3;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const geometry = BubbleShooter.geometry;
    final y = geometry.bubbleRadius + BubbleShooter.failRow * geometry.rowHeight;
    canvas.drawLine(Offset(0, y), Offset(width, y), _failLinePaint);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (game.status != GameStatus.aiming) return;
    _eligibleDragGenerations[event.pointerId] = game.inputGeneration;
    _aimPoint = event.localPosition.clone();
    game.aimAt(_aimPoint);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_eligibleDragGenerations[event.pointerId] != game.inputGeneration) {
      _eligibleDragGenerations.remove(event.pointerId);
      return;
    }
    _aimPoint += event.localDelta;
    game.aimAt(_aimPoint);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final inputGeneration = _eligibleDragGenerations.remove(event.pointerId);
    if (inputGeneration != game.inputGeneration) return;
    game.fire();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    // Flame forwards cancel to this component's onDragEnd with the same
    // pointer id, preserving the start-time eligibility decision.
    super.onDragCancel(event);
  }
}
