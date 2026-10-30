// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/defender_motion.dart';

void main() {
  test('carries the next bubble to the socket within the projectile flight', () {
    final motion = DefenderMotion()..beginShot(flightSeconds: 0.5);
    expect(motion.bubblePosition, 1);

    motion.update(0.2);
    expect(motion.bubblePosition, inExclusiveRange(0, 1));
    expect(motion.loaderPosition, motion.bubblePosition);

    motion.update(0.3);
    expect(motion.bubblePosition, 0);
    expect(motion.loaderPose, 3);
  });

  test('returns empty handed while the new preview stays at the dock', () {
    final motion = DefenderMotion()
      ..beginShot(flightSeconds: 0.5)
      ..update(0.5)
      ..finishShot(scored: false, dropped: false);
    expect(motion.loaderPosition, 0);
    expect(motion.bubblePosition, 1);
    motion.update(0.16);
    expect(motion.loaderPosition, inExclusiveRange(0, 1));
    expect(motion.loaderPose, anyOf(1, 2));
    motion.update(0.3);
    expect(motion.loaderPosition, 1);
    expect(motion.loaderPose, 0);
  });

  test('a fast next shot first fetches its bubble without teleporting', () {
    final motion = DefenderMotion()
      ..beginShot(flightSeconds: 0.2)
      ..update(0.2)
      ..finishShot(scored: false, dropped: false)
      ..update(0.05);
    final before = motion.loaderPosition;
    motion.beginShot(flightSeconds: 0.4);
    expect(motion.loaderPosition, before);
    expect(motion.bubblePosition, 1);
    motion.update(0.04);
    expect(motion.loaderPosition, inExclusiveRange(before, 1));
    expect(motion.bubblePosition, 1);
    motion.update(0.36);
    expect(motion.loaderPosition, 0);
    expect(motion.bubblePosition, 0);
  });

  test('a very short flight still finishes the delivery', () {
    final motion = DefenderMotion()
      ..beginShot(flightSeconds: 0.01)
      ..update(0.01);
    expect(motion.bubblePosition, 0);
    motion
      ..beginShot(flightSeconds: 0)
      ..update(0.01);
    expect(motion.bubblePosition, 0);
  });

  test('the mechanic follows aim and briefly recoils only after a shot', () {
    final motion = DefenderMotion();
    expect(motion.mechanicPose(-0.8), 1);
    expect(motion.mechanicPose(0), 0);
    expect(motion.mechanicPose(0.8), 2);
    motion.beginShot(flightSeconds: 0.5);
    expect(motion.mechanicPose(0.8), 3);
    motion.update(0.2);
    expect(motion.mechanicPose(0.8), 2);
  });

  test('a score triggers anticipation, a staggered hop, and a landing', () {
    final motion = DefenderMotion()..finishShot(scored: true, dropped: false);
    expect(motion.cheerPose(), 2);
    expect(motion.cheerPose(right: true), 0);
    motion.update(0.25);
    expect(motion.cheerPose(), 3);
    expect(motion.cheerLift(), greaterThan(0));
    expect(motion.cheerLift(right: true), isNot(motion.cheerLift()));
    motion.update(0.22);
    expect(motion.cheerPose(), 2);
    expect(motion.cheerLift(), 0);
    motion.update(0.8);
    expect(motion.cheerPose(), 0);
    expect(motion.cheerLift(), 0);
  });

  test('cluster drops celebrate more strongly but misses do not celebrate', () {
    final score = DefenderMotion()
      ..finishShot(scored: true, dropped: false)
      ..update(0.25);
    final drop = DefenderMotion()
      ..finishShot(scored: true, dropped: true)
      ..update(0.25);
    final miss = DefenderMotion()
      ..finishShot(scored: false, dropped: false)
      ..update(0.25);
    expect(drop.cheerLift(), greaterThan(score.cheerLift()));
    expect(miss.cheerLift(), 0);
    expect(miss.cheerPose(), 0);
  });

  test('idle breathing and blinks use different phases for the cheerers', () {
    final motion = DefenderMotion()..update(3.45);
    expect(motion.cheerPose(), 1);
    expect(motion.cheerPose(right: true), 0);
    expect(motion.idleLift(), greaterThan(0));
    expect(motion.idleLift(), isNot(motion.idleLift(right: true)));
  });

  test('reduced motion keeps the crew and preview still across events', () {
    final motion = DefenderMotion()
      ..reducedMotion = true
      ..beginShot(flightSeconds: 0.5)
      ..update(0.25);
    expect(motion.loaderPosition, 1);
    expect(motion.bubblePosition, 1);
    expect(motion.loaderPose, 0);
    expect(motion.mechanicPose(1), 0);
    motion
      ..finishShot(scored: true, dropped: true)
      ..update(0.25);
    expect(motion.cheerPose(), 0);
    expect(motion.cheerLift(), 0);
    expect(motion.idleLift(), 0);
    motion.reset();
    expect(motion.reducedMotion, isTrue);
  });

  test('defeat clears active motion and restart restores a clean idle crew', () {
    final motion = DefenderMotion()
      ..beginShot(flightSeconds: 0.5)
      ..update(0.2)
      ..endRun(victory: false)
      ..update(0.25);
    expect(motion.loaderPosition, 1);
    expect(motion.cheerPose(), 0);
    expect(motion.idleLift(), 0);
    motion
      ..endRun(victory: true)
      ..update(0.25);
    expect(motion.cheerLift(), greaterThan(0));
    motion.reset();
    expect(motion.loaderPosition, 1);
    expect(motion.bubblePosition, 1);
    expect(motion.loaderPose, 0);
    expect(motion.cheerLift(), 0);
    motion.update(0.5);
    expect(motion.idleLift(), greaterThan(0));
  });
}
