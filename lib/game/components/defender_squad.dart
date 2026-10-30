// 🎯 Dart imports:
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/gen/defender_atlas.gen.dart';

/// Registered poses around the fixed launch socket, in shooter-local units.
/// The generated rectangles come from sprite-gen's manifest, not a grid guess.
class DefenderSquad {
  new(ui.Image atlas)
    : _poses = {
        for (final entry in defenderFrameRects.entries)
          entry.key: [
            for (final rect in entry.value)
              Sprite(
                atlas,
                srcPosition: Vector2(rect.left, rect.top),
                srcSize: Vector2(rect.width, rect.height),
              ),
          ],
      };

  final Map<String, List<Sprite>> _poses;

  static const _feet = Offset(128, 236);
  static const _loaderGrip = Offset(49, 151);
  static const _wrenchContacts = [
    Offset(202, 147),
    Offset(190, 148),
    Offset(209, 151),
    Offset(193, 148),
  ];
  static const _nextDockX = 70.0;
  static const _previewRadius = 16.5;

  void render(Canvas canvas, BubbleShooter game) {
    final motion = game.defenderMotion;
    _draw(canvas, 'base', 0, Offset.zero, const Offset(128, 80), 100 / 256);
    for (final right in [false, true]) {
      final lift = motion.idleLift(right: right) + motion.cheerLift(right: right);
      _draw(
        canvas,
        right ? 'peach_cheer' : 'mint_cheer',
        motion.cheerPose(right: right),
        Offset(right ? 166 : -163, 55 - lift),
        _feet,
        0.48,
      );
    }

    final mechanic = motion.mechanicPose(game.aimAngle);
    _draw(canvas, 'mechanic', mechanic, Offset.zero, _wrenchContacts[mechanic], 0.5);

    final ended = game.status == GameStatus.victory || game.status == GameStatus.defeat;
    if (!ended) {
      final radius = _previewRadius + _seating(motion.bubblePosition);
      paintLauncherShot(
        canvas,
        Offset(_nextDockX * motion.bubblePosition, 0),
        radius,
        game.nextShot,
        sprite: game.bubbleSpriteFor(game.nextColor),
      );
    }
    // Paint the hands over the carried bubble. Their contact follows the
    // bubble's growth into the socket, then the loader returns empty-handed.
    _draw(
      canvas,
      'loader',
      motion.loaderPose,
      Offset(_nextDockX * motion.loaderPosition, _seating(motion.loaderPosition)),
      _loaderGrip,
      0.48,
    );
  }

  double _seating(double position) =>
      (BubbleShooter.bubbleRadius - _previewRadius) * (1 - position / 0.25).clamp(0.0, 1.0);

  void _draw(Canvas canvas, String row, int pose, Offset position, Offset anchor, double scale) {
    final sprite = _poses[row]![pose];
    sprite.render(
      canvas,
      position: Vector2(position.dx - anchor.dx * scale, position.dy - anchor.dy * scale),
      size: sprite.srcSize * scale,
    );
  }
}
