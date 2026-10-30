// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/consent_gateway.dart';

/// Shows a UMP form and reports the dismissal error, if any. Both of the
/// real ones are statics on [ConsentForm], so they are taken as functions
/// rather than reached for directly — otherwise nothing here is testable.
typedef ShowConsentForm = Future<void> Function(
  OnConsentFormDismissedListener onDismissed,
);

/// [ConsentGateway] over Google's User Messaging Platform.
class UmpConsentGateway implements ConsentGateway {
  new({
    ConsentInformation? information,
    ShowConsentForm? loadAndShowIfRequired,
    ShowConsentForm? showPrivacyForm,
  }) : _information = information ?? ConsentInformation.instance,
       _loadAndShowIfRequired = loadAndShowIfRequired ?? ConsentForm.loadAndShowConsentFormIfRequired,
       _showPrivacyForm = showPrivacyForm ?? ConsentForm.showPrivacyOptionsForm;

  final ConsentInformation _information;
  final ShowConsentForm _loadAndShowIfRequired;
  final ShowConsentForm _showPrivacyForm;

  final ValueNotifier<bool> _privacyOptionsRequired = ValueNotifier(false);

  bool _canRequestAds = false;

  @override
  bool get canRequestAds => _canRequestAds;

  @override
  ValueListenable<bool> get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> gather() async {
    try {
      await _requestUpdate();
      // A dismissal error here is not a reason to stop: the status queries
      // below report what actually happened, whatever the form did.
      await _loadAndShowIfRequired((_) {});
      // UMP answers this, rather than a flag kept here: `canRequestAds`
      // reports "whether the app has completed the necessary steps for
      // gathering updated user consent", which already accounts for an
      // update that failed. Forcing it false on a failed refresh would take
      // ads from a player who consented in an earlier session over a network
      // hiccup, and would close no gap — one who never consented is refused
      // by this same call.
      await _readState();
    } on Exception {
      // Contract: never throws. A dead network, a missing plugin or a
      // platform refusal all leave the app playable with ads unavailable —
      // consent gates ads, not play (spec §Privacy).
      _canRequestAds = false;
    }
  }

  /// The one UMP call that is still callback-shaped. Both listeners resolve
  /// the same completer, and each guards against completing twice — the
  /// platform calling back more than once would otherwise crash the app
  /// rather than the ad simply not showing.
  Future<void> _requestUpdate() {
    final updated = Completer<void>();
    void finish() {
      if (!updated.isCompleted) updated.complete();
    }

    _information.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      finish,
      (_) => finish(),
    );
    return updated.future;
  }

  Future<void> _readState() async {
    _canRequestAds = await _information.canRequestAds();
    _privacyOptionsRequired.value =
        await _information.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;
  }

  @override
  Future<void> showPrivacyOptions() async {
    try {
      await _showPrivacyForm((_) {});
    } on Exception {
      // Same contract as [gather]: a form that will not open is not worth
      // taking the Settings screen down with it, and it changed nothing.
      return;
    }
    try {
      // This form is where a player withdraws consent, and the channel call
      // above resolves from its dismissal listener — so the new choice is
      // already recorded and re-reading it is what makes a withdrawal take
      // effect this session rather than the next launch.
      await _readState();
    } on Exception {
      // The form ran and the answer is unreadable from here. The unknown
      // that cannot hurt the player is "no ads".
      _canRequestAds = false;
    }
  }
}
