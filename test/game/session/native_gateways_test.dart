// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ad_setup.dart';
import 'package:bubble_shooter/game/session/admob_ads_gateway.dart';
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/fakes.dart';
import 'package:bubble_shooter/game/session/native_gateways.dart';
import 'package:bubble_shooter/game/session/no_ads_gateways.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/store_purchase_gateway.dart';
import 'package:bubble_shooter/game/session/ump_consent_gateway.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('ad-free defaults never expose a store or change a cached purchase', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      for (final cached in [false, true]) {
        final settings = InMemorySettingsRepository(cachedAdsRemoved: cached);
        final entitlements = createEntitlements(
          adSetupFor(AppFlavor.production),
          settings: settings,
          analytics: const AnalyticsSink(),
        );

        expect(entitlements, isNot(isA<PurchaseGateway>()));
        expect(entitlements.adsRemoved, isTrue);
        expect(settings.cachedAdsRemoved, cached);
      }
    }
  });

  test('an explicitly enabled ad setup retains store purchases', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final entitlements = createEntitlements(
      adSetupFor(AppFlavor.production, adsEnabled: true),
      settings: InMemorySettingsRepository(),
      analytics: const AnalyticsSink(),
    );

    expect(entitlements, isA<StorePurchaseGateway>());
  });

  test('every flavor gets the real adapters where AdMob has a plugin', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;

      for (final flavor in AppFlavor.values) {
        final gateways = createGateways(adSetupFor(flavor, adsEnabled: true));

        expect(gateways.consent, isA<UmpConsentGateway>());
        expect(gateways.ads, isA<AdMobAdsGateway>());
      }
    }
  });

  test('falls back to the fakes everywhere else', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;

      final gateways = createGateways(adSetupFor(AppFlavor.development, adsEnabled: true));

      // google_mobile_ads declares Android and iOS only; the real adapters
      // would fail every call with a MissingPluginException on the desktop
      // and web builds this app also produces.
      expect(gateways.consent, isA<FakeConsentGateway>());
      expect(gateways.ads, isA<FakeAdsGateway>());
    }
  });

  test('a setup with no ad vendor gets the no-ads adapters on every platform', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;

      final gateways = createGateways(const NoAdsSetup());

      expect(gateways.consent, isA<NoConsentGateway>());
      expect(gateways.ads, isA<NoAdsGateway>());
    }
  });

  test('uses the real store adapter where a store exists', () {
    for (final entry in {TargetPlatform.android: playStore, TargetPlatform.iOS: appStore}.entries) {
      debugDefaultTargetPlatformOverride = entry.key;

      final purchases = createPurchases(
        settings: InMemorySettingsRepository(),
        analytics: const AnalyticsSink(),
      );

      expect(purchases, isA<StorePurchaseGateway>());
      // The `store` parameter of spec §7's purchase events is decided here,
      // and nothing downstream can recover it if this picks wrong.
      expect((purchases as StorePurchaseGateway).store, entry.value);
    }
  });

  test('falls back to the in-memory store everywhere else', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;

      // macOS is excluded although `in_app_purchase` supports it: the app is
      // submitted to Play and the iOS App Store only, so there is no macOS
      // product record to query.
      final purchases = createPurchases(
        settings: InMemorySettingsRepository(),
        analytics: const AnalyticsSink(),
      );

      expect(purchases, isA<FakePurchaseGateway>());
      // Priced, or the row this fallback exists to keep exercisable renders
      // permanently disabled: Settings opens the offer only once a store has
      // named a price.
      expect(purchases.offer.value.price, devFakePrice);
    }
  });
}
