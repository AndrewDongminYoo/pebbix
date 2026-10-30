// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ad_setup.dart';
import 'package:bubble_shooter/game/session/admob_ads_gateway.dart';
import 'package:bubble_shooter/game/session/ads_gateway.dart';
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/consent_gateway.dart';
import 'package:bubble_shooter/game/session/entitlement_repository.dart';
import 'package:bubble_shooter/game/session/fakes.dart';
import 'package:bubble_shooter/game/session/no_ads_gateways.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/game/session/store_purchase_gateway.dart';
import 'package:bubble_shooter/game/session/ump_consent_gateway.dart';

/// Whether this build runs on a platform that has both an ad SDK and a
/// store. `google_mobile_ads` declares Android and iOS only, and
/// `in_app_purchase` registers a platform for Android, iOS and macOS —
/// nothing web. The real adapters anywhere else would fail every call with a
/// `MissingPluginException`, or throw before the first one when the plugin
/// never registered at all.
///
/// macOS is excluded although the store plugin supports it: the app is
/// submitted to Play and the iOS App Store only, so no macOS product record
/// exists to query.
///
/// The check is [defaultTargetPlatform] rather than `dart:io`, which cannot
/// be imported without breaking the web build.
bool get _hasNativeStores =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// The one place a vendor's adapters are named.
///
/// Two axes: which vendor [setup] names, and whether the platform can run
/// that vendor's plugin at all ([_hasNativeStores]).
///
/// The vendor is read first on purpose. A build configured for no ads gets
/// the no-ads adapters on every platform, so it cannot fall through to the
/// dev fakes, which report both formats ready and would hand out a Continue
/// nothing paid for.
///
/// Takes the resolved [AdSetup] rather than the flavor, so that resolving a
/// vendor and building its adapters stay separate jobs — and so every arm
/// below is reachable from a test without a flavor having to select it.
({ConsentGateway consent, AdsGateway ads}) createGateways(AdSetup setup) {
  return switch (setup) {
    NoAdsSetup() => (consent: NoConsentGateway(), ads: const NoAdsGateway()),
    AdMobSetup() when !_hasNativeStores => (consent: FakeConsentGateway(), ads: FakeAdsGateway()),
    AdMobSetup(:final unitIds) => (
      consent: UmpConsentGateway(),
      ads: AdMobAdsGateway(unitIds: unitIds),
    ),
  };
}

/// The real store adapter where a store exists, the in-repo fake everywhere
/// else — so the purchase UI stays exercisable on the web and macOS dev
/// builds instead of rendering permanently dead.
///
/// The adapter reaches `InAppPurchase.instance` itself, on its first store
/// call rather than here, because the getter registers a store platform and
/// Play's registration opens a billing connection from its own constructor.
PurchaseGateway createPurchases({
  required SettingsRepository settings,
  required AnalyticsSink analytics,
}) {
  // Priced, because the Remove Ads row stays closed until a store names one
  // — an unpriced fake would render the very UI this fallback exists to keep
  // exercisable permanently dead. Deliberately not a plausible amount: this
  // reaches only the web and macOS dev builds, never a store build.
  if (!_hasNativeStores) return FakePurchaseGateway(price: devFakePrice);
  return StorePurchaseGateway(
    settings: settings,
    analytics: analytics,
    store: defaultTargetPlatform == TargetPlatform.android ? playStore : appStore,
  );
}

/// An ad-free release must not connect to the store or sell an unnecessary removal product.
EntitlementRepository createEntitlements(
  AdSetup setup, {
  required SettingsRepository settings,
  required AnalyticsSink analytics,
}) {
  if (setup is NoAdsSetup) return const NoAdsEntitlements();
  return createPurchases(settings: settings, analytics: analytics);
}
