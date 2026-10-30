// 🎯 Dart imports:
import 'dart:math';
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// 📦 Package imports:
import 'package:flame/game.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/app.dart';
import 'package:bubble_shooter/bootstrap.dart';
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';
import 'package:bubble_shooter/title/title.dart';

import '../tool/store_assets/canonical_journey.dart';
import '../tool/store_assets/canonical_scene_ui.dart';
import '../tool/store_assets/store_assets.dart';

typedef _ShotSnapshot = ({List<Point<double>> path, int boardCount, int score, int addsLanding});

const _profileId = String.fromEnvironment('STORE_ASSET_PROFILE');
const _localeId = String.fromEnvironment('STORE_ASSET_LOCALE');
const _appBootTimeout = Duration(seconds: 15);
const _actionTimeout = Duration(seconds: 3);
const _frameStep = Duration(milliseconds: 16);

bool _routeWidgetReady(Finder finder) {
  final matches = finder.evaluate().toList();
  if (matches.length != 1) return false;
  final animation = ModalRoute.of(matches.single)?.animation;
  return animation == null || animation.status == AnimationStatus.completed;
}

Future<void> _waitForRouteWidget(
  WidgetTester tester, {
  required Finder finder,
  required String expected,
}) async {
  var elapsed = Duration.zero;
  while (elapsed < _appBootTimeout) {
    if (_routeWidgetReady(finder)) return;
    await tester.pump(_frameStep);
    elapsed += _frameStep;
  }
  if (_routeWidgetReady(finder)) return;
  throw TestFailure('Application startup timed out. Expected $expected within $_appBootTimeout.');
}

Future<void> _waitForGame(
  WidgetTester tester, {
  required BubbleShooter game,
  required GameSessionController session,
  required bool Function() predicate,
  required String checkpoint,
  required String expected,
  required Duration timeout,
}) async {
  var elapsed = Duration.zero;
  while (elapsed < timeout) {
    if (predicate()) return;
    await tester.pump(_frameStep);
    elapsed += _frameStep;
  }
  if (predicate()) return;
  throw TestFailure(
    'Canonical journey timed out at "$checkpoint". Expected $expected within $timeout. '
    'status=${game.status}, score=${game.score}, shotCount=${game.shotCount}, '
    'ceilingOffset=${game.ceilingOffset}, aimAssist=${game.pressure.aimAssist}, '
    'colorCount=${game.pressure.colorCount}, shotsUntilDescent=${game.pressure.shotsUntilDescent}, '
    'boardBottomRow=${game.board.bottomRow}, aimPathPointCount=${game.aimGuide.path?.length ?? 0}, '
    'sessionPhase=${session.state.phase}.',
  );
}

Locale _requestedLocale(StoreAssetLocale locale) => switch (locale) {
  StoreAssetLocale.enUs => const Locale('en'),
  StoreAssetLocale.korean => const Locale('ko'),
};

TargetPlatform _expectedTargetPlatform(StoreAssetProfile profile) => switch (profile.platform) {
  StoreAssetPlatform.ios => TargetPlatform.iOS,
  StoreAssetPlatform.android => TargetPlatform.android,
};

void _assertCaptureEnvironment({
  required WidgetTester tester,
  required StoreAssetProfile profile,
  required Locale requestedLocale,
  required BuildContext localizedContext,
}) {
  final view = tester.view;
  final physicalSize = view.physicalSize;
  final logicalSize = physicalSize / view.devicePixelRatio;
  expect(defaultTargetPlatform, _expectedTargetPlatform(profile));
  expect(physicalSize.height, greaterThan(physicalSize.width), reason: 'The capture device must be in portrait.');
  expect(physicalSize.width.round(), profile.physicalWidth);
  expect(physicalSize.height.round(), profile.physicalHeight);
  expect(view.devicePixelRatio, profile.devicePixelRatio);
  expect(logicalSize.width, closeTo(profile.logicalWidth, 0.001));
  expect(logicalSize.height, closeTo(profile.logicalHeight, 0.001));
  expect(Localizations.localeOf(localizedContext), requestedLocale);
  expect(AppLocalizations.of(localizedContext).localeName, requestedLocale.languageCode);
}

Offset _globalWorldPoint(WidgetTester tester, BubbleShooter game, Vector2 worldPoint) {
  final canvasPoint = game.camera.localToGlobal(worldPoint);
  final globalPoint = game.convertLocalToGlobalCoordinate(canvasPoint).toOffset();
  final gameRect = tester.getRect(find.byType(GameWidget<FlameGame>));
  expect(
    gameRect.contains(globalPoint),
    isTrue,
    reason: 'The canonical world point must stay inside the Flame surface.',
  );
  final roundTrip = game.camera.globalToLocal(
    game.convertGlobalToLocalCoordinate(Vector2(globalPoint.dx, globalPoint.dy)),
  );
  expect(roundTrip.x, closeTo(worldPoint.x, 0.001));
  expect(roundTrip.y, closeTo(worldPoint.y, 0.001));
  return globalPoint;
}

