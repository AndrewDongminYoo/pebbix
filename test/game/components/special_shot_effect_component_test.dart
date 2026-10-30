import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubble_shooter/game/components/bubble_component.dart';
import 'package:bubble_shooter/game/components/special_shot_effect_component.dart';
import 'package:bubble_shooter/game/domain/domain.dart';

Future<ByteData> pixels(SpecialShotEffectComponent effect) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(120, 120);
  effect.render(canvas);
  final image = await recorder.endRecording().toImage(240, 240);
  final data = (await image.toByteData())!;
  image.dispose();
  return data;
}

int alpha(ByteData data, int x, int y) => data.getUint8((y * 240 + x) * 4 + 3);

void main() {
  SpecialShotEffectComponent effect({
    ShotKind kind = ShotKind.bomb,
    BubbleColor color = BubbleColor.red,
    ui.Offset? contact,
    List<ui.Offset> cleared = const [],
    Sprite? sprite,
  }) => SpecialShotEffectComponent(
    kind: kind,
    resolvedColor: color,
    position: Vector2.zero(),
    contactOffset: contact,
    clearedOffsets: cleared,
    resolvedSprite: sprite,
  );

  test('bomb begins with a solid impact core instead of a faint outline', () async {
    final data = await pixels(effect()..update(0.06));
    expect(alpha(data, 120, 120), greaterThan(230));
  });

  test('rainbow reveals the resolved body after colour absorption', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 60, 60),
      ui.Paint()..color = const ui.Color(0xFF123456),
    );
    final image = await recorder.endRecording().toImage(60, 60);
    final early = await pixels(effect(kind: ShotKind.rainbow, sprite: Sprite(image))..update(0.08));
    final settled = await pixels(effect(kind: ShotKind.rainbow, sprite: Sprite(image))..update(0.42));
    const at = (120 * 240 + 120) * 4;
    expect(early.getUint8(at), isNot(0x12));
    expect(settled.getUint8(at), 0x12);
    expect(settled.getUint8(at + 1), 0x34);
    expect(settled.getUint8(at + 2), 0x56);
    image.dispose();
  });

  test('matched rainbow overlay shrinks with the matched body after conversion', () async {
    final converting = await pixels(effect(kind: ShotKind.rainbow, cleared: [ui.Offset.zero])..update(0.32));
    final shrinking = await pixels(effect(kind: ShotKind.rainbow, cleared: [ui.Offset.zero])..update(0.435));
    final nonMatching = await pixels(effect(kind: ShotKind.rainbow)..update(0.435));
    expect(alpha(converting, 140, 120), greaterThan(0));
    expect(alpha(shrinking, 140, 120), 0);
    expect(alpha(shrinking, 120, 120), greaterThan(0));
    expect(alpha(nonMatching, 140, 120), greaterThan(0));
  });

  test('matched rainbow overlay disappears when the delayed pop finishes', () async {
    final matched = await pixels(effect(kind: ShotKind.rainbow, cleared: [ui.Offset.zero])..update(0.52));
    expect(matched.buffer.asUint8List().any((byte) => byte != 0), isFalse);
    final nonMatching = await pixels(effect(kind: ShotKind.rainbow)..update(0.52));
    expect(alpha(nonMatching, 120, 120), greaterThan(0));
  });

  test('bomb highlights only the directly cleared neighbour', () async {
    final bomb = effect(cleared: [const ui.Offset(60, 0)])..update(0.1);
    final data = await pixels(bomb);
    // Equidistant points outside the central blast, on neighbour outlines.
    expect(alpha(data, 207, 120), greaterThan(0));
    expect(alpha(data, 33, 120), 0);
  });

  test('rainbow carries the contacted colour toward the landing', () async {
    final rainbow = effect(
      kind: ShotKind.rainbow,
      color: BubbleColor.blue,
      contact: const ui.Offset(60, 0),
    )..update(0.2);
    final data = await pixels(rainbow);
    expect(alpha(data, 168, 120), greaterThan(0));
    expect(alpha(data, 72, 120), 0);
    final settled = await pixels(effect(kind: ShotKind.rainbow, color: BubbleColor.blue)..update(0.42));
    const at = (120 * 240 + 120) * 4;
    final expected = BubbleColor.blue.displayColor;
    expect(settled.getUint8(at + 2), greaterThan(settled.getUint8(at)));
    expect(expected.b, greaterThan(expected.r));
  });

  test('ceiling rainbow renders its base colour without a contact line', () async {
    final rainbow = effect(kind: ShotKind.rainbow, color: BubbleColor.green)..update(0.4);
    final data = await pixels(rainbow);
    const at = (120 * 240 + 120) * 4;
    expect(data.getUint8(at + 1), greaterThan(data.getUint8(at)));
    expect(alpha(data, 168, 120), 0);
  });

  test('ceiling conversion ring stays inside the bubble at the top boundary', () async {
    final rainbow = effect(kind: ShotKind.rainbow)..update(0.12);
    final data = await pixels(rainbow);
    for (var y = 0; y < 89; y++) {
      for (var x = 0; x < 240; x++) {
        expect(alpha(data, x, y), 0, reason: 'conversion extends above the ceiling at ($x, $y)');
      }
    }
  });

  test('contact connector has a bright outline distinct from coloured pop particles', () async {
    final rainbow = effect(kind: ShotKind.rainbow, contact: const ui.Offset(60, 0))..update(0.2);
    final data = await pixels(rainbow);
    expect(alpha(data, 168, 132), greaterThan(0));
    const at = (132 * 240 + 168) * 4;
    // rawRgba premultiplies white by alpha; blue still equals that alpha.
    expect(data.getUint8(at + 2), closeTo(data.getUint8(at + 3), 1));
  });

  test('rainbow preserves the resolved engraved sprite', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 60, 60),
      ui.Paint()..color = const ui.Color(0xFF123456),
    );
    final image = await recorder.endRecording().toImage(60, 60);
    final rainbow = effect(kind: ShotKind.rainbow, sprite: Sprite(image))..update(0.42);
    final data = await pixels(rainbow);
    const at = (120 * 240 + 120) * 4;
    expect(data.getUint8(at), 0x12);
    expect(data.getUint8(at + 1), 0x34);
    expect(data.getUint8(at + 2), 0x56);
    image.dispose();
  });

  test('normal shots and expired feedback draw nothing', () async {
    expect((await pixels(effect(kind: ShotKind.normal))).buffer.asUint8List().any((b) => b != 0), isFalse);
    final expired = effect()..update(1);
    expect((await pixels(expired)).buffer.asUint8List().any((b) => b != 0), isFalse);
  });

  testWidgets('paused engine preserves feedback pixels until resumed', (tester) async {
    final game = FlameGame();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await tester.pump();
    final bomb = effect(cleared: [const ui.Offset(60, 0)]);
    await game.add(bomb);
    await tester.pump();
    game.pauseEngine();
    final before = (await tester.runAsync(() => pixels(bomb)))!.buffer.asUint8List();
    expect(before.any((b) => b != 0), isTrue);
    await tester.pump(const Duration(seconds: 1));
    final after = (await tester.runAsync(() => pixels(bomb)))!.buffer.asUint8List();
    expect(after, orderedEquals(before));
    expect(bomb.isMounted, isTrue);
    game.resumeEngine();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(bomb.isMounted, isFalse);
  });
}
