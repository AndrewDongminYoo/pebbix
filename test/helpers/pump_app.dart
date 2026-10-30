// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';

import 'helpers.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    NavigatorObserver? navigatorObserver,
    PreloadCubit? preloadCubit,
    SettingsRepository? settingsRepository,
    ConsentGateway? consentGateway,
    AdsGateway? adsGateway,
    PurchaseGateway? purchaseGateway,
    AnalyticsSink? analyticsSink,
    GameSessionController? sessionController,
    Locale? locale,
    TextScaler? textScaler,
  }) {
    // Resolved once: the default session controller has to run on the same
    // settings and ads instances the test is asserting against, not on a
    // second set of fakes.
    final settings = settingsRepository ?? InMemorySettingsRepository();
    final ads = adsGateway ?? FakeAdsGateway();
    // The store is also the entitlement the session reads, exactly as the app
    // wires it — so a test that purchases here also stops the interstitials.
    final purchases = purchaseGateway ?? FakePurchaseGateway();
    final analytics = analyticsSink ?? const AnalyticsSink();
    // A fresh session per call, and the caller owns whichever one it passed.
    // `BlocProvider.value` never closes what it is handed, and the suite runs
    // as one merged isolate under `very_good test --optimization`, so an
    // unclosed default would leak a cubit and a live event subscription for
    // every widget test in the run.
    //
    // Per call also means a test that pumps twice gets two sessions: assert
    // continuity across a page teardown by passing one in, the way
    // "session accounting survives leaving the game page" does.
    final session =
        sessionController ??
        GameSessionController(
          ads: ads,
          entitlements: purchases,
          analytics: analytics,
          settings: settings,
        );
    if (sessionController == null) addTearDown(session.close);
    return pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SettingsRepository>.value(value: settings),
          RepositoryProvider<ConsentGateway>.value(
            value: consentGateway ?? FakeConsentGateway(),
          ),
          RepositoryProvider<AdsGateway>.value(value: ads),
          RepositoryProvider<EntitlementRepository>.value(value: purchases),
          RepositoryProvider<AnalyticsSink>.value(value: analytics),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: preloadCubit ?? _emptyPreload()),
            BlocProvider.value(value: session),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: textScaler == null
                ? null
                : (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                    child: child!,
                  ),
            navigatorObservers: [
              ?navigatorObserver,
            ],
            home: widget,
          ),
        ),
      ),
    );
  }
}

/// A preload that finished with nothing cached, so a page that reads the
/// sprite cache, like the title, falls back to the procedural painter.
MockPreloadCubit _emptyPreload() {
  final cubit = MockPreloadCubit();
  when(() => cubit.state).thenReturn(
    PreloadState.initial(
      images: Images(prefix: ''),
      audio: MockAudioCache(),
    ),
  );
  return cubit;
}
