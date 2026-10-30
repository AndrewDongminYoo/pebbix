// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flame/text.dart';

/// Names an aim-assistance tier the moment a descent lowers it
/// (`docs/specs/2026-10-01-bank-shot-feedback.md`).
///
/// It describes the run rather than a cell, so it sits in the world at a
/// fixed point; Flame's clock drives it, so pause holds it.
class AimAssistNoticeComponent extends PositionComponent {
  new({
    required this.title,
    required this.label,
    required TextStyle style,
    required super.position,
  }) : _title = TextPaint(
         style: style.copyWith(color: const Color(0xFFFFFFFF), fontSize: 24, fontWeight: FontWeight.w700),
       ),
       _label = TextPaint(
         style: style.copyWith(color: const Color(0xFFFFD166), fontSize: 22, fontWeight: FontWeight.w600),
       ),
       super(anchor: Anchor.center, priority: 30) {
    final titleLine = _title.getLineMetrics(title);
    final labelLine = _label.getLineMetrics(label);
    _titleHeight = titleLine.height;
    size = Vector2(
      (titleLine.width > labelLine.width ? titleLine.width : labelLine.width) + _padding.dx * 2,
      titleLine.height + labelLine.height + _padding.dy * 2,
    );
  }

  /// What changed, in the player's words.
  final String title;

  /// The new tier, as the HUD names it.
  final String label;

  final TextPaint _title;
  final TextPaint _label;
  late final double _titleHeight;

  static const duration = 1.5;
  static const _fade = 0.3;
  static const _padding = Offset(18, 10);

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
    final opacity = switch (_elapsed) {
      < _fade => _elapsed / _fade,
      > duration - _fade => (duration - _elapsed) / _fade,
      _ => 1.0,
    };
    canvas
      ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity))
      ..drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size.toSize(), Radius.circular(size.y / 2)),
        Paint()..color = const Color(0xD9101828),
      );
    _title.render(canvas, title, Vector2(size.x / 2, _padding.dy), anchor: Anchor.topCenter);
    _label.render(canvas, label, Vector2(size.x / 2, _padding.dy + _titleHeight), anchor: Anchor.topCenter);
    canvas.restore();
  }
}
