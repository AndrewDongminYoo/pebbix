// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/loading/loading.dart';
import 'package:bubble_shooter/title/title.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(FakeRoute());
  });

  group('TitlePage', () {
    testWidgets('renders TitleView', (tester) async {
      await tester.pumpApp(const TitlePage());
      expect(find.byType(TitleView), findsOneWidget);
    });
  });

  group('TitleView', () {
    testWidgets('renders start button', (tester) async {
      await tester.pumpApp(const TitleView());

      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets("lines up the board's bubbles, cached sprites included", (tester) async {
      final image = await tester.runAsync(createTestImage);
      final preload = MockPreloadCubit();
      when(() => preload.state).thenReturn(
        PreloadState.initial(
          images: Images(prefix: '')..add(BubbleColor.red.spriteAsset.path, image!),
          audio: MockAudioCache(),
        ),
      );

      await tester.pumpApp(const TitleView(), preloadCubit: preload);

      // The first screen shows the palette the board actually deals, drawn
      // by the same painter, rather than a stand-in set of its own.
      final bubbles = tester.widgetList<LegendBubble>(find.byType(LegendBubble)).toList();
      expect(bubbles.map((bubble) => bubble.shot.color), BubbleColor.values);
      expect(bubbles.map((bubble) => bubble.shot.kind), everyElement(ShotKind.normal));
      expect(bubbles.first.sprite?.image, same(image));
      expect(bubbles.skip(1).map((bubble) => bubble.sprite), everyElement(isNull));
    });

    testWidgets('uses readable system status icons over the nebula', (tester) async {
      await tester.pumpApp(const TitlePage());

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.statusBarIconBrightness, Brightness.light);
      expect(region.value.statusBarBrightness, Brightness.dark);
    });

    testWidgets('opens settings without starting a run', (tester) async {
      final settings = InMemorySettingsRepository();

      await tester.pumpApp(const TitleView(), settingsRepository: settings);
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Spec §Privacy: the policy has to be readable before the first game,
      // and Settings used to hang off the pause panel alone.
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('a settings change made before playing is stored', (tester) async {
      final settings = InMemorySettingsRepository();

      await tester.pumpApp(const TitleView(), settingsRepository: settings);
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      // No AudioCubit exists above GamePage, so this route only writes; the
      // next AudioCubit seeds itself from what was written here.
      expect(settings.settings.musicEnabled, isFalse);
    });

    testWidgets('the policy row opens the published page', (tester) async {
      final launcher = FakeUrlLauncher.install();

      await tester.pumpApp(const TitleView(), settingsRepository: InMemorySettingsRepository());
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      // Asserted at the platform boundary, not at the callback: what matters
      // is the URL a device would be sent to.
      expect(launcher.opened, ['https://pebbix.donminzzi.kr/en/privacy']);
    });

    testWidgets('the policy row is enabled where the consent form is not', (tester) async {
      await tester.pumpApp(const TitleView(), settingsRepository: InMemorySettingsRepository());
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      ListTile rowFor(String label) => tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );

      // One states what the app collects, the other changes an ad-consent
      // choice. UMP only requires its entry point in some regions; the
      // policy is readable in all of them, so they must not share a state.
      expect(rowFor('Privacy Policy').enabled, isTrue);
      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      expect(rowFor('Privacy options').enabled, isFalse);
    });

    testWidgets('the consent row works from the title too', (tester) async {
      final consent = FakeConsentGateway(privacyOptionsRequired: true);

      await tester.pumpApp(
        const TitleView(),
        settingsRepository: InMemorySettingsRepository(),
        consentGateway: consent,
      );
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      // `ConsentGateway`'s contract says Settings offers this row wherever
      // the region requires it — not "wherever the region requires it and
      // the player has already started a game". The first version of this
      // route passed neither the requirement nor the callback, leaving it
      // permanently disabled here.
      expect(consent.privacyOptionsShownCount, 1);
    });

    testWidgets('opens the rules without starting a run', (tester) async {
      final observer = MockNavigatorObserver();
      final preload = MockPreloadCubit();
      when(() => preload.state).thenReturn(
        PreloadState.initial(
          images: Images(prefix: ''),
          audio: MockAudioCache(),
        ),
      );

      await tester.pumpApp(const TitleView(), navigatorObserver: observer, preloadCubit: preload);
      await tester.tap(find.text('How to play'));
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayPage), findsOneWidget);
      verifyNever(
        () => observer.didReplace(
          newRoute: any(named: 'newRoute'),
          oldRoute: any(named: 'oldRoute'),
        ),
      );
    });

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('keeps Start and the rules in reach at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpApp(
          const TitleView(),
          locale: const Locale('ko'),
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
        for (final label in ['시작', '게임 방법']) {
          expect(tester.getRect(find.text(label)).overlaps(Offset.zero & size), isTrue, reason: label);
        }
      });
    }

    testWidgets('starts the game when start button is tapped', (tester) async {
      final observer = MockNavigatorObserver();

      await tester.pumpApp(const TitleView(), navigatorObserver: observer);

      // Deliberately no pumpAndSettle: the observer is notified as the route
      // is installed, before GamePage's overlay entry builds. Settling here
      // would mount the real GamePage, which needs a loaded PreloadCubit and
      // the audioplayers platform channel — neither belongs in a title test.
      await tester.tap(find.byType(ElevatedButton));

      verify(
        () => observer.didReplace(
          newRoute: any(named: 'newRoute'),
          oldRoute: any(named: 'oldRoute'),
        ),
      ).called(1);
    });
  });
}
