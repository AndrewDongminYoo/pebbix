// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ump_consent_gateway.dart';

/// Stands in for UMP. `ConsentInformation.instance` is a settable static, so
/// the real gateway takes one of these instead of reaching for the platform.
class _FakeConsentInformation implements ConsentInformation {
  new({
    this.consentAllowsAds = true,
    this.requirement = PrivacyOptionsRequirementStatus.notRequired,
    this.updateFails = false,
    this.callBackTwice = false,
    this.statusThrows = false,
  });

  bool consentAllowsAds;
  PrivacyOptionsRequirementStatus requirement;
  bool updateFails;

  /// Makes the platform invoke a listener more than once, which a naive
  /// completer would turn into a crash.
  bool callBackTwice;
  bool statusThrows;

  int updateCount = 0;

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    OnConsentInfoUpdateSuccessListener success,
    OnConsentInfoUpdateFailureListener failure,
  ) {
    updateCount++;
    if (updateFails) {
      failure(FormError(errorCode: 1, message: 'no network'));
      if (callBackTwice) failure(FormError(errorCode: 1, message: 'again'));
      return;
    }
    success();
    if (callBackTwice) success();
  }

  @override
  Future<bool> canRequestAds() async {
    if (statusThrows) throw Exception('platform refused');
    return consentAllowsAds;
  }

  @override
  Future<PrivacyOptionsRequirementStatus> getPrivacyOptionsRequirementStatus() async => requirement;

  @override
  Future<bool> isConsentFormAvailable() async => true;

  @override
  Future<ConsentStatus> getConsentStatus() async => ConsentStatus.obtained;

  @override
  Future<void> reset() async {}
}

void main() {
  UmpConsentGateway build(
    _FakeConsentInformation information, {
    ShowConsentForm? loadAndShowIfRequired,
    ShowConsentForm? showPrivacyForm,
  }) => UmpConsentGateway(
    information: information,
    loadAndShowIfRequired: loadAndShowIfRequired ?? (_) async {},
    showPrivacyForm: showPrivacyForm ?? (_) async {},
  );

  group(UmpConsentGateway, () {
    test('reports no permission before gather runs', () {
      final gateway = build(_FakeConsentInformation());

      // Fail-closed: nothing may request an ad until UMP has answered.
      expect(gateway.canRequestAds, isFalse);
      expect(gateway.privacyOptionsRequired.value, isFalse);
    });

    test('defaults to the real UMP surface', () {
      // Construction alone must not touch the platform — the defaults are a
      // static instance and two tear-offs, not calls.
      final gateway = UmpConsentGateway();

      expect(gateway.canRequestAds, isFalse);
    });

    test('opens ads and the privacy row once UMP answers', () async {
      final gateway = build(
        _FakeConsentInformation(
          requirement: PrivacyOptionsRequirementStatus.required,
        ),
      );

      await gateway.gather();

      expect(gateway.canRequestAds, isTrue);
      expect(gateway.privacyOptionsRequired.value, isTrue);
    });

    test('shows the form before reading the resulting status', () async {
      final order = <String>[];
      final information = _FakeConsentInformation();
      final gateway = build(
        information,
        loadAndShowIfRequired: (_) async => order.add('form'),
      );

      await gateway.gather();
      order.add('status read');

      // Reading canRequestAds before the form is answered would cache the
      // pre-consent answer for the whole session.
      expect(order, ['form', 'status read']);
      expect(information.updateCount, 1);
    });

    test('a failed update still resolves and leaves ads closed', () async {
      final gateway = build(
        _FakeConsentInformation(updateFails: true, consentAllowsAds: false),
      );

      await gateway.gather();

      expect(gateway.canRequestAds, isFalse);
    });

    test('a failed update defers to UMP, not to a flag here', () async {
      final gateway = build(_FakeConsentInformation(updateFails: true));

      await gateway.gather();

      // The test above covers the closed side. This is the open one: consent
      // obtained in an earlier session survives a refresh that could not
      // reach the network, because UMP reports whether the necessary steps
      // were completed and not whether this launch reached its servers.
      expect(gateway.canRequestAds, isTrue);
    });

    test('a platform that answers twice does not crash the app', () async {
      // Completing a completer twice throws, and this one is reached from a
      // fire-and-forget call at startup, so it would surface as an uncaught
      // error rather than a missing ad.
      final gateway = build(_FakeConsentInformation(callBackTwice: true));

      await expectLater(gateway.gather(), completes);
      expect(gateway.canRequestAds, isTrue);
    });

    test('a throwing status query leaves the app playable', () async {
      final gateway = build(_FakeConsentInformation(statusThrows: true));

      // Contract: gather never throws — consent gates ads, not play.
      await expectLater(gateway.gather(), completes);
      expect(gateway.canRequestAds, isFalse);
    });

    test('a consent form that fails to open is swallowed', () async {
      final gateway = build(
        _FakeConsentInformation(),
        loadAndShowIfRequired: (_) async => throw Exception('form died'),
      );

      await expectLater(gateway.gather(), completes);
      expect(gateway.canRequestAds, isFalse);
    });

    test('a withdrawal through the privacy form closes ads at once', () async {
      final information = _FakeConsentInformation();
      final gateway = build(
        information,
        // UMP resolves this from the form's dismissal listener, so the new
        // choice is already recorded when it returns.
        showPrivacyForm: (_) async => information.consentAllowsAds = false,
      );
      await gateway.gather();
      expect(gateway.canRequestAds, isTrue);

      await gateway.showPrivacyOptions();

      // Serving ads until the next launch would be serving them against the
      // current consent state (spec §Privacy).
      expect(gateway.canRequestAds, isFalse);
    });

    test('an unreadable state after the form closes ads', () async {
      final information = _FakeConsentInformation();
      final gateway = build(
        information,
        showPrivacyForm: (_) async => information.statusThrows = true,
      );
      await gateway.gather();

      await expectLater(gateway.showPrivacyOptions(), completes);

      // The form ran and the answer cannot be read, so the choice that
      // cannot hurt the player wins.
      expect(gateway.canRequestAds, isFalse);
    });

    test('showPrivacyOptions surfaces the form and swallows failure', () async {
      var shown = 0;
      final ok = build(
        _FakeConsentInformation(),
        showPrivacyForm: (_) async => shown++,
      );
      await ok.showPrivacyOptions();
      expect(shown, 1);

      final broken = build(
        _FakeConsentInformation(),
        showPrivacyForm: (_) async => throw Exception('no form'),
      );

      // Settings must survive a form that will not open.
      await expectLater(broken.showPrivacyOptions(), completes);
    });
  });
}