Future<TestGesture> _startCaptureGesture(
  IntegrationTestWidgetsFlutterBinding binding,
  Offset position,
) async {
  final gesture = TestGesture(
    dispatcher: (event) async {
      binding.shouldPropagateDevicePointerEvents = true;
      try {
        binding.handlePointerEventForSource(event);
      } finally {
        binding.shouldPropagateDevicePointerEvents = false;
      }
    },
  );
  await gesture.down(position);
  return gesture;
}

_ShotSnapshot _shotSnapshot(BubbleShooter game, {required int actionIndex}) {
  final path = game.aimGuide.path;
  if (path == null || path.length < 3) {
    throw TestFailure(
      'Canonical action ${actionIndex + 1} has no valid aim path before capture. '
      'status=${game.status}, hasAimedShot=${game.hasAimedShot}, shotCount=${game.shotCount}.',
    );
  }
  return (
    path: List<Point<double>>.of(path),
    boardCount: game.board.occupiedCells.length,
    score: game.score,
    addsLanding: game.currentShot.kind == ShotKind.bomb ? 0 : 1,
  );
}

CanonicalShotOutcome _shotOutcome(BubbleShooter game, _ShotSnapshot before) {
  final scoreGain = game.score - before.score;
  final multiplier = before.path.length - 2;
  if (scoreGain % (multiplier * 10) != 0) {
    throw TestFailure('The canonical shot score cannot identify popped and dropped bubbles.');
  }
  final removed = before.boardCount + before.addsLanding - game.board.occupiedCells.length;
  final weightedRemoved = scoreGain ~/ (multiplier * 10);
  final dropped = weightedRemoved - removed;
  return (
    bounces: before.path.length - 3,
    popped: removed - dropped,
    dropped: dropped,
    scoreGain: scoreGain,
  );
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  CanonicalScene scene, {
  required bool Function() predicate,
  required void Function() assertRenderedUi,
  BubbleShooter? freezeGame,
  bool requireAimedShot = true,
}) async {
  // The scene was validated by `_waitForGame`, which returns the instant its
  // predicate passes — before that mutation has been painted. This frame gives
  // it somewhere to land, because freezing the engine first captures the frame
  // before it. Spec §Readiness forbids an unconditional advance standing as
  // proof of readiness, so the predicate is re-asserted here: what gets
  // captured has to be the moment that was validated, not the one after it.
  await tester.pump(_frameStep);
  if (!predicate()) {
    throw TestFailure('${scene.fileName} left its canonical state while painting the capture frame.');
  }
  if (freezeGame != null) {
    freezeGame.pauseEngine();
    freezeGame.renderBox.markNeedsPaint();
  }
  try {
    await tester.pump();
    if (freezeGame != null && requireAimedShot && (!freezeGame.hasAimedShot || freezeGame.aimGuide.path == null)) {
      throw TestFailure('The aimed scene was cleared while pumping its capture frame.');
    }
    assertRenderedUi();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final bytes = await binding.takeScreenshot(scene.fileName);
      expect(bytes, isNotEmpty, reason: 'The host driver must receive ${scene.fileName}.');
      return;
    }
    final renderView = tester.binding.renderViews.single;
    expect(renderView.paintBounds.size, tester.view.physicalSize);
    final layer = renderView.debugLayer;
    if (layer is! OffsetLayer) throw TestFailure('The Flutter capture surface has no OffsetLayer.');
    final image = await layer.toImage(renderView.paintBounds);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) throw TestFailure('The Flutter surface could not encode ${scene.fileName}.');
    expect(bytes, isNotEmpty, reason: 'The host driver must receive ${scene.fileName}.');
    final reportData = binding.reportData ??= <String, dynamic>{};
    (reportData.putIfAbsent('screenshots', () => <dynamic>[])! as List<dynamic>).add(
      <String, dynamic>{'screenshotName': scene.fileName, 'bytes': bytes},
    );
  } finally {
    freezeGame?.resumeEngine();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the production canonical journey', (tester) async {
    final profile = StoreAssetProfile.parse(_profileId);
    final storeLocale = StoreAssetLocale.parse(_localeId);
    final requestedLocale = _requestedLocale(storeLocale);
    binding.platformDispatcher.localeTestValue = requestedLocale;
    binding.platformDispatcher.localesTestValue = [requestedLocale];
    addTearDown(() {
      binding.platformDispatcher.clearLocaleTestValue();
      binding.platformDispatcher.clearLocalesTestValue();
    });

    final settings = InMemorySettingsRepository(
      settings: const GameSettings(
        musicEnabled: false,
        sfxEnabled: false,
        hapticsEnabled: false,
      ),
    );
    final testFlutterErrorHandler = FlutterError.onError;
    try {
      await bootstrap(
        () => App(
          settings: settings,
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(interstitialReady: false),
          entitlements: FakeEntitlementRepository(),
          analytics: const AnalyticsSink(),
        ),
      );
    } finally {
      FlutterError.onError = testFlutterErrorHandler;
    }
    await _waitForRouteWidget(
      tester,
      finder: find.byType(TitlePage),
      expected: 'the completed production title route after preload',
    );

    final titleContext = tester.element(find.byType(TitlePage));
    _assertCaptureEnvironment(
      tester: tester,
      profile: profile,
      requestedLocale: requestedLocale,
      localizedContext: titleContext,
    );
    final l10n = AppLocalizations.of(titleContext);
    final theme = Theme.of(titleContext);
    final preload = titleContext.read<PreloadCubit>().state;
    final session = titleContext.read<GameSessionController>();
    final game = BubbleShooter(
      l10n: l10n,
      playSfx: (_) {},
      textStyle: theme.textTheme.bodySmall!.copyWith(color: Colors.white, fontSize: 4),
      images: preload.images,
      seed: canonicalJourneySeed,
    );
    void assertGameplayUi(CanonicalScene scene) => assertCanonicalGameplayUi(
      tester: tester,
      scene: scene,
      score: game.score,
      pressure: game.pressure,
      l10n: l10n,
    );
    Navigator.of(titleContext).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => GamePage(game: game)),
    );
    await _waitForRouteWidget(
      tester,
      finder: find.byType(GameWidget<FlameGame>),
      expected: 'the completed production game route with the injected Flame surface',
    );
    await _waitForGame(
      tester,
      game: game,
      session: session,
      predicate: () => game.isLoaded && game.status == GameStatus.aiming,
      checkpoint: CanonicalScene.aim.fileName,
      expected: 'the injected seeded game to finish loading',
      timeout: CanonicalScene.aim.timeout,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }

    for (var index = 0; index < canonicalJourneyActions.length; index++) {
      final action = canonicalJourneyActions[index];
      final gesture = await _startCaptureGesture(
        binding,
        _globalWorldPoint(tester, game, game.shooterOrigin),
      );
      await tester.pump();
      await gesture.moveTo(_globalWorldPoint(tester, game, canonicalWorldPoint(action)));
      await _waitForGame(
        tester,
        game: game,
        session: session,
        predicate: () => game.hasAimedShot,
        checkpoint: 'action ${index + 1}',
        expected: 'a valid shot through the production drag path',
        timeout: _actionTimeout,
      );
      final before = index == CanonicalScene.clusterDrop.actionIndex ? _shotSnapshot(game, actionIndex: index) : null;

      if (index == CanonicalScene.aim.actionIndex) {
        bool isAimReady() =>
            isCanonicalPreciseAim(
              aimAssist: game.pressure.aimAssist,
              hasAimedShot: game.hasAimedShot,
              path: game.aimGuide.path,
              showLanding: game.aimGuide.showLanding,
            ) &&
            hasNoTransientFeedback(game);
        await _waitForGame(
          tester,
          game: game,
          session: session,
          predicate: isAimReady,
          checkpoint: CanonicalScene.aim.fileName,
          expected: 'full aim assistance with a valid visible trajectory and landing guide',
          timeout: CanonicalScene.aim.timeout,
        );
        await _capture(
          binding,
          tester,
          CanonicalScene.aim,
          predicate: isAimReady,
          assertRenderedUi: () => assertGameplayUi(CanonicalScene.aim),
          freezeGame: game,
        );
      }
      if (index == CanonicalScene.bankShot.actionIndex) {
        bool isBankShotReady() => hasCanonicalWallReflection(game.aimGuide.path) && hasNoTransientFeedback(game);
        await _waitForGame(
          tester,
          game: game,
          session: session,
          predicate: isBankShotReady,
          checkpoint: CanonicalScene.bankShot.fileName,
          expected: 'an aim path with at least one wall reflection',
          timeout: CanonicalScene.bankShot.timeout,
        );
        await _capture(
          binding,
          tester,
          CanonicalScene.bankShot,
          predicate: isBankShotReady,
          assertRenderedUi: () => assertGameplayUi(CanonicalScene.bankShot),
          freezeGame: game,
        );
      }
      if (index == CanonicalScene.pressure.actionIndex) {
        bool isPressureReady() =>
            isCanonicalPressureScene(
              ceilingOffset: game.ceilingOffset,
              aimAssist: game.pressure.aimAssist,
              colorCount: game.pressure.colorCount,
              shotsUntilDescent: game.pressure.shotsUntilDescent,
              currentShotKind: game.currentShot.kind,
            ) &&
            hasNoTransientFeedback(game);
        await _waitForGame(
          tester,
          game: game,
          session: session,
          predicate: isPressureReady,
          checkpoint: CanonicalScene.pressure.fileName,
          expected: 'ceiling pressure with trajectory assistance and a visible bomb',
          timeout: CanonicalScene.pressure.timeout,
        );
        await _capture(
          binding,
          tester,
          CanonicalScene.pressure,
          predicate: isPressureReady,
          assertRenderedUi: () => assertGameplayUi(CanonicalScene.pressure),
          freezeGame: game,
        );
      }

      await gesture.up();
      await _waitForGame(
        tester,
        game: game,
        session: session,
        predicate: () => game.status != GameStatus.flying && game.status != GameStatus.transitioning,
        checkpoint: 'action ${index + 1}',
        expected: 'the shot and any ceiling transition to finish',
        timeout: _actionTimeout,
      );

      if (index == CanonicalScene.clusterDrop.actionIndex) {
        final outcome = _shotOutcome(game, before!);
        // The callout is part of this scene by decision (2026-10-01), so it
        // is a readiness condition and the engine freezes on it: timing
        // alone let it expire on one locale and not the other.
        bool isClusterDropReady() =>
            isCanonicalClusterDrop(
              outcome: outcome,
              score: game.score,
              boardSignature: canonicalBoardSignature(game),
              visualStable: hasStableCanonicalClusterVisual(game),
            ) &&
            hasCanonicalScoreCallout(game);
        await _waitForGame(
          tester,
          game: game,
          session: session,
          predicate: isClusterDropReady,
          checkpoint: CanonicalScene.clusterDrop.fileName,
          expected: 'five popped bubbles, a disconnected drop, score 280, and a stable board',
          timeout: CanonicalScene.clusterDrop.timeout,
        );
        await _capture(
          binding,
          tester,
          CanonicalScene.clusterDrop,
          predicate: isClusterDropReady,
          assertRenderedUi: () => assertGameplayUi(CanonicalScene.clusterDrop),
          freezeGame: game,
          requireAimedShot: false,
        );
      }

      if (index < canonicalJourneyActions.length - 1) {
        expect(game.status, GameStatus.aiming);
      }
    }

    await _waitForGame(
      tester,
      game: game,
      session: session,
      predicate: () => session.state.phase == SessionPhase.continueOffer,
      checkpoint: CanonicalScene.highScore.fileName,
      expected: 'the rewarded Continue offer after defeat',
      timeout: CanonicalScene.highScore.timeout,
    );
    expect(find.text(l10n.skipContinue), findsOneWidget);
    final skipContinueButton = find.ancestor(
      of: find.text(l10n.skipContinue),
      matching: find.byType(TextButton),
    );
    expect(skipContinueButton, findsOneWidget);
    tester.widget<TextButton>(skipContinueButton).onPressed!();
    bool isHighScoreReady() =>
        session.state.phase == SessionPhase.results &&
        hasNoTransientFeedback(game) &&
        isCanonicalHighScore(
          status: game.status,
          stats: session.state.lastGameOver,
          freshHighScore: canonicalFreshHighScore,
        );
    await _waitForGame(
      tester,
      game: game,
      session: session,
      predicate: isHighScoreReady,
      checkpoint: CanonicalScene.highScore.fileName,
      expected: 'a finalized high-score result with replay available',
      timeout: CanonicalScene.highScore.timeout,
    );
    await _waitForRouteWidget(
      tester,
      finder: find.text(l10n.playAgain),
      expected: 'the localized replay action on the finalized result overlay',
    );
    expect(find.text(l10n.playAgain), findsOneWidget);
    await _capture(
      binding,
      tester,
      CanonicalScene.highScore,
      predicate: isHighScoreReady,
      assertRenderedUi: () => assertCanonicalHighScoreUi(
        tester: tester,
        scene: CanonicalScene.highScore,
        stats: session.state.lastGameOver!,
        highScore: session.state.highScore,
        l10n: l10n,
      ),
    );
  });
}
