enum RewardedOutcome { earned, dismissed, failed }

/// Plugin-agnostic ad surface; the real AdMob adapter arrives in the
/// native-adapters phase (spec §9 step 4).
abstract interface class AdsGateway {
  /// Initializes the ad SDK and starts preloading, once per launch and only
  /// after consent allows ad requests — an SDK initialized before that would
  /// request ads the player has not agreed to.
  ///
  /// Never throws. It is fired unawaited from startup, so an SDK that will
  /// not come up costs the ads, not the launch.
  Future<void> start();

  /// Drops whatever is loaded and requests nothing further until [start] runs
  /// again. Called when consent is withdrawn, which can happen mid-session
  /// through the Settings privacy form.
  ///
  /// Never throws, for the same reason [start] does not.
  Future<void> stop();

  bool get rewardedReady;
  bool get interstitialReady;
  Future<RewardedOutcome> showRewarded();
  Future<void> showInterstitial();
}
