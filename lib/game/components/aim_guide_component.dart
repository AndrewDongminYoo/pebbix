// 🎯 Dart imports:
import 'dart:math';
import 'dart:ui';

// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';

/// Dotted preview of the visible trajectory. When [showLanding] is true, the
/// final settle segment is omitted and a ghost ring marks the landing cell.
/// Renders nothing while [path] is null.
class AimGuideComponent extends Component {
  List<Point<double>>? path;
  bool showLanding = true;

  static final _dotPaint = Paint()..color = const Color(0x99FFFFFF);
  static final _ghostPaint = Paint()
    ..color = const Color(0x66FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  static const _dotSpacing = 26.0;
  static const _dotRadius = 4.0;

  @override
  void render(Canvas canvas) {
    final points = path;
    if (points == null || points.length < 2) return;

    // Full assistance omits the final contact → landing settle segment.
    final segmentCount = showLanding ? points.length - 2 : points.length - 1;
    var leftover = 0.0;
    for (var i = 0; i < segmentCount; i++) {
      final from = points[i];
      final to = points[i + 1];
      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final length = sqrt(dx * dx + dy * dy);
      if (length == 0) continue;
      var d = leftover;
      while (d < length) {
        canvas.drawCircle(
          Offset(from.x + dx * d / length, from.y + dy * d / length),
          _dotRadius,
          _dotPaint,
        );
        d += _dotSpacing;
      }
      leftover = d - length;
    }

    if (showLanding) {
      final landing = points.last;
      canvas.drawCircle(
        Offset(landing.x, landing.y),
        BubbleShooter.bubbleRadius - 3,
        _ghostPaint,
      );
    }
  }
}
