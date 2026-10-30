// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ad_setup.dart';
import 'package:bubble_shooter/game/session/admob_ads_gateway.dart';
import 'package:bubble_shooter/game/session/ads_gateway.dart';

const AdUnitIds _unitIds = (
  rewarded: 'rewarded-unit',
  interstitial: 'interstitial-unit',
);

/// Both error types have `@protected` constructors, so the only way to hand
/// one to a callback is from a subclass.
class _AdError extends LoadAdError {
  new() : super(3, 'test', 'no fill', null);
}

/// A loaded rewarded ad. The platform drives its outcome through callbacks,
/// so [onShow] is where a test says what the ad does once shown.
class _FakeRewardedAd implements RewardedAd {
  new();

  void Function(_FakeRewardedAd ad)? onShow;
  bool showThrows = false;
  int disposeCount = 0;

  late OnUserEarnedRewardCallback _earn;

  void earnReward() => _earn(this, RewardItem(1, 'continue'));

  void dismiss() => fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);

  void failToShow() => fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
    this,
    _AdError(),
  );

  @override
  FullScreenContentCallback<RewardedAd>? fullScreenContentCallback;

  @override
  Future<void> show({
    required OnUserEarnedRewardCallback onUserEarnedReward,
  }) async {
    _earn = onUserEarnedReward;
    if (showThrows) throw Exception('no activity to show over');
    onShow?.call(this);
  }

  @override
  Future<void> dispose() async => disposeCount++;

  @override
  String get adUnitId => _unitIds.rewarded;

  @override
  ResponseInfo? responseInfo;

  @override
  AdRequest? get request => null;

  @override
  AdManagerAdRequest? get adManagerRequest => null;

  @override
  RewardedAdLoadCallback get rewardedAdLoadCallback => throw UnimplementedError();

  @override
  OnUserEarnedRewardCallback? onUserEarnedRewardCallback;

  @override
  OnPaidEventCallback? onPaidEvent;

  @override
  Future<void> setImmersiveMode(bool immersiveModeEnabled) async {}

  @override
  Future<void> setServerSideOptions(
    ServerSideVerificationOptions options,
  ) async {}
}

class _FakeInterstitialAd implements InterstitialAd {
  new();

  void Function(_FakeInterstitialAd ad)? onShow;
  bool showThrows = false;
  int disposeCount = 0;

  void dismiss() => fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);

  void failToShow() => fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
    this,
    _AdError(),
  );

  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;

  @override
  Future<void> show() async {
    if (showThrows) throw Exception('no activity to show over');
    onShow?.call(this);
  }

  @override
  Future<void> dispose() async => disposeCount++;

  @override
  String get adUnitId => _unitIds.interstitial;

  @override
  ResponseInfo? responseInfo;

  @override
  AdRequest get request => const AdRequest();

  @override
  InterstitialAdLoadCallback get adLoadCallback => throw UnimplementedError();

  @override
  OnPaidEventCallback? onPaidEvent;

  @override
  Future<void> setImmersiveMode(bool immersiveModeEnabled) async {}
}

/// Stands in for `RewardedAd.load` and `InterstitialAd.load`, which are
/// statics on their ad classes.
class _FakeAdLoader {
  new({this.failuresBeforeFill = 0, this.dispatchThrows = false});

  final int failuresBeforeFill;

  /// Makes the request itself fail, as a dead channel would, rather than
  /// coming back through the load callback.
  final bool dispatchThrows;

  final rewardedRequests = <String>[];
  final interstitialRequests = <String>[];
  final rewardedAds = <_FakeRewardedAd>[];
  final interstitialAds = <_FakeInterstitialAd>[];

