import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubble_shooter/app/settings_route.dart';
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

void main() {
  testWidgets('settings hides Analytics opt-in when collection is unavailable', (tester) async {
    tester.view
      ..physicalSize = const Size(568, 320)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = InMemorySettingsRepository();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SettingsRepository>.value(value: settings),
          RepositoryProvider<ConsentGateway>.value(value: FakeConsentGateway()),
          RepositoryProvider<AdsGateway>.value(value: FakeAdsGateway()),
          RepositoryProvider<EntitlementRepository>.value(value: FakeEntitlementRepository()),
          RepositoryProvider<AnalyticsSink>.value(value: const AnalyticsSink()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openSettings(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Share gameplay analytics'), findsNothing);
    await tester.scrollUntilVisible(find.text('Privacy Policy'), 100);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(settings.settings.analyticsEnabled, isFalse);
  });

  testWidgets('settings applies the separate Analytics choice on each change', (tester) async {
    final settings = InMemorySettingsRepository();
    final analytics = _ConsentAnalyticsSink();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SettingsRepository>.value(value: settings),
          RepositoryProvider<ConsentGateway>.value(value: FakeConsentGateway()),
          RepositoryProvider<AdsGateway>.value(value: FakeAdsGateway()),
          RepositoryProvider<EntitlementRepository>.value(value: FakeEntitlementRepository()),
          RepositoryProvider<AnalyticsSink>.value(value: analytics),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openSettings(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final analyticsTile = find.widgetWithText(SwitchListTile, 'Share gameplay analytics');
    await tester.ensureVisible(analyticsTile);
    await tester.tap(analyticsTile);
    await tester.pump();
    expect(settings.settings.analyticsEnabled, isTrue);
    expect(analytics.choices, [true]);

    await tester.tap(analyticsTile);
    await tester.pump();
    expect(settings.settings.analyticsEnabled, isFalse);
    expect(analytics.choices, [true, false]);
  });
}

class _ConsentAnalyticsSink extends AnalyticsSink implements AnalyticsCollectionControl {
  final choices = <bool>[];

  @override
  Future<void> setAnalyticsEnabled({required bool enabled}) async => choices.add(enabled);
}
