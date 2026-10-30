// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';

import '../../helpers/helpers.dart';

void main() {
  group('ScoreHud', () {
    late ValueNotifier<int> score;
    late ValueNotifier<PressureState> pressure;

    setUp(() {
      score = ValueNotifier(0);
      pressure = ValueNotifier(
        (
          aimAssist: AimAssistLevel.full,
          ceilingOffset: 0,
          colorCount: 4,
          shotsUntilDescent: 6,
        ),
      );
    });

    tearDown(() {
      score.dispose();
      pressure.dispose();
    });

    Future<void> pumpHud(WidgetTester tester) => tester.pumpApp(ScoreHud(score: score, pressure: pressure));

    testWidgets('renders and follows score changes', (tester) async {
      await pumpHud(tester);

      expect(find.text('Score: 0'), findsOneWidget);

      score.value = 70;
      await tester.pump();

      expect(find.text('Score: 70'), findsOneWidget);
    });

    testWidgets('uses a high contrast status surface', (tester) async {
      await pumpHud(tester);

      final surface = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(ScoreHud),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        surface.decoration,
        isA<BoxDecoration>().having(
          (decoration) => decoration.color,
          'color',
          Colors.black87,
        ),
      );
    });

    testWidgets('shows live pressure and aim assistance states', (
      tester,
    ) async {
      score.value = 120;
      await pumpHud(tester);

      expect(find.text('Score: 120'), findsOneWidget);
      expect(find.text('Ceiling in 6'), findsOneWidget);
      expect(find.text('Depth: 0'), findsOneWidget);
      expect(find.text('Aim: Exact'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      pressure.value = (
        aimAssist: AimAssistLevel.trajectory,
        ceilingOffset: 1,
        colorCount: 4,
        shotsUntilDescent: 3,
      );
      await tester.pump();

      expect(find.text('Depth: 1'), findsOneWidget);
      expect(find.text('Aim: Path'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      pressure.value = (
        aimAssist: AimAssistLevel.direction,
        ceilingOffset: 3,
        colorCount: 5,
        shotsUntilDescent: 2,
      );
      await tester.pump();

      expect(find.text('Ceiling in 2'), findsOneWidget);
      expect(find.text('Depth: 3'), findsOneWidget);
      expect(find.text('Aim: Direction'), findsOneWidget);
      // Two shots out is not urgent: the cadence floors at three shots, so
      // a two-shot threshold would light the warning on two of every three.
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      pressure.value = (
        aimAssist: AimAssistLevel.hidden,
        ceilingOffset: 5,
        colorCount: 6,
        shotsUntilDescent: 1,
      );
      await tester.pump();

      expect(find.text('Ceiling in 1'), findsOneWidget);
      expect(find.text('Depth: 5'), findsOneWidget);
      expect(find.text('Aim: Off'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
