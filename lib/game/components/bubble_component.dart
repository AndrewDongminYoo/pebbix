// 🎯 Dart imports:
import 'dart:math' as math;

// 🐦 Flutter imports:
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/particles.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

extension BubbleColorSprite on BubbleColor {
  /// The engraved sprite each color ships with. The board and the rules
  /// page's legend both read it here, so the legend cannot show a bubble the
  /// board never draws.
  AssetGenImage get spriteAsset => switch (this) {
    BubbleColor.red => Assets.images.bubbleRed,
    BubbleColor.yellow => Assets.images.bubbleYellow,
    BubbleColor.green => Assets.images.bubbleGreen,
    BubbleColor.blue => Assets.images.bubbleBlue,
    BubbleColor.purple => Assets.images.bubblePurple,
    BubbleColor.orange => Assets.images.bubbleOrange,
  };
}

extension BubbleColorPalette on BubbleColor {
  /// Dominant fill sampled from the matching engraved sprite, so the
  /// procedural fallback and pop particles agree with the shipped art.
  Color get displayColor => switch (this) {
    BubbleColor.red => const Color(0xFFF84848),
    BubbleColor.yellow => const Color(0xFFF8B840),
    BubbleColor.green => const Color(0xFF78E0C0),
    BubbleColor.blue => const Color(0xFF0078F8),
    BubbleColor.purple => const Color(0xFFB890E0),
    BubbleColor.orange => const Color(0xFFF89060),
  };
}

/// Draws a bubble — the per-color engraved [sprite] when available, otherwise
/// a procedural radial-gradient body with a specular highlight. Shared by
/// board bubbles, the projectile, and the shooter preview.
void paintBubble(
  Canvas canvas,
  Offset center,
  double radius,
  BubbleColor color, {
  Sprite? sprite,
}) {
  if (sprite != null) {
    sprite.render(
      canvas,
      position: Vector2(center.dx - radius, center.dy - radius),
      size: Vector2.all(radius * 2),
    );
    return;
  }
  final base = color.displayColor;
  final gradient = RadialGradient(
    center: const Alignment(-0.35, -0.4),
    colors: [
      Color.lerp(base, const Color(0xFFFFFFFF), 0.45)!,
      base,
      Color.lerp(base, const Color(0xFF000000), 0.35)!,
    ],
    stops: const [0, 0.55, 1],
  );
  final rect = Rect.fromCircle(center: center, radius: radius);
  canvas
    ..drawCircle(center, radius, Paint()..shader = gradient.createShader(rect))
    ..drawOval(
      Rect.fromCenter(
        center: center + Offset(-radius * 0.35, -radius * 0.45),
        width: radius * 0.55,
        height: radius * 0.35,
      ),
      Paint()..color = const Color(0x66FFFFFF),
    );
}

/// Draws one launcher/projectile shot over its normal engraved base.
void paintLauncherShot(
  Canvas canvas,
  Offset center,
  double radius,
  LauncherShot shot, {
  Sprite? sprite,
}) {
  paintBubble(canvas, center, radius, shot.color, sprite: sprite);
  switch (shot.kind) {
    case ShotKind.normal:
      return;
    case ShotKind.bomb:
      final core = Paint()..color = const Color(0xE6101828);
      final fuse = Paint()
        ..color = const Color(0xFF101828)
        ..strokeWidth = radius * 0.14
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawCircle(center, radius * 0.38, core)
        ..drawLine(
          center + Offset(radius * 0.2, -radius * 0.3),
          center + Offset(radius * 0.48, -radius * 0.62),
          fuse,
        )
        ..drawCircle(
          center + Offset(radius * 0.52, -radius * 0.66),
          radius * 0.11,
          Paint()..color = const Color(0xFFFFD166),
        );
    case ShotKind.rainbow:
      final ring = Rect.fromCircle(center: center, radius: radius * 0.74);
      final sweep = 2 * math.pi / BubbleColor.values.length;
      for (final color in BubbleColor.values) {
        canvas.drawArc(
          ring,
          -math.pi / 2 + color.index * sweep,
          sweep * 0.88,
          false,
          Paint()
            ..color = color.displayColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.18
            ..strokeCap = StrokeCap.round,
        );
      }
  }
}

class BubbleComponent extends PositionComponent with HasGameReference<BubbleShooter> {
  new({
    required this.color,
    required Vector2 position,
    this.kind = ShotKind.normal,
  }) : super(
         position: position,
         size: Vector2.all(BubbleShooter.bubbleRadius * 2),
         anchor: Anchor.center,
       );

  final BubbleColor color;
  final ShotKind kind;

  static const popDuration = 0.15;

  static final _particleRandom = math.Random();

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    paintLauncherShot(
      canvas,
      const Offset(BubbleShooter.bubbleRadius, BubbleShooter.bubbleRadius),
      BubbleShooter.bubbleRadius,
      (color: color, kind: kind),
      sprite: game.bubbleSpriteFor(color),
    );
  }

  /// Quick squash-and-settle used when a shot snaps into place.
  void settle() {
    scale = Vector2(1.2, 0.85);
    add(ScaleEffect.to(Vector2.all(1), EffectController(duration: 0.12)));
  }

  /// Burst into particles and disappear (popped match).
  void pop({bool emitParticles = true, double delay = 0}) {
    if (emitParticles) _spawnBurst();
    add(
      ScaleEffect.to(
        Vector2.zero(),
        EffectController(duration: popDuration, startDelay: delay),
        onComplete: removeFromParent,
      ),
    );
  }

  /// Fall off the board when disconnected from the ceiling.
  void drop() {
    add(
      MoveEffect.by(
        Vector2(0, BubbleShooter.worldHeight),
        EffectController(duration: 0.5, curve: Curves.easeInQuad),
        onComplete: removeFromParent,
      ),
    );
  }

  void _spawnBurst() {
    final paint = Paint()..color = color.displayColor;
    parent?.add(
      ParticleSystemComponent(
        position: position.clone(),
        particle: Particle.generate(
          count: 8,
          lifespan: 0.4,
          generator: (i) {
            final angle = (i + _particleRandom.nextDouble()) * (2 * math.pi / 8);
            return AcceleratedParticle(
              speed: Vector2(math.cos(angle), math.sin(angle)) * 180,
              acceleration: Vector2(0, 400),
              child: CircleParticle(radius: 5, paint: paint),
            );
          },
        ),
      ),
    );
  }
}
