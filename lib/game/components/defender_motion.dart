// 🎯 Dart imports:
import 'dart:math' as math;

/// Presentation timing for the launcher crew, independent of game rules.
///
/// The projectile owns the deadline. No animation can postpone a shot or
/// mutate the queue, and a new shot can interrupt the empty-handed return.
class DefenderMotion {
  new();

  bool reducedMotion = false;
  double _clock = 0;
  double? _deliveryTime;
  double? _returnTime;
  double? _cheerTime;
  double _flightSeconds = 1;
  double _departure = 1;
  double _pickupFraction = 0;
  double _recoilTime = 1;
  double _hopHeight = 8;
  bool _ended = false;

  /// One is the next-shot dock; zero is the launch socket.
  double get bubblePosition {
    if (_deliveryTime == null || reducedMotion) return 1;
    if (_deliveryTime! / _flightSeconds < _pickupFraction) return 1;
    return loaderPosition;
  }

  double get loaderPosition {
    if (reducedMotion) return 1;
    final time = _deliveryTime;
    if (time != null) {
      final progress = time / _flightSeconds;
      if (progress < _pickupFraction) {
        return _departure + (1 - _departure) * _ease(progress / _pickupFraction);
      }
      return 1 - _ease((progress - _pickupFraction) / (0.85 - _pickupFraction));
    }
    return _returnTime == null ? 1 : _ease(_returnTime! / 0.32);
  }

  int get loaderPose {
    if (reducedMotion) return 0;
    final time = _deliveryTime;
    if (time != null && time >= _flightSeconds * 0.85) return 3;
    if (time == null && _returnTime == null) return 0;
    return 1 + (_clock * 12).floor() % 2;
  }

  void beginShot({required double flightSeconds}) {
    _departure = loaderPosition;
    _pickupFraction = _departure < 1 ? 0.2 : 0;
    _flightSeconds = math.max(flightSeconds, 0.000001);
    _deliveryTime = 0;
    _returnTime = null;
    _recoilTime = 0;
  }

  void update(double dt) {
    _clock += dt;
    _recoilTime += dt;
    if (_deliveryTime != null) _deliveryTime = _deliveryTime! + dt;
    if (_returnTime != null) {
      _returnTime = _returnTime! + dt;
      if (_returnTime! >= 0.32) _returnTime = null;
    }
    if (_cheerTime != null) {
      _cheerTime = _cheerTime! + dt;
      if (_cheerTime! >= 0.9) _cheerTime = null;
    }
  }

  void finishShot({required bool scored, required bool dropped}) {
    _deliveryTime = null;
    _returnTime = 0;
    if (scored) {
      _cheerTime = 0;
      _hopHeight = dropped ? 12 : 8;
    }
  }

  void endRun({required bool victory}) {
    reset();
    _ended = true;
    if (victory) {
      _cheerTime = 0;
      _hopHeight = 12;
    }
  }

  void reset() {
    _clock = 0;
    _deliveryTime = null;
    _returnTime = null;
    _cheerTime = null;
    _recoilTime = 1;
    _ended = false;
  }

  int mechanicPose(double aimAngle) {
    if (reducedMotion) return 0;
    if (_recoilTime < 0.18) return 3;
    if (aimAngle < -0.12) return 1;
    if (aimAngle > 0.12) return 2;
    return 0;
  }

  int cheerPose({bool right = false}) {
    if (reducedMotion) return 0;
    final time = _cheerTime;
    if (time != null) {
      final phase = time - (right ? 0.07 : 0);
      if (phase < 0) return 0;
      if (phase < 0.12) return 2;
      if (phase < 0.42) return 3;
      if (phase < 0.56) return 2;
      return 3;
    }
    if (_ended) return 0;
    return (_clock + (right ? 1.2 : 0)) % 3.6 > 3.4 ? 1 : 0;
  }

  double cheerLift({bool right = false}) {
    if (reducedMotion || _cheerTime == null) return 0;
    final phase = (_cheerTime! - (right ? 0.07 : 0) - 0.12) / 0.3;
    if (phase <= 0 || phase >= 1) return 0;
    return math.sin(phase * math.pi) * _hopHeight;
  }

  double idleLift({bool right = false}) {
    if (reducedMotion || _ended || _cheerTime != null) return 0;
    return (1 - math.cos((_clock / 2.8 + (right ? 0.35 : 0)) * math.pi * 2)) * 1.2;
  }

  static double _ease(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
