// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

import 'canonical_journey.dart';

void assertCanonicalGameplayUi({
  required WidgetTester tester,
  required CanonicalScene scene,
  required int score,
  required PressureState pressure,
  required AppLocalizations l10n,
}) {
  final aimLabel = switch (pressure.aimAssist) {
    AimAssistLevel.full => l10n.aimAssistFull,
    AimAssistLevel.trajectory => l10n.aimAssistPath,
    AimAssistLevel.direction => l10n.aimAssistDirection,
    AimAssistLevel.hidden => l10n.aimAssistOff,
  };
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'score HUD',
    finder: find.byType(ScoreHud),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'live score row',
    finder: find.text(l10n.scoreLabel(score)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'ceiling countdown row',
    finder: find.text(l10n.ceilingCountdown(pressure.shotsUntilDescent)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'live depth row',
    finder: find.text(l10n.ceilingDepth(pressure.ceilingOffset)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'aim-assistance row',
    finder: find.text(aimLabel),
  );
  final conflictingAimLabels = <String>{
    l10n.aimAssistFull,
    l10n.aimAssistPath,
    l10n.aimAssistDirection,
    l10n.aimAssistOff,
  }..remove(aimLabel);
  for (final conflictingAimLabel in conflictingAimLabels) {
    _expectAbsent(
      scene: scene,
      element: 'conflicting aim-assistance label',
      finder: find.text(conflictingAimLabel),
    );
  }
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'pause action',
    finder: find.widgetWithIcon(IconButton, Icons.pause),
  );
  if (scene == CanonicalScene.aim) {
    _expectRenderedOnce(
      tester,
      scene: scene,
      element: 'first-shot tutorial',
      finder: find.byType(TutorialHint),
    );
    _expectRenderedOnce(
      tester,
      scene: scene,
      element: 'localized first-shot instruction',
      finder: find.text(l10n.tutorialHint),
    );
  } else {
    _expectAbsent(
      scene: scene,
      element: 'first-shot tutorial',
      finder: find.byType(TutorialHint),
    );
  }
  if (pressure.shotsUntilDescent <= 1) {
    _expectRenderedOnce(
      tester,
      scene: scene,
      element: 'ceiling warning icon',
      finder: find.byIcon(Icons.warning_amber_rounded),
    );
  } else {
    _expectAbsent(
      scene: scene,
      element: 'ceiling warning icon',
      finder: find.byIcon(Icons.warning_amber_rounded),
    );
  }
}

void assertCanonicalHighScoreUi({
  required WidgetTester tester,
  required CanonicalScene scene,
  required GameOverStats stats,
  required int highScore,
  required AppLocalizations l10n,
}) {
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'game-over overlay',
    finder: find.byType(GameOverOverlay),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'result title',
    finder: find.text(l10n.defeatTitle),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'result score row',
    finder: find.text(l10n.scoreLabel(stats.score)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'best-score row',
    finder: find.text(l10n.bestScoreLabel(highScore)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'result depth row',
    finder: find.text(l10n.ceilingDepth(stats.ceilingDepth)),
  );
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'shot-efficiency row',
    finder: find.text(l10n.runShotsLabel(stats.shotCount, stats.score / stats.shotCount)),
  );
  final replayAction = find.widgetWithText(ElevatedButton, l10n.playAgain);
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'replay action',
    finder: replayAction,
  );
  if (tester.widget<ElevatedButton>(replayAction).onPressed == null) {
    throw TestFailure('${scene.fileName} must render an enabled replay action.');
  }
  _expectRenderedOnce(
    tester,
    scene: scene,
    element: 'Home action',
    finder: find.text(l10n.homeButton),
  );
  _expectAbsent(
    scene: scene,
    element: 'Continue result row',
    finder: find.text(l10n.runContinuedLabel),
  );
  _expectAbsent(
    scene: scene,
    element: 'rewarded Continue action',
    finder: find.text(l10n.continueWithAd),
  );
  _expectAbsent(
    scene: scene,
    element: 'Skip action',
    finder: find.text(l10n.skipContinue),
  );
}

void _expectRenderedOnce(
  WidgetTester tester, {
  required CanonicalScene scene,
  required String element,
  required Finder finder,
}) {
  final matches = finder.evaluate().toList();
  if (matches.length != 1) {
    throw TestFailure('${scene.fileName} must render $element exactly once; found ${matches.length}.');
  }
  if (_hasZeroOpacityAncestor(matches.single)) {
    throw TestFailure('${scene.fileName} rendered $element under a zero-opacity ancestor.');
  }
  final renderObject = matches.single.renderObject;
  final elementBounds = tester.getRect(finder);
  if (renderObject is! RenderBox || !renderObject.hasSize || renderObject.size.isEmpty || elementBounds.isEmpty) {
    throw TestFailure('${scene.fileName} rendered $element without visible bounds.');
  }
  final captureBounds = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final isWithinCapture =
      elementBounds.left >= captureBounds.left &&
      elementBounds.top >= captureBounds.top &&
      elementBounds.right <= captureBounds.right &&
      elementBounds.bottom <= captureBounds.bottom;
  if (!isWithinCapture) {
    throw TestFailure('${scene.fileName} rendered $element outside the capture bounds.');
  }
}

bool _hasZeroOpacityAncestor(Element element) {
  var hasZeroOpacity = false;
  element.visitAncestorElements((ancestor) {
    switch (ancestor.widget) {
      case Opacity(:final opacity) when opacity == 0:
      case AnimatedOpacity(:final opacity) when opacity == 0:
        hasZeroOpacity = true;
        return false;
      case FadeTransition(:final opacity) when opacity.value == 0:
        hasZeroOpacity = true;
        return false;
    }
    return true;
  });
  return hasZeroOpacity;
}

void _expectAbsent({
  required CanonicalScene scene,
  required String element,
  required Finder finder,
}) {
  final count = finder.evaluate().length;
  if (count != 0) {
    throw TestFailure('${scene.fileName} must omit $element; found $count.');
  }
}
