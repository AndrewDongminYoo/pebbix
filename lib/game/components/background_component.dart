// 🎯 Dart imports:
import 'dart:math' as math;

// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

/// Quiet deep-sea backdrop: the preloaded background art (cover-cropped to
/// the world's aspect ratio) plus faint ambient bubbles drifting upward.
class BackgroundComponent extends PositionComponent with HasGameReference<BubbleShooter> {
  new()
    : super(
        size: Vector2(BubbleShooter.worldWidth, BubbleShooter.worldHeight),
      );

  static const _ambientCount = 14;

  final _random = math.Random();
  final List<_AmbientBubble> _ambient = [];

  Sprite? _sprite;

  static final _bubblePaint = Paint()..color = const Color(0x12FFFFFF);

  static final _fallbackPaint = Paint()
    ..shader =
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2B52), Color(0xFF16213E), Color(0xFF0B1226)],
        ).createShader(
          const Rect.fromLTWH(
            0,
            0,
            BubbleShooter.worldWidth,
            BubbleShooter.worldHeight,
          ),
        );

  @override
  Future<void> onLoad() async {
    // The art is decorative: tests (and any frame before preload) run
    // without the image cache, so fall back to a plain gradient.
    if (game.images.containsKey(Assets.images.background.path)) {
      final image = game.images.fromCache(Assets.images.background.path);
      // Cover-crop the source to the world's aspect ratio.
      final targetRatio = size.x / size.y;
      final srcWidth = math.min(
        image.width.toDouble(),
        image.height * targetRatio,
      );
      final srcHeight = srcWidth / targetRatio;
      _sprite = Sprite(
        image,
        srcPosition: Vector2(
          (image.width - srcWidth) / 2,
          (image.height - srcHeight) / 2,
        ),
        srcSize: Vector2(srcWidth, srcHeight),
      );
    }
    for (var i = 0; i < _ambientCount; i++) {
      _ambient.add(_spawn(anywhere: true));
    }
  }

  _AmbientBubble _spawn({bool anywhere = false}) => _AmbientBubble(
    x: _random.nextDouble() * BubbleShooter.worldWidth,
    y: anywhere ? _random.nextDouble() * BubbleShooter.worldHeight : BubbleShooter.worldHeight + 10,
    radius: 2 + _random.nextDouble() * 6,
    speed: 12 + _random.nextDouble() * 25,
  );

  @override
  void update(double dt) {
    super.update(dt);
    for (var i = 0; i < _ambient.length; i++) {
      final bubble = _ambient[i];
      bubble.y -= bubble.speed * dt;
      if (bubble.y < -bubble.radius) {
        _ambient[i] = _spawn();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final sprite = _sprite;
    if (sprite != null) {
      sprite.render(canvas, size: size);
    } else {
      canvas.drawRect(size.toRect(), _fallbackPaint);
    }
    for (final bubble in _ambient) {
      canvas.drawCircle(
        Offset(bubble.x, bubble.y),
        bubble.radius,
        _bubblePaint,
      );
    }
  }
}

class _AmbientBubble {
  new({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
  });

  final double x;
  double y;
  final double radius;
  final double speed;
}
