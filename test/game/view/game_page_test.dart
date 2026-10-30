// Not needed for test files
// ignore_for_file: prefer_const_constructors

// 🎯 Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flame/cache.dart';
import 'package:flame/components.dart' show Vector2;
import 'package:flame/game.dart' show FlameGame, GameWidget;
import 'package:flame_audio/bgm.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/gen/app_localizations_en.dart';
import 'package:bubble_shooter/loading/cubit/cubit.dart';
import 'package:bubble_shooter/title/title.dart';

import '../../helpers/helpers.dart';

/// An interstitial that never dismisses, so a session can be handed to a new
/// page while its ad is still in flight.
class _HangingAds extends FakeAdsGateway {
  @override
  Future<void> showInterstitial() => Completer<void>().future;
}

class _FakeAssetSource extends Fake implements AssetSource;

class _FakeImage extends Fake implements ui.Image;

class _MockAudioCubit extends MockCubit<AudioState> implements AudioCubit;

class _MockImages extends Mock implements Images;

class _MockBgm extends Mock implements Bgm;

class _MockPreloadCubit extends MockCubit<PreloadState> implements PreloadCubit;

ShotResult shotTo(HexCell landing) {
  final center = BubbleShooter.geometry.center(landing);
  return ShotResult(
    path: [
      const Point(BubbleShooter.worldWidth / 2, 720),
      Point(center.x, center.y),
      Point(center.x, center.y),
    ],
    landingCell: landing,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // https://github.com/material-foundation/flutter-packages/issues/286#issuecomment-1406343761
  HttpOverrides.global = null;

  setUpAll(() async {
    registerFallbackValue(AudioPauseReason.lifecycle);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null)
      ..setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global/events'), (_) async => null);
    // Bgm creates a real AudioPlayer. Finish its shared initialization outside
    // a widget's fake async zone so later backend tests can await it too.
    await AudioPlayer.global.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('xyz.luan/audioplayers'),
      (message) => null,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (message) async => switch (message.method) {
        ('getTemporaryDirectory' || 'getApplicationSupportDirectory') =>
          Directory.systemTemp.createTempSync('fake').path,
        _ => null,
      },
    );
  });

  group('GamePage', () {
    late PreloadCubit preloadCubit;
    late Images images;

    setUpAll(() {
      registerFallbackValue(_FakeAssetSource());
    });

    setUp(() {
      images = _MockImages();
      when(() => images.fromCache(any())).thenReturn(_FakeImage());
      when(() => images.containsKey(any())).thenReturn(false);

      preloadCubit = _MockPreloadCubit();
      when(() => preloadCubit.state).thenReturn(
        PreloadState.initial(
          images: images,
          audio: AudioCache(prefix: ''),
        ),
      );
    });

    testWidgets('is routable', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.of(context).push(GamePage.route()),
            ),
          ),
        ),
        preloadCubit: preloadCubit,
      );

      await tester.tap(find.byType(FloatingActionButton));

      await tester.pump();
      await tester.pump();

      expect(find.byType(GamePage), findsOneWidget);

      await tester.pumpWidget(Container());
    });

    testWidgets('renders GameView', (tester) async {
      await tester.pumpApp(const GamePage(), preloadCubit: preloadCubit);
      expect(find.byType(GameView), findsOneWidget);
    });

    testWidgets('forwards live system reduced-motion changes to the crew', (tester) async {
      final reduceMotion = ValueNotifier(false);
      addTearDown(reduceMotion.dispose);
      final game = _shooter();
      await tester.pumpApp(
        ValueListenableBuilder(
          valueListenable: reduceMotion,
          builder: (context, reduced, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: GamePage(game: game),
          ),
        ),
        preloadCubit: preloadCubit,
      );
      await tester.pump();
      expect(game.defenderMotion.reducedMotion, isFalse);
      reduceMotion.value = true;
      await tester.pump();
      expect(game.defenderMotion.reducedMotion, isTrue);
      reduceMotion.value = false;
      await tester.pump();
      expect(game.defenderMotion.reducedMotion, isFalse);
      await tester.pumpWidget(Container());
    });

    testWidgets('forwards an injected game to GameView', (tester) async {
      final game = TestGame();

      await tester.pumpApp(GamePage(game: game), preloadCubit: preloadCubit);

      expect(tester.widget<GameView>(find.byType(GameView)).game, same(game));
    });

    testWidgets('uses readable system status icons over the game', (tester) async {
      await tester.pumpApp(const GamePage(), preloadCubit: preloadCubit);

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.statusBarIconBrightness, Brightness.light);
      expect(region.value.statusBarBrightness, Brightness.dark);
    });
  });

  group('GameView', () {
    late AudioCubit audioCubit;
    late AudioState initialState;

    setUp(() {
      audioCubit = _MockAudioCubit();
      final bgm = _MockBgm();
      when(() => bgm.play(any())).thenAnswer((_) async {});
      when(bgm.pause).thenAnswer((_) async {});
      initialState = AudioState(bgm: bgm);
      when(() => audioCubit.state).thenReturn(initialState);
      when(
        () => audioCubit.start(any(), effects: any(named: 'effects')),
      ).thenAnswer((_) async {});
      when(
        () => audioCubit.pauseBackgroundMusic(any()),
      ).thenAnswer((_) async {});
      when(
        () => audioCubit.resumeBackgroundMusic(any()),
      ).thenAnswer((_) async {});
      when(() => audioCubit.stopEffect(any())).thenAnswer((_) async {});
    });

    testWidgets('keeps the playable surface below top and side system insets', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 24, left: 8, right: 12);
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: TestGame())),
        ),
      );
      await tester.pump();

      expect(tester.getRect(find.byType(GameView)), Offset.zero & const Size(320, 568));
      expect(tester.getRect(find.byType(GameWidget<FlameGame>)), const Rect.fromLTWH(8, 24, 300, 544));
    });

    testWidgets('starts the background loop through the cubit', (tester) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = TestGame();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );

      // Every generated cue but the loop is handed over to be warmed, so a
      // cue added later does not silently miss prewarming.
      verify(
        () => audioCubit.start(
          Assets.audio.background,
          effects: Assets.audio.values.where((asset) => asset != Assets.audio.background).toList(),
        ),
      ).called(1);
    });

    testWidgets('pauses and resumes the loop across the app lifecycle', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = TestGame();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );

      // AppLifecycleListener rejects skipped states, so the walk down and
      // back up has to visit every intermediate one.
      const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump();

      verify(() => audioCubit.pauseBackgroundMusic(any())).called(1);
      verifyNever(() => audioCubit.resumeBackgroundMusic(any()));

      const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump();

      verify(() => audioCubit.resumeBackgroundMusic(any())).called(1);
    });

    testWidgets('pauses the loop for an interruption that never backgrounds', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = TestGame();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );

      // A phone call moves iOS to inactive and straight back to resumed —
      // it never reaches paused, so a pause hung off onPause would let the
      // loop play through the call.
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await tester.pump();

      verify(() => audioCubit.pauseBackgroundMusic(any())).called(1);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump();

      verify(() => audioCubit.resumeBackgroundMusic(any())).called(1);
    });

    testWidgets('HUD does not block game input', (tester) async {
      // The default 800x600 surface letterboxes the fixed-resolution
      // viewport away from the top-left HUD; the portrait target viewport
      // is where the two actually overlap.
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final game = BubbleShooter(
        l10n: AppLocalizationsEn(),
        playSfx: (_) {},
        textStyle: const TextStyle(),
        images: Images(prefix: ''),
        seed: 42,
      );

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      // Drag from on top of the HUD text: the aim must still reach the game.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Score: 0')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(20, -40));
      await tester.pump();

      expect(game.aimGuide.path, isNotNull);
      await gesture.cancel();
    });

    testWidgets('large Korean gameplay surfaces do not overlap in target viewports', (tester) async {
      tester.view
        ..physicalSize = const Size(568, 320)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pump();

      expect(find.text('점수: 0'), findsOneWidget);
      expect(find.text('천장까지 6발'), findsOneWidget);
      expect(find.text('깊이: 0줄'), findsOneWidget);
      expect(find.text('조준: 정확'), findsOneWidget);
      expect(find.text('끌어서 조준하고 놓아서 발사하세요'), findsOneWidget);

      for (final size in [const Size(568, 320), const Size(320, 568)]) {
        tester.view.physicalSize = size;
        await tester.pump();

        expect(tester.takeException(), isNull);
        final scoreRect = tester.getRect(find.byType(ScoreHud));
        final pauseRect = tester.getRect(find.byType(IconButton));
        final tutorialRect = tester.getRect(find.byType(TutorialHint));
        expect(scoreRect.overlaps(pauseRect), isFalse, reason: '$scoreRect overlaps $pauseRect at $size');
        expect(scoreRect.overlaps(tutorialRect), isFalse, reason: '$scoreRect overlaps $tutorialRect at $size');
        expect(pauseRect.overlaps(tutorialRect), isFalse, reason: '$pauseRect overlaps $tutorialRect at $size');
      }
    });

    testWidgets('AND-122 HUD fits both target viewports at every aim tier', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      final cases = <({AimAssistLevel aim, int depth, Size size, String text})>[
        (
          aim: AimAssistLevel.full,
          depth: 0,
          size: const Size(320, 568),
          text: 'Aim: Exact',
        ),
        (
          aim: AimAssistLevel.trajectory,
          depth: 1,
          size: const Size(320, 568),
          text: 'Aim: Path',
        ),
        (
          aim: AimAssistLevel.direction,
          depth: 3,
          size: const Size(568, 320),
          text: 'Aim: Direction',
        ),
        (
          aim: AimAssistLevel.hidden,
          depth: 5,
          size: const Size(568, 320),
          text: 'Aim: Off',
        ),
      ];

      for (final qaCase in cases) {
        tester.view.physicalSize = qaCase.size;
        await tester.pump();

        game
          ..currentShot = const (
            color: BubbleColor.yellow,
            kind: ShotKind.bomb,
          )
          ..nextShot = const (
            color: BubbleColor.blue,
            kind: ShotKind.rainbow,
          )
          ..ceilingOffset = qaCase.depth
          ..pressureNotifier.value = (
            aimAssist: qaCase.aim,
            ceilingOffset: qaCase.depth,
            colorCount: qaCase.depth >= 4
                ? 6
                : qaCase.depth >= 2
                ? 5
                : 4,
            shotsUntilDescent: 2,
          )
          ..aimAt(Vector2(game.shooterOrigin.x + 1, 0));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '${qaCase.size}');
        expect(find.text('Depth: ${qaCase.depth}'), findsOneWidget);
        expect(find.text(qaCase.text), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsOneWidget);
      }
    });

    testWidgets('builds the game over overlay and restarts from it', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      // No shot is fired here, so the effect player is never played.
      final game = BubbleShooter(
        l10n: AppLocalizationsEn(),
        playSfx: (_) {},
        textStyle: TextStyle(),
        images: Images(prefix: ''),
        seed: 3,
      );

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.status = GameStatus.victory;
      game.overlays.add(BubbleShooter.gameOverOverlayKey);
      await tester.pump();

      expect(find.byType(GameOverOverlay), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(game.status, GameStatus.aiming);
    });

    testWidgets('offers Continue on defeat and revives on accept', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = BubbleShooter(
        l10n: AppLocalizationsEn(),
        playSfx: (_) {},
        textStyle: TextStyle(),
        images: Images(prefix: ''),
        seed: 3,
      );

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue (watch ad)'), findsOneWidget);
      await tester.tap(find.text('Continue (watch ad)'));
      await tester.pump();

      expect(game.status, GameStatus.transitioning);
      expect(find.text('Continue (watch ad)'), findsNothing);
      game
        ..update(0)
        ..update(0.3);
      expect(game.status, GameStatus.aiming);
    });

    testWidgets('cuts the game over cue when a revive resumes play', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = BubbleShooter(
        l10n: AppLocalizationsEn(),
        playSfx: (_) {},
        textStyle: TextStyle(),
        images: Images(prefix: ''),
        seed: 3,
      );

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      // The jingle runs 1-2 s; a granted Continue hands play back well
      // inside that, and it would otherwise ring over the revived run.
      verifyNever(() => audioCubit.stopEffect(any()));
      await tester.tap(find.text('Continue (watch ad)'));
      await tester.pump();

      verify(() => audioCubit.stopEffect(Assets.audio.gameover)).called(1);
    });

    testWidgets('shows the stored best score on the game over overlay', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: InMemorySettingsRepository(highScore: 4200),
      );
      await tester.pump();

      game.status = GameStatus.victory;
      game.overlays.add(BubbleShooter.gameOverOverlayKey);
      await tester.pump();

      expect(find.text('Best: 4200'), findsOneWidget);
    });

    testWidgets('pauses the engine from the HUD and resumes from the panel', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(game.paused, isTrue);

      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(find.byType(PauseOverlay), findsNothing);
      expect(game.paused, isFalse);
    });

    testWidgets('restarts the run from the pause panel', (tester) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.scoreNotifier.value = 999;
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      await tester.tap(find.text('Restart'));
      await tester.pump();

      expect(find.byType(PauseOverlay), findsNothing);
      expect(game.paused, isFalse);
      expect(game.score, 0);
    });

    testWidgets('opens the privacy form where the region needs it', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final consent = FakeConsentGateway(privacyOptionsRequired: true);

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        consentGateway: consent,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Spec §Privacy: privacy options can be reopened from Settings.
      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      expect(consent.privacyOptionsShownCount, 1);
    });

    testWidgets('the in-game policy row opens the published page', (tester) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final launcher = FakeUrlLauncher.install();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      // Same destination as the title-screen route, so a player reaches one
      // policy whichever way they came.
      expect(launcher.opened, ['https://pebbix.donminzzi.kr/en/privacy']);
    });

    testWidgets('a page inheriting a mid-ad session starts muted', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final controller = GameSessionController(
        ads: _HangingAds(),
        entitlements: FakeEntitlementRepository(),
        analytics: const AnalyticsSink(),
        settings: InMemorySettingsRepository(),
      );
      addTearDown(controller.close);
      const stats = GameOverStats(
        score: 10,
        shotCount: 1,
        maxOccupiedRows: 1,
        ceilingDepth: 0,
        continued: false,
        reason: GameOverReason.victory,
      );
      for (var run = 0; run < 3; run++) {
        controller
          ..onRunStarted()
          ..onGameOver(stats);
      }
      expect(controller.state.phase, SessionPhase.interstitialShowing);

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        sessionController: controller,
      );
      await tester.pump();

      // A cubit stream replays nothing, so a page that opens onto a session
      // already mid-ad never hears about it — and its fresh AudioCubit would
      // come up playing under the ad (spec §6).
      verify(
        () => audioCubit.pauseBackgroundMusic(AudioPauseReason.ad),
      ).called(1);
    });

    testWidgets('session accounting survives leaving the game page', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final controller = GameSessionController(
        ads: FakeAdsGateway(),
        entitlements: FakeEntitlementRepository(),
        analytics: const AnalyticsSink(),
        settings: InMemorySettingsRepository(),
      );
      addTearDown(controller.close);

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        sessionController: controller,
      );
      await tester.pump();
      final afterFirstEntry = controller.state.runNumber;

      // Home tears the page down; the session is not the page.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        sessionController: controller,
      );
      await tester.pump();

      // AND-117: a player who taps Home after each result would otherwise
      // never reach the interstitial threshold, and every run would report
      // number 1.
      expect(afterFirstEntry, 1);
      expect(controller.state.runNumber, 2);
    });

    testWidgets('a privacy choice reaches the ads that run on it', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final consent = FakeConsentGateway(privacyOptionsRequired: true)..privacyChoice = false;
      final ads = FakeAdsGateway();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        consentGateway: consent,
        adsGateway: ads,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      // Withdrawing here has to drop what is already loaded: an ad paid for
      // under the old consent is still an ad the current state refuses.
      expect(ads.stopCount, 1);
      expect(ads.startCount, 0);

      consent.privacyChoice = true;
      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      // And granting it is worth this session, not the next launch.
      expect(ads.startCount, 1);
    });

    testWidgets('enables the privacy row if consent resolves late', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final consent = FakeConsentGateway();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        consentGateway: consent,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // gather() is deliberately off the critical path, so the player can
      // already be standing here when it lands. A row that snapshotted the
      // requirement at route creation would stay dead for the whole visit.
      consent.privacyOptionsRequired.value = true;
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      expect(consent.privacyOptionsShownCount, 1);
    });

    testWidgets('leaves the privacy row disabled where it is not required', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final consent = FakeConsentGateway();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        consentGateway: consent,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      // UMP only requires the entry point in some regions; elsewhere the
      // row stays inert rather than opening an empty form.
      expect(consent.privacyOptionsShownCount, 0);
    });

    testWidgets('saves settings changes and applies them to the audio', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      when(
        () => audioCubit.applySettings(
          const GameSettings(musicEnabled: false),
        ),
      ).thenAnswer((_) async {});

      final settings = InMemorySettingsRepository();
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.tap(find.text('Music'));
      await tester.pump();

      expect(settings.settings.musicEnabled, isFalse);
      verify(
        () => audioCubit.applySettings(
          const GameSettings(musicEnabled: false),
        ),
      ).called(1);
    });

    testWidgets('hides the first-run hint once the first shot is fired', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository();
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      expect(find.byType(TutorialHint), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GameView)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(10, -60));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(find.byType(TutorialHint), findsNothing);
      expect(settings.tutorialSeen, isTrue);
    });

    testWidgets('withdraws pause once the run is no longer playing', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.pause), findsOneWidget);

      // A pause panel opened over the continue offer would offer a second
      // Restart that skips finalization, so the lost run would never reach
      // run_end, the high score, or the interstitial cadence.
      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue (watch ad)'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);
    });

    testWidgets('large Korean continue offer owns the compact surface', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(GameOverOverlay), findsOneWidget);
      expect(find.byType(ScoreHud), findsNothing);
      expect(find.byType(TutorialHint), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.text('게임 오버'), findsOneWidget);
      expect(find.text('이어하기 (광고 보기)'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget);
      expect(find.text('홈'), findsOneWidget);
      expect(find.text('깊이: 0줄'), findsNothing);

      await tester.ensureVisible(find.text('건너뛰기'));
      await tester.pump();
      await tester.tap(find.text('건너뛰기'));
      await tester.pump();

      expect(find.text('다시 하기'), findsOneWidget);
      expect(find.text('깊이: 0줄'), findsOneWidget);
      await tester.ensureVisible(find.text('홈'));
      await tester.pump();
      await tester.tap(find.text('홈'));
      await tester.pumpAndSettle();
      expect(find.byType(TitlePage), findsOneWidget);
    });

    testWidgets('keeps the tutorial hint out from over the pause panel', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      expect(find.byType(TutorialHint), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(find.byType(TutorialHint), findsNothing);

      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(find.byType(TutorialHint), findsOneWidget);
    });

    testWidgets('opens the rules from pause and comes back still paused', (tester) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );
      final preload = _MockPreloadCubit();
      when(() => preload.state).thenReturn(
        PreloadState.initial(
          images: Images(prefix: ''),
          audio: AudioCache(prefix: ''),
        ),
      );
      final game = _shooter();

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        preloadCubit: preload,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.text('How to play'));
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayPage), findsOneWidget);
      expect(game.paused, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayPage), findsNothing);
      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(game.paused, isTrue);
    });

    testWidgets('large Korean pause owns the compact surface', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        locale: const Locale('ko'),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(tester.getSize(find.byType(PauseOverlay)).width, 320);
      expect(find.byType(ScoreHud), findsNothing);
      expect(find.byType(TutorialHint), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.text('일시정지'), findsOneWidget);
      expect(find.text('계속하기'), findsOneWidget);
      expect(find.text('게임 방법'), findsOneWidget);
      expect(find.text('설정'), findsOneWidget);
      expect(find.text('다시 시작'), findsOneWidget);

      await tester.ensureVisible(find.text('다시 시작'));
      await tester.pump();
      await tester.tap(find.text('다시 시작'));
      await tester.pump();
      expect(find.byType(PauseOverlay), findsNothing);
      expect(find.byType(ScoreHud), findsOneWidget);
    });

    testWidgets('returns to the title screen from the results panel', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.status = GameStatus.victory;
      game.overlays.add(BubbleShooter.gameOverOverlayKey);
      await tester.pump();

      // TitlePage enters the game with pushReplacement, so Home is the only
      // way back and has to replace rather than pop.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(TitlePage), findsOneWidget);
      expect(find.byType(GameView), findsNothing);
    });

    testWidgets('settles a pending continue offer on any exit from the page', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository();
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..scoreNotifier.value = 750
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue (watch ad)'), findsOneWidget);

      // The offer is pre-finalization, so leaving without settling it
      // would drop run_end and the high-score write. Home is one exit;
      // Android Back and any externally replaced route are others, which
      // is why the settling hangs off dispose rather than off Home.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(TitlePage), findsOneWidget);
      expect(settings.highScore, 750);
    });

    testWidgets('settles a pending offer when the page is torn down', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository();
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..scoreNotifier.value = 610
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue (watch ad)'), findsOneWidget);

      // Android Back never reaches _goHome, so the invariant has to hold
      // for a bare teardown too.
      await tester.pumpWidget(Container());

      expect(settings.highScore, 610);
    });

    testWidgets('keeps a mid-play record when the page is torn down', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository(highScore: 200);
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      // No game over: the run is still live, which is the case the HUD
      // already shows as Best and the session used to walk away from.
      game.scoreNotifier.value = 980;
      await tester.pump();
      await tester.pumpWidget(Container());

      expect(settings.highScore, 980);
    });

    testWidgets('keeps a mid-play record when Pause offers Restart', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository(highScore: 200);
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      game.scoreNotifier.value = 980;
      await tester.pump();

      // Restart never tears the page down, so dispose cannot settle it — and
      // startGame() zeroes the score before it emits RunStarted, so the
      // session cannot read it afterwards either.
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      await tester.tap(find.text('Restart'));
      await tester.pump();

      expect(settings.highScore, 980);
    });

    testWidgets('keeps a mid-play record when the app leaves the foreground', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final settings = InMemorySettingsRepository(highScore: 200);
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: settings,
      );
      await tester.pump();

      game.scoreNotifier.value = 980;
      await tester.pump();

      // TitlePage enters with pushReplacement, so GamePage is the only route
      // and Android Back hands the pop to the system instead of disposing
      // this page. Backgrounding is the signal that survives it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(settings.highScore, 980);
    });

    testWidgets('shows the pending run as the best while the offer is open', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
        settingsRepository: InMemorySettingsRepository(highScore: 100),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..scoreNotifier.value = 750
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      // The run is still pre-finalization, so the stored best is stale —
      // showing it verbatim would read `Score: 750` beside `Best: 100`.
      expect(find.text('Continue (watch ad)'), findsOneWidget);
      expect(find.text('Best: 750'), findsOneWidget);
    });

    testWidgets('resumes instead of leaving when Back closes the panel', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(game.paused, isTrue);

      // A Flame overlay is not a route, so an unguarded Back would reach
      // the Navigator and leave the game instead of closing the panel.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(PauseOverlay), findsNothing);
      expect(game.paused, isFalse);
      expect(find.byType(GameView), findsOneWidget);
    });

    testWidgets('pauses the loop while a rewarded ad is showing', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      verifyNever(() => audioCubit.pauseBackgroundMusic(any()));

      // Spec §6: the loop stops for the ad and restores per setting. No
      // lifecycle change happens here, so these calls can only come from
      // the session's ad phases.
      await tester.tap(find.text('Continue (watch ad)'));
      await tester.pump();

      verify(() => audioCubit.pauseBackgroundMusic(any())).called(1);
      verify(() => audioCubit.resumeBackgroundMusic(any())).called(1);
    });

    testWidgets('never shows the hint once the tutorial was seen', (
      tester,
    ) async {
      whenListen(
        audioCubit,
        const Stream<AudioState>.empty(),
        initialState: initialState,
      );

      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: _shooter())),
        ),
        settingsRepository: InMemorySettingsRepository(tutorialSeen: true),
      );
      await tester.pump();

      expect(find.byType(TutorialHint), findsNothing);
    });

    testWidgets('reports the run only once it is finalized, never during the offer', (tester) async {
      final game = _shooter();
      await tester.pumpApp(
        BlocProvider.value(
          value: audioCubit,
          child: Material(child: GameView(game: game)),
        ),
      );
      await tester.pump();

      game.board = BubbleBoard(columns: BubbleShooter.columns);
      fillBelowFailLine(game.board);
      game
        ..boardComponent.syncBoard()
        ..currentColor = BubbleColor.purple
        ..onShotLanded(shotTo(failingCell()));
      await tester.pump();
      await tester.pump();

      // The continue offer is a decision with a deadline, so the run summary
      // stays out of it — the run is not finalized yet either.
      expect(find.text('Continue (watch ad)'), findsOneWidget);
      expect(find.textContaining('per shot'), findsNothing);
      expect(find.textContaining('Depth:'), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();

      // Declining finalizes the run, and the panel then reports what it did.
      expect(find.textContaining('per shot'), findsOneWidget);
      expect(find.text('Depth: 0'), findsOneWidget);
    });
  });
}

/// A seeded game that swallows its cues — no shot in these tests reaches
/// the audio layer, and the seed keeps the board reproducible.
BubbleShooter _shooter() => BubbleShooter(
  l10n: AppLocalizationsEn(),
  playSfx: (_) {},
  textStyle: const TextStyle(),
  images: Images(prefix: ''),
  seed: 3,
);
