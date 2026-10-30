// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ad_setup.dart';
import 'package:bubble_shooter/game/session/native_gateways.dart';

void main() {
  // The suite runs as one merged entrypoint under `very_good test
  // --optimization`, so an override left set here would follow every other
  // file in the run.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('default builds cannot request ads or offer a rewarded continue', () async {
    for (final platform in [TargetPlatform.linux, ...TargetPlatform.values]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final flavor in AppFlavor.values) {
        final gateways = createGateways(adSetupFor(flavor));
        expect(gateways.ads.rewardedReady, isFalse);
        expect(gateways.ads.interstitialReady, isFalse);
        await gateways.consent.gather();
        await gateways.ads.start();
        expect(gateways.consent.canRequestAds, isFalse);
        expect(gateways.consent.privacyOptionsRequired.value, isFalse);
      }
    }
  });

  test('explicit ad enablement retains test units for every flavor', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    for (final flavor in AppFlavor.values) {
      // Spec §Quality: nothing may ship a real unit ID until the AdMob
      // account exists, and debug and test builds never may.
      expect(
        adSetupFor(flavor, adsEnabled: true),
        isA<AdMobSetup>().having(
          (setup) => setup.unitIds,
          'unitIds',
          (
            rewarded: 'ca-app-pub-3940256099942544/5224354917',
            interstitial: 'ca-app-pub-3940256099942544/1033173712',
          ),
        ),
      );
    }
  });

  test('iOS requests its own units', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    // Unit IDs are per platform: an Android unit never fills on iOS.
    expect(
      adSetupFor(AppFlavor.production, adsEnabled: true),
      isA<AdMobSetup>().having(
        (setup) => setup.unitIds,
        'unitIds',
        (
          rewarded: 'ca-app-pub-3940256099942544/1712485313',
          interstitial: 'ca-app-pub-3940256099942544/4411468910',
        ),
      ),
    );
  });
}
