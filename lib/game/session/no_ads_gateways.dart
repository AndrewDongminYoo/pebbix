// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ads_gateway.dart';
import 'package:bubble_shooter/game/session/consent_gateway.dart';
import 'package:bubble_shooter/game/session/entitlement_repository.dart';

/// Suppresses interstitials without granting or persisting a purchased entitlement.
/// This is not a PurchaseGateway, so loading and settings never contact the store.
class NoAdsEntitlements implements EntitlementRepository {
  const new();

  @override
  bool get adsRemoved => true;
}

/// The [AdsGateway] a build with no ad vendor ships on.
///
/// Deliberately not `FakeAdsGateway`, which reports both formats ready and
/// returns [RewardedOutcome.earned] so the web and desktop dev builds can
/// exercise the Continue offer. Shipping that would hand a player a revive
/// no ad ever paid for. This one is its opposite: both flags stay false,
/// and those two flags are the entire gate on both ad paths — `onGameOver`
/// offers Continue only when [rewardedReady], and `_shouldShowInterstitial`
/// returns false without [interstitialReady] — so a run finalizes straight
/// to the results screen and no offer is ever shown that cannot be filled.
class NoAdsGateway implements AdsGateway {
  const new();

  @override
  bool get rewardedReady => false;

  @override
  bool get interstitialReady => false;

  /// Nothing to initialize. Kept a no-op rather than an error for the
  /// interface's contract: `start` never throws, and it is fired unawaited
  /// from startup.
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  /// Unreachable through [rewardedReady], and answered rather than thrown if
  /// something reaches it anyway — the caller has to finalize the run, and a
  /// failed outcome is the path that already does.
  @override
  Future<RewardedOutcome> showRewarded() async => RewardedOutcome.failed;

  /// Throws, because a throw is how "the player never saw it" reaches the
  /// caller: it returns the results screen without recording an impression
  /// and without stamping the cadence clock. Returning normally would claim
  /// an ad was shown.
  @override
  Future<void> showInterstitial() async => throw Exception('no ad vendor configured');
}

/// The [ConsentGateway] a build with no ad vendor ships on.
///
/// UMP exists to decide whether ads may be requested, so a build that
/// requests none has nothing to gather: no form is shown, and
/// [canRequestAds] stays false in line with the fail-closed contract.
///
/// [privacyOptionsRequired] never turns true.
/// The settings route omits the consent callback for this gateway, hiding the unavailable entry.
///
/// The privacy policy link is a separate entry point in Settings and is
/// unaffected — the policy is a store requirement in its own right, not a
/// consequence of serving ads.
class NoConsentGateway implements ConsentGateway {
  new();

  /// Never notifies. Held as a field rather than rebuilt per read so a
  /// listener Settings attaches stays attached to the object it registered
  /// on.
  final ValueNotifier<bool> _neverRequired = ValueNotifier(false);

  @override
  bool get canRequestAds => false;

  @override
  ValueListenable<bool> get privacyOptionsRequired => _neverRequired;

  @override
  Future<void> gather() async {}

  @override
  Future<void> showPrivacyOptions() async {}
}
