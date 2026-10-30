// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';

void main() {
  test(
    'FakeAdsGateway returns its configured outcome and counts shows',
    () async {
      final ads = FakeAdsGateway(rewardedOutcome: RewardedOutcome.dismissed);
      expect(ads.rewardedReady, isTrue);
      expect(ads.interstitialReady, isTrue);
      expect(await ads.showRewarded(), RewardedOutcome.dismissed);
      await ads.showInterstitial();
      expect(ads.interstitialShownCount, 1);
      await ads.start();
      await ads.stop();
      expect(ads.startCount, 1);
      expect(ads.stopCount, 1);
    },
  );

  test('FakeConsentGateway opens only after a successful gather', () async {
    final consent = FakeConsentGateway();

    // Fail-closed: this fake is the shipped implementation until the UMP
    // adapter lands, so "before consent resolves" must mean no ads.
    expect(consent.canRequestAds, isFalse);

    await consent.gather();
    expect(consent.canRequestAds, isTrue);
    expect(consent.gatherCount, 1);

    // The privacy form is where consent is withdrawn, and the real gateway
    // re-reads the state there, so the fake has to be able to close too.
    consent.privacyChoice = false;
    await consent.showPrivacyOptions();
    expect(consent.canRequestAds, isFalse);
  });

  test('FakeConsentGateway stays closed when gathering fails', () async {
    final consent = FakeConsentGateway(gatherFails: true);

    // A failure still completes — the real one never throws either.
    await consent.gather();

    expect(consent.canRequestAds, isFalse);
  });

  test('FakeEntitlementRepository defaults to ads on', () {
    expect(FakeEntitlementRepository().adsRemoved, isFalse);
    expect(FakeEntitlementRepository(adsRemoved: true).adsRemoved, isTrue);
  });

  test('the AnalyticsSink base swallows events', () {
    const createAnalyticsSink = AnalyticsSink.new;
    createAnalyticsSink().track('run_start', {'run_number': 1});
  });

  test('FakePurchaseGateway revokes on an empty restore', () async {
    final gateway = FakePurchaseGateway(adsRemoved: true);

    await gateway.restore();

    // The real gateway treats the store's empty answer as authoritative, and
    // a fake that kept suppressing ads would let a test — or the web and
    // macOS dev builds — pass on behaviour the contract forbids.
    expect(gateway.adsRemoved, isFalse);
  });
}
