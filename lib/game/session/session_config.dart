/// Interstitial cadence constants, fixed in spec §4. Hard-coded for
/// v1.0 — Remote Config tuning is explicitly out of scope.
class SessionConfig {
  const new({
    this.minCompletedRunsBeforeFirstInterstitial = 3,
    this.completedRunsPerInterstitial = 3,
    this.minInterstitialInterval = const Duration(minutes: 2),
  });

  final int minCompletedRunsBeforeFirstInterstitial;
  final int completedRunsPerInterstitial;
  final Duration minInterstitialInterval;
}
