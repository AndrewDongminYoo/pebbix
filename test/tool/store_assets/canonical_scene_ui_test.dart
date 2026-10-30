// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

import '../../../tool/store_assets/canonical_journey.dart';
import '../../../tool/store_assets/canonical_scene_ui.dart';
import '../../helpers/helpers.dart';

void main() {
  testWidgets('high score contract accepts the complete result row set', (tester) async {
    const stats = GameOverStats(
      score: 120,
      shotCount: 16,
      maxOccupiedRows: 16,
      ceilingDepth: 2,
      continued: false,
      reason: GameOverReason.defeat,
    );
    await tester.pumpApp(
      GameOverOverlay(
        isVictory: false,
        score: stats.score,
        bestScore: 480,
        onRestart: () {},
        onHome: () {},
        summary: (
          shotCount: stats.shotCount,
          ceilingDepth: stats.ceilingDepth,
          continued: stats.continued,
        ),
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(GameOverOverlay)));

    assertCanonicalHighScoreUi(
      tester: tester,
      scene: CanonicalScene.highScore,
      stats: stats,
      highScore: 480,
      l10n: l10n,
    );
  });

  testWidgets('high score contract names a missing result depth row', (tester) async {
    const stats = GameOverStats(
      score: 120,
      shotCount: 16,
      maxOccupiedRows: 16,
      ceilingDepth: 2,
      continued: false,
      reason: GameOverReason.defeat,
    );
    await tester.pumpApp(
      GameOverOverlay(
        isVictory: false,
        score: stats.score,
        bestScore: 480,
        onRestart: () {},
        onHome: () {},
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(GameOverOverlay)));

    expect(
      () => assertCanonicalHighScoreUi(
        tester: tester,
        scene: CanonicalScene.highScore,
        stats: stats,
        highScore: 480,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '05-high-score.png must render result depth row exactly once; found 0.',
        ),
      ),
    );
  });

  testWidgets('high score contract rejects a disabled replay action', (tester) async {
    const stats = GameOverStats(
      score: 120,
      shotCount: 16,
      maxOccupiedRows: 16,
      ceilingDepth: 2,
      continued: false,
      reason: GameOverReason.defeat,
    );
    await tester.pumpApp(
      GameOverOverlay(
        isVictory: false,
        score: stats.score,
        bestScore: 480,
        onRestart: null,
        onHome: () {},
        summary: (
          shotCount: stats.shotCount,
          ceilingDepth: stats.ceilingDepth,
          continued: stats.continued,
        ),
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(GameOverOverlay)));

    expect(
      () => assertCanonicalHighScoreUi(
        tester: tester,
        scene: CanonicalScene.highScore,
        stats: stats,
        highScore: 480,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '05-high-score.png must render an enabled replay action.',
        ),
      ),
    );
  });

  testWidgets('gameplay contract requires the HUD and pause action', (tester) async {
    final score = ValueNotifier<int>(120);
    final pressure = ValueNotifier<PressureState>(
      (
        aimAssist: AimAssistLevel.full,
        ceilingOffset: 0,
        colorCount: 4,
        shotsUntilDescent: 6,
      ),
    );
    addTearDown(score.dispose);
    addTearDown(pressure.dispose);
    await tester.pumpApp(
      Stack(
        children: [
          ScoreHud(score: score, pressure: pressure),
          IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
          const Align(alignment: Alignment(0, 0.45), child: TutorialHint()),
        ],
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ScoreHud)));

    assertCanonicalGameplayUi(
      tester: tester,
      scene: CanonicalScene.aim,
      score: score.value,
      pressure: pressure.value,
      l10n: l10n,
    );
  });

  testWidgets('gameplay contract rejects a partially clipped pause action', (tester) async {
    final score = ValueNotifier<int>(120);
    final pressure = ValueNotifier<PressureState>(
      (
        aimAssist: AimAssistLevel.full,
        ceilingOffset: 0,
        colorCount: 4,
        shotsUntilDescent: 6,
      ),
    );
    addTearDown(score.dispose);
    addTearDown(pressure.dispose);
    await tester.pumpApp(
      Stack(
        children: [
          ScoreHud(score: score, pressure: pressure),
          Transform.translate(
            offset: Offset(tester.view.physicalSize.width / tester.view.devicePixelRatio - 40, 0),
            child: IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
          ),
          const Align(alignment: Alignment(0, 0.45), child: TutorialHint()),
        ],
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ScoreHud)));

    expect(
      () => assertCanonicalGameplayUi(
        tester: tester,
        scene: CanonicalScene.aim,
        score: score.value,
        pressure: pressure.value,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '01-aim.png rendered pause action outside the capture bounds.',
        ),
      ),
    );
  });

  testWidgets('gameplay contract rejects a transparent HUD', (tester) async {
    final score = ValueNotifier<int>(120);
    final pressure = ValueNotifier<PressureState>(
      (
        aimAssist: AimAssistLevel.full,
        ceilingOffset: 0,
        colorCount: 4,
        shotsUntilDescent: 6,
      ),
    );
    addTearDown(score.dispose);
    addTearDown(pressure.dispose);
    await tester.pumpApp(
      Stack(
        children: [
          Opacity(
            opacity: 0,
            child: ScoreHud(score: score, pressure: pressure),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
          const Align(alignment: Alignment(0, 0.45), child: TutorialHint()),
        ],
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ScoreHud)));

    expect(
      () => assertCanonicalGameplayUi(
        tester: tester,
        scene: CanonicalScene.aim,
        score: score.value,
        pressure: pressure.value,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '01-aim.png rendered score HUD under a zero-opacity ancestor.',
        ),
      ),
    );
  });

  testWidgets('gameplay contract rejects a conflicting aim-assistance label', (tester) async {
    final score = ValueNotifier<int>(120);
    final pressure = ValueNotifier<PressureState>(
      (
        aimAssist: AimAssistLevel.full,
        ceilingOffset: 0,
        colorCount: 4,
        shotsUntilDescent: 6,
      ),
    );
    addTearDown(score.dispose);
    addTearDown(pressure.dispose);
    await tester.pumpApp(
      Stack(
        children: [
          ScoreHud(score: score, pressure: pressure),
          IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
          const Align(alignment: Alignment(0, 0.45), child: TutorialHint()),
          Builder(builder: (context) => Text(context.l10n.aimAssistOff)),
        ],
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ScoreHud)));

    expect(
      () => assertCanonicalGameplayUi(
        tester: tester,
        scene: CanonicalScene.aim,
        score: score.value,
        pressure: pressure.value,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '01-aim.png must omit conflicting aim-assistance label; found 1.',
        ),
      ),
    );
  });

  testWidgets('gameplay contract rejects a warning outside an urgent state', (tester) async {
    final score = ValueNotifier<int>(120);
    final pressure = ValueNotifier<PressureState>(
      (
        aimAssist: AimAssistLevel.full,
        ceilingOffset: 0,
        colorCount: 4,
        shotsUntilDescent: 6,
      ),
    );
    addTearDown(score.dispose);
    addTearDown(pressure.dispose);
    await tester.pumpApp(
      Stack(
        children: [
          ScoreHud(score: score, pressure: pressure),
          IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
          const Align(alignment: Alignment(0, 0.45), child: TutorialHint()),
          const Icon(Icons.warning_amber_rounded),
        ],
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ScoreHud)));

    expect(
      () => assertCanonicalGameplayUi(
        tester: tester,
        scene: CanonicalScene.aim,
        score: score.value,
        pressure: pressure.value,
        l10n: l10n,
      ),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          '01-aim.png must omit ceiling warning icon; found 1.',
        ),
      ),
    );
  });
}
