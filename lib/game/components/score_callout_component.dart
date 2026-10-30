// 🎯 Dart imports:
import 'dart:math' as math;

// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flame/text.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';

/// The points one shot added, drawn where it landed
/// (`docs/specs/2026-10-01-bank-shot-feedback.md`).
///
/// Board-local, so it rides the ceiling slide; its clock is Flame's, so
/// pausing the game holds it. It only reads what the shot already resolved.
class ScoreCalloutComponent extends PositionComponent {
  new({
    required this.points,
    required TextStyle style,
    required super.position,
    this.bankLabel,
    this.ruleText,
  }) : super(anchor: Anchor.center, priority: 30) {
    const shadows = [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1))];
    _lines = [
      if (bankLabel case final label?)
        (
          label,
          TextPaint(
            style: style.copyWith(
              color: const Color(0xFFFFD166),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              shadows: shadows,
            ),
          ),
        ),
      (
        '+$points',
        TextPaint(
          style: style.copyWith(
            color: const Color(0xFFFFFFFF),
            fontSize: 32,
            fontWeight: FontWeight.w800,
            shadows: shadows,
          ),
        ),
      ),
      if (ruleText case final text?)
        (
          text,
          TextPaint(
            style: style.copyWith(
              color: const Color(0xFFFFFFFF),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              shadows: shadows,
            ),
          ),
        ),
    ];
    final metrics = [for (final (text, paint) in _lines) paint.getLineMetrics(text)];
    size = Vector2(
      metrics.map((line) => line.width).reduce(math.max) + _padding.dx * 2,
      metrics.map((line) => line.height).reduce((a, b) => a + b) + _padding.dy * 2,
    );
    // Kept inside the world: a wall landing would otherwise cut the text
    // in half, and a top-row landing would rise off the screen. Text wider
    // than the world centers instead.
    final halfWidth = math.min(size.x / 2 + _margin, BubbleShooter.worldWidth / 2);
    position
      ..x = position.x.clamp(halfWidth, BubbleShooter.worldWidth - halfWidth)
      ..y = math.max(position.y, size.y / 2 + rise + _margin);
  }

  final int points;

  /// `Bank ×N`, present only when the shot bounced off a wall.
  final String? bankLabel;

  /// The one-line rule, present only on a run's first scoring bank shot.
  final String? ruleText;

  late final List<(String, TextPaint)> _lines;

  static const duration = 0.9;

  /// Longer only when there is a sentence to read.
  static const explainedDuration = 1.5;
  static const rise = 36.0;
  static const _margin = 4.0;
  static const _padding = Offset(12, 6);

  double get lifetime => ruleText == null ? duration : explainedDuration;
  double _elapsed = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= lifetime) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = _elapsed / lifetime;
    if (progress >= 1) return;
    final opacity = progress < 0.6 ? 1.0 : 1 - (progress - 0.6) / 0.4;
    final lift = rise * (1 - math.pow(1 - progress, 2));
    canvas
      ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity))
      ..translate(0, -lift)
      // A backdrop, because the text lands over bubbles that share its
      // colours, the bank label's amber included.
      ..drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size.toSize(), const Radius.circular(14)),
        Paint()..color = const Color(0xB3101828),
      );
    var top = _padding.dy;
    for (final (text, paint) in _lines) {
      paint.render(canvas, text, Vector2(size.x / 2, top), anchor: Anchor.topCenter);
      top += paint.getLineMetrics(text).height;
    }
    canvas.restore();
  }
}
