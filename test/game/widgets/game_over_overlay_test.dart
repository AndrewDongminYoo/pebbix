// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';

import '../../helpers/helpers.dart';

void main() {
  group('GameOverOverlay', () {
    testWidgets('shows victory title, score and restart button', (
      tester,
    ) async {
      var restarted = false;
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: true,
          score: 120,
          bestScore: 480,
          onRestart: () => restarted = true,
          onHome: () {},
        ),
      );

      expect(find.text('Board cleared!'), findsOneWidget);
      expect(find.text('Score: 120'), findsOneWidget);
      expect(find.text('Best: 480'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      expect(restarted, isTrue);
    });

    testWidgets('shows defeat title when the player lost', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 30,
          bestScore: 80,
          onRestart: () {},
          onHome: () {},
        ),
      );

      expect(find.text('Game Over'), findsOneWidget);
    });

    testWidgets('shows Continue and Skip while the offer is open', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var continued = false;
      var declined = false;
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 42,
          bestScore: 100,
          onRestart: () {},
          onHome: () {},
          showContinue: true,
          onContinue: () => continued = true,
          onDecline: () => declined = true,
        ),
      );
      expect(find.textContaining('Ceiling back one row'), findsOneWidget);
      expect(find.textContaining('Score kept'), findsOneWidget);
      expect(find.textContaining('Once per run'), findsOneWidget);
      // The separator dots are layout, not content.
      expect(tester.getSemantics(find.textContaining('Score kept')).label, 'Score kept');
      expect(find.text('Continue (watch ad)'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Play Again'), findsNothing);
      expect(find.textContaining('Depth:'), findsNothing);
      await tester.tap(find.text('Continue (watch ad)'));
      expect(continued, isTrue);
      await tester.tap(find.text('Skip'));
      expect(declined, isTrue);
      semantics.dispose();
    });

    testWidgets('shows Play Again when no offer is open', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 42,
          bestScore: 100,
          onRestart: () {},
          onHome: () {},
        ),
      );
      expect(find.text('Play Again'), findsOneWidget);
      expect(find.text('Continue (watch ad)'), findsNothing);
      expect(find.textContaining('Ceiling back one row'), findsNothing);
      expect(find.textContaining('Once per run'), findsNothing);
    });

    testWidgets('continue offer fits a 320x568 portrait viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var declined = false;
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 999999,
          bestScore: 999999,
          onRestart: () {},
          onHome: () {},
          showContinue: true,
          onContinue: () {},
          onDecline: () => declined = true,
        ),
      );
      // A RenderFlex overflow surfaces as a FlutterError during layout.
      expect(tester.takeException(), isNull);
      expect(find.text('Continue (watch ad)'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      expect(declined, isTrue);
    });

    testWidgets('keeps large Korean continue actions reachable in compact landscape', (tester) async {
      tester.view
        ..physicalSize = const Size(568, 320)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var homeTaps = 0;

      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 999999,
          bestScore: 999999,
          onRestart: () {},
          onHome: () => homeTaps += 1,
          showContinue: true,
          onContinue: () {},
          onDecline: () {},
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('게임 오버'), findsOneWidget);
      expect(find.text('점수: 999999'), findsOneWidget);
      expect(find.text('최고 점수: 999999'), findsOneWidget);
      expect(find.textContaining('천장 1칸 후퇴'), findsOneWidget);
      expect(find.textContaining('점수 유지'), findsOneWidget);
      expect(find.textContaining('한 판에 1회'), findsOneWidget);
      expect(find.text('이어하기 (광고 보기)'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);

      await tester.ensureVisible(find.text('홈'));
      await tester.pump();
      await tester.tap(find.text('홈'));
      expect(homeTaps, 1);
    });

    testWidgets('keeps the large Korean continue offer reachable in compact portrait', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var declines = 0;

      // The reward line wraps most at the narrowest width, and it sits above
      // every action, so it is what could push them out of reach.
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 999999,
          bestScore: 999999,
          onRestart: () {},
          onHome: () {},
          showContinue: true,
          onContinue: () {},
          onDecline: () => declines += 1,
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('천장 1칸 후퇴'), findsOneWidget);
      expect(find.textContaining('점수 유지'), findsOneWidget);
      expect(find.textContaining('한 판에 1회'), findsOneWidget);
      expect(find.text('이어하기 (광고 보기)'), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);
      await tester.ensureVisible(find.text('건너뛰기'));
      await tester.pump();
      await tester.tap(find.text('건너뛰기'));
      expect(declines, 1);
      await tester.ensureVisible(find.text('홈'));
      await tester.pump();
      expect(tester.getRect(find.text('홈')).overlaps(Offset.zero & const Size(320, 568)), isTrue);
    });

    testWidgets('keeps large Korean result actions reachable in compact landscape', (tester) async {
      tester.view
        ..physicalSize = const Size(568, 320)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 999999,
          bestScore: 999999,
          onRestart: () {},
          onHome: () {},
          // Spec 0002 §8: doubled Korean text and the longest numbers still
          // have to scroll rather than clip or drop actions. Which viewport
          // is the tighter one is not asserted here — portrait is the
          // narrower of the two, so it gets its own fixture below.
          summary: (shotCount: 999, ceilingDepth: 999, continued: true),
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('깊이: 999줄'), findsOneWidget);
      expect(find.text('이어하기 1회 사용'), findsOneWidget);
      expect(find.text('다시 하기'), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);
      await tester.ensureVisible(find.text('홈'));
      await tester.pump();
      expect(tester.getRect(find.text('홈')).overlaps(Offset.zero & const Size(568, 320)), isTrue);
    });

    testWidgets('keeps large Korean result actions reachable in compact portrait', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Spec 0002 §7 names both viewports, and this is the narrower one: 272
      // logical pixels of content width against landscape's 520, so doubled
      // Korean wraps onto more lines here than it does there.
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 999999,
          bestScore: 999999,
          onRestart: () {},
          onHome: () {},
          summary: (shotCount: 999, ceilingDepth: 999, continued: true),
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('깊이: 999줄'), findsOneWidget);
      expect(find.text('이어하기 1회 사용'), findsOneWidget);
      expect(find.text('다시 하기'), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);
      await tester.ensureVisible(find.text('홈'));
      await tester.pump();
      expect(tester.getRect(find.text('홈')).overlaps(Offset.zero & const Size(320, 568)), isTrue);
    });

    testWidgets('keeps the full host bounds when a continue offer becomes the result', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var showContinue = true;

      await tester.pumpApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            height: 568,
            child: Stack(
              children: [
                const SizedBox.expand(),
                StatefulBuilder(
                  builder: (context, setState) => GameOverOverlay(
                    isVictory: false,
                    score: 270,
                    bestScore: 270,
                    onRestart: () {},
                    onHome: () {},
                    showContinue: showContinue,
                    onContinue: () {},
                    onDecline: () => setState(() => showContinue = false),
                  ),
                ),
              ],
            ),
          ),
        ),
        locale: const Locale('ko'),
        textScaler: TextScaler.noScaling,
      );

      await tester.ensureVisible(find.text('건너뛰기'));
      await tester.pump();
      await tester.tap(find.text('건너뛰기'));
      await tester.pump();

      expect(find.text('다시 하기'), findsOneWidget);
      final dimmer = find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == Colors.black54);
      expect(tester.getRect(dimmer), Offset.zero & const Size(240, 568));
    });

    testWidgets('disables restart while an ad is showing', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 42,
          bestScore: 100,
          onRestart: null,
          onHome: () {},
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Play Again'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('offers Home in both the results and the offer state', (
      tester,
    ) async {
      var homeTaps = 0;
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 42,
          bestScore: 100,
          onRestart: () {},
          onHome: () => homeTaps += 1,
        ),
      );
      await tester.tap(find.text('Home'));
      expect(homeTaps, 1);

      // Spec §3: Home stays reachable while the continue offer is open,
      // and while an ad in flight has disabled restart.
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 42,
          bestScore: 100,
          onRestart: null,
          onHome: () => homeTaps += 1,
          showContinue: true,
          onContinue: () {},
          onDecline: () {},
        ),
      );
      await tester.tap(find.text('Home'));
      expect(homeTaps, 2);
    });
    testWidgets('reports the finished run: shots, score per shot, and the Continue it used', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 120,
          bestScore: 480,
          onRestart: () {},
          onHome: () {},
          summary: (shotCount: 16, ceilingDepth: 2, continued: true),
        ),
      );

      // The facts the run produced, which the panel used to drop at the UI
      // boundary.
      expect(find.text('Shots: 16 · 7.5 per shot'), findsOneWidget);
      expect(find.text('Depth: 2'), findsOneWidget);
      expect(find.text('Continued once'), findsOneWidget);
    });

    testWidgets('says nothing about Continue when the run did not use it', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 120,
          bestScore: 480,
          onRestart: () {},
          onHome: () {},
          summary: (shotCount: 16, ceilingDepth: 2, continued: false),
        ),
      );

      // A "not used" row carries no information; the line exists to make the
      // ad's value visible, so it appears only when the ad was watched.
      expect(find.text('Continued once'), findsNothing);
      expect(find.text('Shots: 16 · 7.5 per shot'), findsOneWidget);
    });

    testWidgets('omits the shots line when the run fired nothing', (tester) async {
      await tester.pumpApp(
        GameOverOverlay(
          isVictory: false,
          score: 0,
          bestScore: 480,
          onRestart: () {},
          onHome: () {},
          summary: (shotCount: 0, ceilingDepth: 0, continued: false),
        ),
      );

      // Score per shot divides by the shot count, and a run with no shots has
      // no efficiency to report either — so the whole line goes rather than
      // rendering an infinity.
      expect(find.textContaining('per shot'), findsNothing);
      // The panel still stands: only the line that needs a divisor is gone.
      expect(find.text('Score: 0'), findsOneWidget);
    });
  });
}
