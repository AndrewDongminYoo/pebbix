// 🎯 Dart imports:
import 'dart:math' as math;
import 'dart:ui';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/game/domain/domain.dart';

/// A snapshot of a resolved special shot, rendered in board-local space.
/// Its clock belongs to Flame, so pausing the game also pauses this feedback.
class SpecialShotEffectComponent extends PositionComponent {
  new({
    required this.kind,
    required this.resolvedColor,
    required super.position,
    this.contactOffset,
    List<Offset> clearedOffsets = const [],
    this.resolvedSprite,
  }) : clearedOffsets = List.unmodifiable(clearedOffsets),
       super(priority: 20);

  final ShotKind kind;
  final BubbleColor resolvedColor;
  final Offset? contactOffset;
  final List<Offset> clearedOffsets;
  final Sprite? resolvedSprite;
  static const duration = 0.72;

  /// Presentation-only delay: the board transaction still resolves at landing.
  static const rainbowConversionTime = 0.36;
  double _elapsed = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (_elapsed >= duration) return;
    switch (kind) {
      case ShotKind.bomb:
        _renderBomb(canvas);
      case ShotKind.rainbow:
        _renderRainbow(canvas);
      case ShotKind.normal:
        return;
    }
  }

  void _renderBomb(Canvas canvas) {
    const warm = Color(0xFFFFD166);
    const orange = Color(0xFFFF7830);
    final progress = _elapsed / duration;
    final opacity = 1 - progress;
    final expansion = math.sqrt(progress);
    final radius = 20 + 52 * expansion;
    // A jagged filled impact, then a thick outward wave. No dot debris.
    final coreOpacity = (1 - _elapsed / 0.24).clamp(0.0, 1.0);
    final core = Path();
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final reach = (i.isEven ? 1.0 : 0.48) * (22 + 34 * expansion);
      final point = Offset(math.cos(angle), math.sin(angle)) * reach;
      if (i == 0) {
        core.moveTo(point.dx, point.dy);
      } else {
        core.lineTo(point.dx, point.dy);
      }
    }
    core.close();
    canvas
      ..drawPath(core, Paint()..color = orange.withValues(alpha: coreOpacity))
      ..save()
      ..scale(0.68)
      ..drawPath(core, Paint()..color = const Color(0xFFFFF5D6).withValues(alpha: coreOpacity))
      ..restore()
      ..drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..color = warm.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 * opacity,
      );
    // Spokes end on actual direct removals; floating drops receive no blast mark.
    for (final offset in clearedOffsets) {
      final direction = offset / offset.distance;
      canvas
        ..drawLine(
          direction * 24,
          offset - direction * 10,
          Paint()
            ..color = orange.withValues(alpha: opacity)
            ..strokeWidth = 11 * opacity
            ..strokeCap = StrokeCap.round,
        )
        ..drawCircle(
          offset,
          27 + 3 * progress,
          Paint()
            ..color = warm.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 * opacity,
        );
    }
  }

  void _renderRainbow(Canvas canvas) {
    // A matched rainbow includes its landing cell in the captured removals.
    final shrink = clearedOffsets.contains(Offset.zero)
        ? 1 - ((_elapsed - rainbowConversionTime) / BubbleComponent.popDuration).clamp(0.0, 1.0)
        : 1.0;
    if (shrink == 0) return;
    canvas
      ..save()
      ..scale(shrink);
    final color = resolvedColor.displayColor;
    final opacity = ((duration - _elapsed) / 0.22).clamp(0.0, 1.0);
    final absorption = (_elapsed / 0.2).clamp(0.0, 1.0);
    final conversion = ((_elapsed - 0.2) / (rainbowConversionTime - 0.2)).clamp(0.0, 1.0);
    final contact = contactOffset;
    if (contact != null && _elapsed < rainbowConversionTime) {
      final trailOpacity = (1 - conversion) * opacity;
      final control = contact * 0.5 + Offset(-contact.dy, contact.dx) * 0.24;
      final end = contact * math.pow(1 - absorption, 2).toDouble() + control * (2 * (1 - absorption) * absorption);
      final ribbon = Path()
        ..moveTo(contact.dx, contact.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas
        ..drawCircle(
          contact,
          24,
          Paint()
            ..color = const Color(0xFFFFFFFF).withValues(alpha: trailOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        )
        ..drawPath(
          ribbon,
          Paint()
            ..color = const Color(0xFFFFFFFF).withValues(alpha: trailOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..strokeCap = StrokeCap.round,
        )
        ..drawPath(
          ribbon,
          Paint()
            ..color = color.withValues(alpha: trailOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round,
        );
    }
    canvas.saveLayer(
      const Rect.fromLTWH(-32, -32, 64, 64),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    // Opaque colour bands cover the final sprite until the absorption completes.
    // A wipe reveals both its body and engraved symbol, including ceiling fallback.
    paintBubble(canvas, Offset.zero, 30, resolvedColor, sprite: resolvedSprite);
    canvas
      ..save()
      ..clipPath(Path()..addOval(const Rect.fromLTWH(-30, -30, 60, 60)))
      ..clipRect(Rect.fromLTRB(-30, -30 + 60 * conversion, 30, 30));
    final sweep = 2 * math.pi / BubbleColor.values.length;
    for (final band in BubbleColor.values) {
      canvas.drawArc(
        const Rect.fromLTWH(-32, -32, 64, 64),
        -math.pi / 2 + band.index * sweep + absorption * 0.5,
        sweep,
        true,
        Paint()..color = band.displayColor,
      );
    }
    canvas
      ..restore()
      ..restore()
      ..restore();
  }
}
