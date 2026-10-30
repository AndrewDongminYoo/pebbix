// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

/// The build flavor, named by the entrypoint that starts the app.
enum AppFlavor { development, staging, production }

/// The two ad units one build requests from.
typedef AdUnitIds = ({String rewarded, String interstitial});

/// Which ad vendor a build talks to, and what it needs to talk to it.
///
/// Sealed so that adding a vendor is a subclass here plus one arm in
/// `createGateways` — the analyzer names every switch that has to grow, and
/// nothing above the `AdsGateway` interface ever learns which vendor is live.
///
/// The vendor is chosen once, at the same seam that already decides
/// fake-versus-real, rather than through conditional imports:
/// `google_mobile_ads` is web-safe as a link-time dependency, so an
/// `_io`/`_stub` shim buys nothing and splits every file it touches.
sealed class AdSetup {
  const new();
}

/// No ad vendor at all.
///
/// The initial release keeps gameplay and local settings without starting ads, consent, or store purchases.
/// SDK dependencies and platform declarations remain in the build.
final class NoAdsSetup extends AdSetup {
  const new();
}

/// AdMob, requesting the units in [unitIds].
final class AdMobSetup extends AdSetup {
  const new(this.unitIds);

  final AdUnitIds unitIds;
}

/// Google's public test units, copied from the plugin's own example. They are
/// the only units this app has, and the only ones debug and test builds may
/// ever use (spec §Quality).
const AdUnitIds _androidTest = (
  rewarded: 'ca-app-pub-3940256099942544/5224354917',
  interstitial: 'ca-app-pub-3940256099942544/1033173712',
);

const AdUnitIds _iosTest = (
  rewarded: 'ca-app-pub-3940256099942544/1712485313',
  interstitial: 'ca-app-pub-3940256099942544/4411468910',
);

/// The only place in the app that decides which ad vendor a build talks to.
///
/// Every flavor defaults to no ads for the initial release.
/// Re-enabling ads requires an explicit code change, not a date or remote setting.
/// The retained opt-in path uses test units until production AdMob configuration is ready.
AdSetup adSetupFor(AppFlavor flavor, {bool adsEnabled = false}) {
  if (!adsEnabled) return const NoAdsSetup();
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  final admob = AdMobSetup(ios ? _iosTest : _androidTest);
  return switch (flavor) {
    AppFlavor.development || AppFlavor.staging || AppFlavor.production => admob,
  };
}
