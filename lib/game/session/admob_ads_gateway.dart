// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ad_setup.dart';
import 'package:bubble_shooter/game/session/ads_gateway.dart';

/// Requests one full-screen ad. Both of the real ones are statics on their ad
/// class, so they are taken as functions rather than reached for directly —
/// otherwise nothing here is testable.
typedef LoadRewarded = Future<void> Function({
  required String adUnitId,
  required AdRequest request,
  required RewardedAdLoadCallback rewardedAdLoadCallback,
});

typedef LoadInterstitial = Future<void> Function({
  required String adUnitId,
  required AdRequest request,
  required InterstitialAdLoadCallback adLoadCallback,
});

/// [AdsGateway] over AdMob's full-screen formats.
///
/// One ad of each format is kept loaded so the first game over can offer
/// Continue without a wait, and the next is requested as soon as the previous
/// one is consumed.
class AdMobAdsGateway implements AdsGateway {
  new({
    required this._unitIds,
    this._initialize,
    LoadRewarded? loadRewarded,
    LoadInterstitial? loadInterstitial,
  }) : _loadRewarded = loadRewarded ?? RewardedAd.load,
       _loadInterstitial = loadInterstitial ?? InterstitialAd.load;

  final AdUnitIds _unitIds;

  /// Left null rather than defaulted in the initializer list: reading
  /// `MobileAds.instance` fires a channel call from its own lazy static, so
  /// merely constructing this would reach the platform.
  final Future<void> Function()? _initialize;

  final LoadRewarded _loadRewarded;
  final LoadInterstitial _loadInterstitial;

  /// A failed request is retried immediately, as Google's own sample does.
  /// Without it a single no-fill leaves that format dead for the session:
  /// nothing else asks for a load until an ad has been shown.
  static const _maxLoadAttempts = 3;

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _initialized = false;

  /// Set by [stop] when consent is withdrawn. Every request path reads it,
  /// including after its own await, because a load in flight when the player
  /// withdraws would otherwise deliver into an emptied slot.
  bool _blocked = false;

  bool _rewardedPending = false;
  bool _interstitialPending = false;

  @override
  bool get rewardedReady => _rewarded != null;

  @override
  bool get interstitialReady => _interstitial != null;

  @override
  Future<void> start() async {
    _blocked = false;
    if (!_initialized) {
      try {
        await (_initialize ?? MobileAds.instance.initialize)();
      } on Exception {
        // Contract: never throws, and an SDK that will not initialize has
        // nothing to load from either.
        return;
      }
      _initialized = true;
    }
    // Idempotent through the load guards, so re-running this after consent is
    // granted again resumes without stacking a second ad into either slot.
    await Future.wait([_loadRewardedAd(), _loadInterstitialAd()]);
  }

  @override
  Future<void> stop() async {
    _blocked = true;
    _rewarded?.dispose().ignore();
    _rewarded = null;
    _interstitial?.dispose().ignore();
    _interstitial = null;
  }

  @override
  Future<RewardedOutcome> showRewarded() async {
    final ad = _rewarded;
    // Consumed the moment it is taken: AdMob rejects a second show of the
    // same ad, and the reload below has to find the slot empty.
    _rewarded = null;
    if (ad == null) return RewardedOutcome.failed;

    final shown = Completer<RewardedOutcome>();
    var earned = false;
    // Guarded because the platform may report an outcome more than once, and
    // completing twice would crash the app rather than lose an ad. Disposal
    // lives here so every exit path frees the ad exactly once.
    void finish(RewardedOutcome outcome) {
      if (shown.isCompleted) return;
      ad.dispose().ignore();
      shown.complete(outcome);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      // The reward always lands before the dismissal, which is what turns it
      // into an outcome.
      onAdDismissedFullScreenContent: (_) => finish(earned ? RewardedOutcome.earned : RewardedOutcome.dismissed),
      onAdFailedToShowFullScreenContent: (_, _) => finish(RewardedOutcome.failed),
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } on Exception {
      finish(RewardedOutcome.failed);
    }
    // Reloaded here rather than after the outcome lands: the slot is already
    // empty, and a platform that never calls back would otherwise leave the
    // format dead for the rest of the session.
    unawaited(_loadRewardedAd());
    // ponytail: no wall-clock bound on the outcome. A rewarded end card has
    // no upper duration — the player leaves it open as long as they like —
    // so any bound short enough to unblock the UI promptly would fire while
    // an ad is still on screen and dispose it out from under them. A
    // platform that answers neither callback therefore leaves this pending;
    // Home still finalizes the run. Revisit only with a lifecycle signal,
    // never with a timer.
    return await shown.future;
  }

  @override
  Future<void> showInterstitial() async {
    final ad = _interstitial;
    _interstitial = null;
    if (ad == null) return;

    final displayed = Completer<bool>();
    void finish({required bool ok}) {
      if (displayed.isCompleted) return;
      ad.dispose().ignore();
      displayed.complete(ok);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(ok: true),
      onAdFailedToShowFullScreenContent: (_, _) => finish(ok: false),
    );
    try {
      await ad.show();
    } on Exception {
      finish(ok: false);
    }
    unawaited(_loadInterstitialAd());
    // Unbounded for the reason given in [showRewarded]. Every state spec §Ads
    // enumerates — load failure, no-fill, dismissal, offline — resolves
    // through the callbacks above and leaves Retry alone; only a platform
    // that answers neither one holds the results screen on Home.
    //
    // The caller treats a throw as "not shown" and neither records the
    // impression nor stamps the cadence clock — which is what an ad the
    // player never saw has to do.
    if (!await displayed.future) throw Exception('interstitial failed to show');
  }

  Future<void> _loadRewardedAd([int attempt = 1]) async {
    // The pending flag is as load-bearing as the slot: the request outlives
    // this call and only lands in its callback, so guarding on the slot alone
    // lets a second start() — reopening Privacy options mid-preload does one
    // — put a duplicate in flight, whose arrival overwrites the first ad
    // without freeing it.
    if (_blocked || _rewarded != null || _rewardedPending) return;
    _rewardedPending = true;
    try {
      await _loadRewarded(
        adUnitId: _unitIds.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedPending = false;
            if (_blocked) {
              ad.dispose().ignore();
              return;
            }
            _rewarded = ad;
          },
          onAdFailedToLoad: (_) {
            _rewardedPending = false;
            if (attempt < _maxLoadAttempts) {
              unawaited(_loadRewardedAd(attempt + 1));
            }
          },
        ),
      );
    } on Exception {
      // A request that cannot even be dispatched leaves the format
      // unavailable; it never takes the app down with it.
      _rewardedPending = false;
    }
  }

  Future<void> _loadInterstitialAd([int attempt = 1]) async {
    if (_blocked || _interstitial != null || _interstitialPending) return;
    _interstitialPending = true;
    try {
      await _loadInterstitial(
        adUnitId: _unitIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialPending = false;
            if (_blocked) {
              ad.dispose().ignore();
              return;
            }
            _interstitial = ad;
          },
          onAdFailedToLoad: (_) {
            _interstitialPending = false;
            if (attempt < _maxLoadAttempts) {
              unawaited(_loadInterstitialAd(attempt + 1));
            }
          },
        ),
      );
    } on Exception {
      // As above: a request that cannot be dispatched costs an ad, not a run.
      _interstitialPending = false;
    }
  }
}
