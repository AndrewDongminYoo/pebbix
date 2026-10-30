// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/widgets/pause_overlay.dart';

import '../../helpers/helpers.dart';

void main() {
  group('PauseOverlay', () {
    testWidgets('renders the pause actions', (tester) async {
      await tester.pumpApp(
        PauseOverlay(
          onResume: () {},
          onHowToPlay: () {},
          onSettings: () {},
          onRestart: () {},
        ),
      );

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('How to play'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
    });

    testWidgets('invokes each pause action once', (tester) async {
      var resumeCount = 0;
      var howToPlayCount = 0;
      var settingsCount = 0;
      var restartCount = 0;
      await tester.pumpApp(
        PauseOverlay(
          onResume: () => resumeCount += 1,
          onHowToPlay: () => howToPlayCount += 1,
          onSettings: () => settingsCount += 1,
          onRestart: () => restartCount += 1,
        ),
      );

      await tester.tap(find.text('Resume'));
      await tester.tap(find.text('How to play'));
      await tester.tap(find.text('Settings'));
      await tester.tap(find.text('Restart'));

      expect(resumeCount, 1);
      expect(howToPlayCount, 1);
      expect(settingsCount, 1);
      expect(restartCount, 1);
    });

    testWidgets('keeps large Korean actions reachable in compact landscape', (tester) async {
      tester.view
        ..physicalSize = const Size(568, 320)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var restartCount = 0;

      await tester.pumpApp(
        PauseOverlay(
          onResume: () {},
          onHowToPlay: () {},
          onSettings: () {},
          onRestart: () => restartCount += 1,
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('일시정지'), findsOneWidget);
      expect(find.text('계속하기'), findsOneWidget);
      expect(find.text('게임 방법'), findsOneWidget);
      expect(find.text('설정'), findsOneWidget);
      expect(find.text('다시 시작'), findsOneWidget);

      await tester.ensureVisible(find.text('다시 시작'));
      await tester.pump();
      await tester.tap(find.text('다시 시작'));
      expect(restartCount, 1);
    });

    testWidgets('scrolls instead of clipping when the host is shorter than the panel', (tester) async {
      // Four actions in doubled Korean exactly fill 568×320, so a host
      // shorter than that, with a system inset for instance, must scroll.
      tester.view
        ..physicalSize = const Size(568, 240)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var restartCount = 0;

      await tester.pumpApp(
        PauseOverlay(
          onResume: () {},
          onHowToPlay: () {},
          onSettings: () {},
          onRestart: () => restartCount += 1,
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('다시 시작')).top, greaterThan(240));
      await tester.ensureVisible(find.text('다시 시작'));
      await tester.pump();
      expect(tester.getRect(find.text('다시 시작')).bottom, lessThanOrEqualTo(240));
      await tester.tap(find.text('다시 시작'));
      expect(restartCount, 1);
    });
  });
}