  Future<void> loadRewarded({
    required String adUnitId,
    required AdRequest request,
    required RewardedAdLoadCallback rewardedAdLoadCallback,
  }) async {
    rewardedRequests.add(adUnitId);
    if (dispatchThrows) throw Exception('channel down');
    if (rewardedRequests.length <= failuresBeforeFill) {
      rewardedAdLoadCallback.onAdFailedToLoad(_AdError());
      return;
    }
    final ad = _FakeRewardedAd();
    rewardedAds.add(ad);
    rewardedAdLoadCallback.onAdLoaded(ad);
  }

  Future<void> loadInterstitial({
    required String adUnitId,
    required AdRequest request,
    required InterstitialAdLoadCallback adLoadCallback,
  }) async {
    interstitialRequests.add(adUnitId);
    if (dispatchThrows) throw Exception('channel down');
    if (interstitialRequests.length <= failuresBeforeFill) {
      adLoadCallback.onAdFailedToLoad(_AdError());
      return;
    }
    final ad = _FakeInterstitialAd();
    interstitialAds.add(ad);
    adLoadCallback.onAdLoaded(ad);
  }
}

void main() {
  late _FakeAdLoader loader;
  var initializeCount = 0;
  var initializeFails = false;

  setUp(() {
    loader = _FakeAdLoader();
    initializeCount = 0;
    initializeFails = false;
  });

  AdMobAdsGateway build([_FakeAdLoader? override]) {
    final ads = override ?? loader;
    return AdMobAdsGateway(
      unitIds: _unitIds,
      initialize: () async {
        initializeCount++;
        if (initializeFails) throw Exception('SDK unavailable');
      },
      loadRewarded: ads.loadRewarded,
      loadInterstitial: ads.loadInterstitial,
    );
  }

  group(AdMobAdsGateway, () {
    test('defaults to the real AdMob surface without touching it', () {
      // Construction alone must reach no platform: the defaults are two
      // static tear-offs, and `MobileAds.instance` is deliberately not among
      // them because reading it fires a channel call.
      final gateway = AdMobAdsGateway(unitIds: _unitIds);

      expect(gateway.rewardedReady, isFalse);
      expect(gateway.interstitialReady, isFalse);
    });

    test('start initializes once and preloads both formats', () async {
      final gateway = build();

      await gateway.start();
      await gateway.start();

      expect(initializeCount, 1);
      expect(loader.rewardedRequests, [_unitIds.rewarded]);
      expect(loader.interstitialRequests, [_unitIds.interstitial]);
      expect(gateway.rewardedReady, isTrue);
      expect(gateway.interstitialReady, isTrue);
    });

    test('an SDK that will not initialize costs the ads, not play', () async {
      initializeFails = true;
      final gateway = build();

      // Contract: start never throws — it is fired unawaited from startup.
      await expectLater(gateway.start(), completes);

      expect(loader.rewardedRequests, isEmpty);
      expect(gateway.rewardedReady, isFalse);
    });

    test('a failed request is retried, then left alone', () async {
      final failing = _FakeAdLoader(failuresBeforeFill: 9);
      final gateway = build(failing);

      await gateway.start();
      await pumpEventQueue();

      // Bounded: a dead network must not turn into an endless request loop.
      expect(failing.rewardedRequests, hasLength(3));
      expect(failing.interstitialRequests, hasLength(3));
      expect(gateway.rewardedReady, isFalse);
    });

    test('a retry that fills leaves the format ready', () async {
      final failing = _FakeAdLoader(failuresBeforeFill: 1);
      final gateway = build(failing);

      await gateway.start();
      await pumpEventQueue();

      // Without the retry a single no-fill would leave Continue unofferable
      // for the whole session.
      expect(failing.rewardedRequests, hasLength(2));
      expect(gateway.rewardedReady, isTrue);
      expect(gateway.interstitialReady, isTrue);
    });

    test('a request that cannot be dispatched is swallowed', () async {
      final broken = _FakeAdLoader(dispatchThrows: true);
      final gateway = build(broken);

      await expectLater(gateway.start(), completes);

      expect(gateway.rewardedReady, isFalse);
      expect(gateway.interstitialReady, isFalse);
    });

    test('a second start during a pending load requests nothing', () async {
      final callbacks = <RewardedAdLoadCallback>[];
      final gateway = AdMobAdsGateway(
        unitIds: _unitIds,
        initialize: () async {},
        loadRewarded: ({
          required adUnitId,
          required request,
          required rewardedAdLoadCallback,
        }) async => callbacks.add(rewardedAdLoadCallback),
        loadInterstitial: loader.loadInterstitial,
      );

      // Reopening Privacy options mid-preload does exactly this.
      await gateway.start();
      await gateway.start();
      await pumpEventQueue();

      // The request outlives the call and only lands in its callback, so a
      // slot-only guard would have put a duplicate in flight — whose arrival
      // overwrites the first ad without ever freeing it.
      expect(callbacks, hasLength(1));

      final first = _FakeRewardedAd();
      callbacks.single.onAdLoaded(first);
      expect(gateway.rewardedReady, isTrue);
    });

    test('stop frees both formats and requests nothing more', () async {
      final gateway = build();
      await gateway.start();
      final rewarded = loader.rewardedAds.single;
      final interstitial = loader.interstitialAds.single;

      await gateway.stop();
      await pumpEventQueue();

      // Consent was withdrawn: an ad already paid for is not a reason to
      // show one more (spec §Privacy).
      expect(rewarded.disposeCount, 1);
      expect(interstitial.disposeCount, 1);
      expect(gateway.rewardedReady, isFalse);
      expect(gateway.interstitialReady, isFalse);
      expect(await gateway.showRewarded(), RewardedOutcome.failed);
      expect(loader.rewardedRequests, hasLength(1));
    });

    test('an ad still in flight when stop lands is discarded', () async {
      late RewardedAdLoadCallback onRewarded;
      late InterstitialAdLoadCallback onInterstitial;
      final gateway = AdMobAdsGateway(
        unitIds: _unitIds,
        initialize: () async {},
        loadRewarded: ({
          required adUnitId,
          required request,
          required rewardedAdLoadCallback,
        }) async => onRewarded = rewardedAdLoadCallback,
        loadInterstitial: ({
          required adUnitId,
          required request,
          required adLoadCallback,
        }) async => onInterstitial = adLoadCallback,
      );
      await gateway.start();

      await gateway.stop();
      final rewarded = _FakeRewardedAd();
      final interstitial = _FakeInterstitialAd();
      onRewarded.onAdLoaded(rewarded);
      onInterstitial.onAdLoaded(interstitial);

      // The guard has to be re-read after the await, not only before it —
      // both formats have their own in-flight request to land.
      expect(rewarded.disposeCount, 1);
      expect(interstitial.disposeCount, 1);
      expect(gateway.rewardedReady, isFalse);
      expect(gateway.interstitialReady, isFalse);
    });

    test('start after stop resumes without stacking a second ad', () async {
      final gateway = build();
      await gateway.start();
      await gateway.stop();

      await gateway.start();
      await gateway.start();

      // Initialization stays once per launch; the slots refill exactly once.
      expect(initializeCount, 1);
      expect(loader.rewardedRequests, hasLength(2));
      expect(gateway.rewardedReady, isTrue);
      expect(gateway.interstitialReady, isTrue);
    });

    group('showRewarded', () {
      test('reports failed when nothing is loaded', () async {
        expect(await build().showRewarded(), RewardedOutcome.failed);
      });

      test('reports the reward, frees the ad and reloads', () async {
        final gateway = build();
        await gateway.start();
        final ad = loader.rewardedAds.single
          ..onShow = (ad) => ad
            ..earnReward()
            ..dismiss();

        expect(await gateway.showRewarded(), RewardedOutcome.earned);

        expect(ad.disposeCount, 1);
        await pumpEventQueue();
        // The next game over needs its own ad, and the shown one can never
        // be shown again.
        expect(loader.rewardedRequests, hasLength(2));
        expect(gateway.rewardedReady, isTrue);
      });

      test('a dismissal without a reward is not a continue', () async {
        final gateway = build();
        await gateway.start();
        loader.rewardedAds.single.onShow = (ad) => ad.dismiss();

        expect(await gateway.showRewarded(), RewardedOutcome.dismissed);
      });

      test('an ad that fails to show reports failed and reloads', () async {
        final gateway = build();
        await gateway.start();
        final ad = loader.rewardedAds.single..onShow = (ad) => ad.failToShow();

        expect(await gateway.showRewarded(), RewardedOutcome.failed);

        expect(ad.disposeCount, 1);
        await pumpEventQueue();
        // A failed show that skipped the reload would leave the format dead.
        expect(loader.rewardedRequests, hasLength(2));
      });

      test('a platform that never answers still reloads', () async {
        final gateway = build();
        await gateway.start();
        // The ad goes up and neither callback ever arrives.
        unawaited(gateway.showRewarded());
        await pumpEventQueue();

        // Waiting on the outcome to reload would cost every later run its
        // Continue offer, not just this one.
        expect(loader.rewardedRequests, hasLength(2));
        expect(gateway.rewardedReady, isTrue);
      });

      test('a show that throws reports failed', () async {
        final gateway = build();
        await gateway.start();
        loader.rewardedAds.single.showThrows = true;

        expect(await gateway.showRewarded(), RewardedOutcome.failed);
      });

      test('a platform that reports twice does not crash the app', () async {
        final gateway = build();
        await gateway.start();
        final ad = loader.rewardedAds.single
          ..onShow = (ad) => ad
            ..earnReward()
            ..dismiss()
            ..dismiss();

        // Completing a completer twice throws, and disposing twice would
        // reach a freed native ad.
        await expectLater(gateway.showRewarded(), completes);
        expect(ad.disposeCount, 1);
      });

      test('the same ad is never offered twice', () async {
        final gateway = build();
        await gateway.start();
        late bool readyWhileShowing;
        loader.rewardedAds.single.onShow = (ad) {
          readyWhileShowing = gateway.rewardedReady;
          ad.dismiss();
        };

        await gateway.showRewarded();

        // Consumed the moment it is taken: AdMob rejects a second show of
        // the same ad, so it must not still look available while it is up.
        expect(readyWhileShowing, isFalse);
      });
    });

    group('showInterstitial', () {
      test('does nothing when none is loaded', () async {
        await expectLater(build().showInterstitial(), completes);
      });

      test('frees the ad and reloads after a show', () async {
        final gateway = build();
        await gateway.start();
        final ad = loader.interstitialAds.single..onShow = (ad) => ad.dismiss();

        await gateway.showInterstitial();

        expect(ad.disposeCount, 1);
        await pumpEventQueue();
        expect(loader.interstitialRequests, hasLength(2));
        expect(gateway.interstitialReady, isTrue);
      });

      test('throws when the ad never reached the player', () async {
        final gateway = build();
        await gateway.start();
        loader.interstitialAds.single.onShow = (ad) => ad.failToShow();

        // The session controller reads a throw as "not shown" and neither
        // records the impression nor stamps the cadence clock.
        await expectLater(gateway.showInterstitial(), throwsException);

        await pumpEventQueue();
        expect(loader.interstitialRequests, hasLength(2));
      });

      test('a show that throws is reported as not shown', () async {
        final gateway = build();
        await gateway.start();
        loader.interstitialAds.single.showThrows = true;

        await expectLater(gateway.showInterstitial(), throwsException);
      });

      test('a platform that reports twice does not crash the app', () async {
        final gateway = build();
        await gateway.start();
        final ad = loader.interstitialAds.single
          ..onShow = (ad) => ad
            ..dismiss()
            ..dismiss();

        await expectLater(gateway.showInterstitial(), completes);
        expect(ad.disposeCount, 1);
      });
    });
  });
}
