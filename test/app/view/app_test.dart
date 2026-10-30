// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/app.dart';
import 'package:bubble_shooter/app/settings_route.dart';
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/loading/loading.dart';

import '../../helpers/helpers.dart';

class _RecordingAnalyticsSink implements AnalyticsSink {
  final events = <(String, Map<String, Object?>)>[];

  @override
  void track(String event, [Map<String, Object?> parameters = const {}]) {
    events.add((event, parameters));
  }
}

void main() {
  group('App', () {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('ad-free startup and settings work at $size without native services', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final launcher = FakeUrlLauncher.install();
        final settings = InMemorySettingsRepository();
        final setup = adSetupFor(AppFlavor.production);
        final gateways = createGateways(setup);
        await tester.pumpWidget(
          App(
            settings: settings,
            consent: gateways.consent,
            ads: gateways.ads,
            entitlements: createEntitlements(setup, settings: settings, analytics: const AnalyticsSink()),
            analytics: const AnalyticsSink(),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 400));
        final route = openSettings(tester.element(find.byType(LoadingPage)));
        await tester.pumpAndSettle();

        expect(find.text('Remove Ads'), findsNothing);
        expect(find.text('Restore Purchases'), findsNothing);
        expect(find.text('Privacy options'), findsNothing);
        await tester.tap(find.text('Music'));
        await tester.pump();
        expect(settings.settings.musicEnabled, isFalse);
        await tester.scrollUntilVisible(find.text('Privacy Policy'), 100);
        await tester.tap(find.text('Privacy Policy'));
        await tester.pumpAndSettle();
        expect(launcher.opened, ['https://pebbix.donminzzi.kr/en/privacy']);
        expect(tester.takeException(), isNull);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await route;
      });
    }

    testWidgets('renders AppView', (tester) async {
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(),
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(),
          entitlements: FakeEntitlementRepository(),
          analytics: const AnalyticsSink(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 400));
      expect(find.byType(AppView), findsOneWidget);
    });

    testWidgets('renders text through the bundled family', (tester) async {
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(),
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(),
          entitlements: FakeEntitlementRepository(),
          analytics: const AnalyticsSink(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 400));

      // Read from inside the MaterialApp: AppView is what builds it, so its
      // own context still sees the default theme.
      // Every screen inherits from here, so this is the one place a Hangul
      // string could fall back to whatever the platform substitutes.
      final theme = Theme.of(tester.element(find.byType(LoadingPage)));
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Pretendard');
    });

    testWidgets('publishes the localized title with the native flavor tag', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ko')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(),
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(),
          entitlements: FakeEntitlementRepository(),
          analytics: const AnalyticsSink(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 400));

      final flavorTag = switch (appFlavor) {
        'development' => '[DEV] ',
        'staging' => '[STG] ',
        _ => '',
      };
      expect(tester.widget<Title>(find.byType(Title)).title, '$flavorTag페빅스');
    });

    testWidgets('publishes one session for the whole app', (tester) async {
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(highScore: 500),
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(),
          entitlements: FakeEntitlementRepository(),
          analytics: const AnalyticsSink(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 400));

      final context = tester.element(find.byType(AppView));
      final session = context.read<GameSessionController>();

      // AND-117: the game page reads this one rather than building its own,
      // so the run count and the interstitial cadence outlive a Home round
      // trip. It is seeded from the app's settings, not from a second store.
      expect(session.state.highScore, 500);
      expect(context.read<GameSessionController>(), same(session));
    });

    testWidgets('supplied entitlement suppresses the app session interstitial', (tester) async {
      final ads = FakeAdsGateway();
      final entitlements = FakeEntitlementRepository(adsRemoved: true);
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(),
          consent: FakeConsentGateway(),
          ads: ads,
          entitlements: entitlements,
          analytics: const AnalyticsSink(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 400));

      final session = tester.element(find.byType(AppView)).read<GameSessionController>();
      const result = GameOverStats(
        score: 100,
        shotCount: 4,
        maxOccupiedRows: 3,
        ceilingDepth: 0,
        continued: false,
        reason: GameOverReason.victory,
      );
      for (var run = 0; run < 3; run++) {
        session
          ..onRunStarted()
          ..onGameOver(result);
        await tester.pump();
      }

      expect(ads.interstitialShownCount, 0);
    });

    testWidgets('supplied analytics receives the app session run start', (tester) async {
      final analytics = _RecordingAnalyticsSink();
      await tester.pumpWidget(
        App(
          settings: InMemorySettingsRepository(),
          consent: FakeConsentGateway(),
          ads: FakeAdsGateway(),
          entitlements: FakeEntitlementRepository(),
          analytics: analytics,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 400));

      tester.element(find.byType(AppView)).read<GameSessionController>().onRunStarted();

      expect(analytics.events.first.$1, 'run_start');
      expect(analytics.events.first.$2, {'run_number': 1});
    });
  });
}
