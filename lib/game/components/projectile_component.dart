// 📦 Package imports:
import 'package:flame/components.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/game/domain/domain.dart';

/// Animates a fired bubble along the pre-solved path, then hands the
/// result back to the game for the single board mutation.
class ProjectileComponent extends BubbleComponent {
  new({required this.result, required super.color})
    : shot = (color: color, kind: ShotKind.normal),
      super(position: Vector2(result.path.first.x, result.path.first.y));

  new shot({required this.result, required this.shot})
    : super(
        color: shot.color,
        kind: shot.kind,
        position: Vector2(result.path.first.x, result.path.first.y),
      );

  final ShotResult result;
  final LauncherShot shot;

  static const _speed = 1500.0;

  /// The same path and speed used by [update], so loading cannot delay play.
  double get flightSeconds {
    var distance = 0.0;
    for (var i = 1; i < result.path.length; i++) {
      distance += result.path[i - 1].distanceTo(result.path[i]);
    }
    return distance / _speed;
  }

  int _index = 0;

  @override
  void update(double dt) {
    super.update(dt);
    var remaining = _speed * dt;
    while (remaining > 0 && _index < result.path.length - 1) {
      final next = result.path[_index + 1];
      final target = Vector2(next.x, next.y);
      final distance = position.distanceTo(target);
      if (distance <= remaining) {
        position = target;
        _index++;
        remaining -= distance;
      } else {
        position += (target - position)..scale(remaining / distance);
        remaining = 0;
      }
    }
    if (_index >= result.path.length - 1) {
      removeFromParent();
      game.onShotLanded(result);
    }
  }
}
