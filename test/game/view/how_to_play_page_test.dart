// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';

import '../../helpers/helpers.dart';

void main() {
  group('HowToPlayPage', () {
    testWidgets('exposes the bubble reference as a screen-reader heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(HowToPlayPage(images: Images(prefix: '')));
      await tester.scrollUntilVisible(find.text('Bubbles'), 100);

      expect(tester.getSemantics(find.text('Bubbles')), matchesSemantics(label: 'Bubbles', isHeader: true));
      semantics.dispose();
    });

    testWidgets('explains every rule the game already enforces', (tester) async {
      const ceiling =
          'The ceiling drops a row every few shots, sooner as the run goes on. '
          'The run ends when bubbles reach the line at the bottom.';
      await tester.pumpApp(HowToPlayPage(images: Images(prefix: '')));

      expect(find.text('How to play'), findsOneWidget);
      for (final rule in [
        'Drag to aim and release to shoot. Shots bounce off the side walls.',
        'Three or more of one color pop, for 10 points each.',
        'Bubbles cut off from the top fall, for 20 points each.',
        "Each wall bounce multiplies the shot's points: one bounce ×2, two ×3.",
        ceiling,
        'The aim guide shortens as the ceiling drops, until you aim on your own.',
        'Bubbles',
        'Six colors. A run starts with four, and the other two join as the ceiling drops.',
        'Bomb: clears the bubbles around where it lands.',
        'Rainbow: turns the color of the first bubble it touches.',
      ]) {
        await tester.scrollUntilVisible(find.text(rule), 100);
        expect(find.text(rule), findsOneWidget);
      }
    });

    testWidgets('shows every color and both special bubbles in the legend', (tester) async {
      await tester.pumpApp(HowToPlayPage(images: Images(prefix: '')));
      await tester.scrollUntilVisible(find.text('Rainbow: turns the color of the first bubble it touches.'), 100);

      final shots = tester.widgetList<LegendBubble>(find.byType(LegendBubble)).map((bubble) => bubble.shot);
      expect(
        shots.where((shot) => shot.kind == ShotKind.normal).map((shot) => shot.color),
        unorderedEquals(BubbleColor.values),
      );
      expect(shots.map((shot) => shot.kind), containsAll([ShotKind.bomb, ShotKind.rainbow]));
    });

    testWidgets("draws the board's sprite where one is cached and the fallback elsewhere", (tester) async {
      final image = await tester.runAsync(createTestImage);
      final images = Images(prefix: '')..add(BubbleColor.red.spriteAsset.path, image!);

      await tester.pumpApp(HowToPlayPage(images: images));
      await tester.scrollUntilVisible(find.text('Bomb: clears the bubbles around where it lands.'), 100);

      final bubbles = tester.widgetList<LegendBubble>(find.byType(LegendBubble)).toList();
      final red = bubbles.where((bubble) => bubble.shot.color == BubbleColor.red);
      final others = bubbles.where((bubble) => bubble.shot.color != BubbleColor.red);
      // The bomb is drawn over a red base, so it shares the red sprite.
      expect(red.map((bubble) => bubble.sprite?.image), everyElement(same(image)));
      expect(others.map((bubble) => bubble.sprite), everyElement(isNull));

      // A rebuild hands each bubble a new painter; that has to be cheap and
      // must not throw.
      await tester.pumpApp(HowToPlayPage(images: images));
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('reads in large Korean text at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpApp(
          HowToPlayPage(images: Images(prefix: '')),
          locale: const Locale('ko'),
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('게임 방법'), findsOneWidget);
        const last = '무지개: 처음 닿은 구슬과 같은 색이 됩니다.';
        await tester.scrollUntilVisible(find.text(last), 100);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text(last)).overlaps(Offset.zero & size), isTrue);
      });
    }
  });
}
