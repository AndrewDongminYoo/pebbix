// 🎯 Dart imports:
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/painting.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/game/components/aim_assist_notice_component.dart';
import 'package:bubble_shooter/game/components/score_callout_component.dart';

/// The largest alpha [component] paints, rendered from its own top-left.
Future<int> peakAlpha(PositionComponent component) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(0, 80);
  component.render(canvas);
  final width = component.size.x.ceil() + 1;
  final height = component.size.y.ceil() + 160;
  final image = await recorder.endRecording().toImage(width, height);
  final data = (await image.toByteData())!;
  image.dispose();
  var peak = 0;
  for (var index = 3; index < data.lengthInBytes; index += 4) {
    if (data.getUint8(index) > peak) peak = data.getUint8(index);
  }
  return peak;
}

void main() {
  const style = TextStyle();

  group('ScoreCalloutComponent', () {
    ScoreCalloutComponent callout({String? bank = 'Bank ×2', String? rule, Vector2? at}) => ScoreCalloutComponent(
      points: 60,
      style: style,
      position: at ?? Vector2(240, 400),
      bankLabel: bank,
      ruleText: rule,
    );

    test('stacks the bank label over the points, and the rule under them', () {
      final plain = callout(bank: null);
      final banked = callout();
      final explained = callout(rule: 'Rule');
      expect(banked.size.y, greaterThan(plain.size.y));
      expect(explained.size.y, greaterThan(banked.size.y));
    });

    test('reads for longer only when it carries the rule', () {
      expect(callout().lifetime, ScoreCalloutComponent.duration);
      expect(callout(rule: 'Rule').lifetime, ScoreCalloutComponent.explainedDuration);
    });

    test('a top-row landing still leaves room to rise', () {
      final top = callout(at: Vector2(240, 0));
      expect(top.position.y - top.size.y / 2 - ScoreCalloutComponent.rise, greaterThanOrEqualTo(0));
    });

    test('text wider than the world centers on it', () {
      final wide = callout(rule: 'W' * 60, at: Vector2(10, 400));
      expect(wide.size.x, greaterThan(BubbleShooter.worldWidth));
      expect(wide.position.x, BubbleShooter.worldWidth / 2);
    });

    test('holds, fades, and then draws nothing', () async {
      final effect = callout();
      expect(await peakAlpha(effect), 255);
      effect.update(ScoreCalloutComponent.duration * 0.8);
      final fading = await peakAlpha(effect);
      expect(fading, inExclusiveRange(0, 255));
      effect.update(ScoreCalloutComponent.duration);
      expect(await peakAlpha(effect), 0);
    });
  });

  group('AimAssistNoticeComponent', () {
    AimAssistNoticeComponent notice() => AimAssistNoticeComponent(
      title: 'Aim help reduced',
      label: 'Aim: Path',
      style: style,
      position: Vector2(240, BubbleShooter.assistNoticeY),
    );

    test('fades in, holds, fades out, and then draws nothing', () async {
      final effect = notice()..update(0.1);
      final fadingIn = await peakAlpha(effect);
      expect(fadingIn, inExclusiveRange(0, 255));
      effect.update(0.5);
      expect(await peakAlpha(effect), 255);
      effect.update(0.8);
      expect(await peakAlpha(effect), inExclusiveRange(0, 255));
      effect.update(AimAssistNoticeComponent.duration);
      expect(await peakAlpha(effect), 0);
    });

    test('is wide enough for the longer of its two lines', () {
      final short = notice();
      final long = AimAssistNoticeComponent(
        title: 'Aim',
        label: 'A much longer tier label',
        style: style,
        position: Vector2.zero(),
      );
      expect(long.size.x, greaterThan(short.size.x));
    });
  });
}
