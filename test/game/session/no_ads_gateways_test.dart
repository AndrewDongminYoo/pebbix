// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/game/session/session.dart';

class _RecordingAnalyticsSink implements AnalyticsSink {
  final List<String> names = [];

  @override
  void track(String event, [Map<String, Object?> parameters = const {}]) {
    names.add(event);
  }
}

const _defeat = GameOverStats(
  score: 100,
  shotCount: 5,
  maxOccupiedRows: 11,
  ceilingDepth: 2,
  continued: false,
  reason: GameOverReason.defeat,
);

const _victory = GameOverStats(
  score: 300,
  shotCount: 9,
  maxOccupiedRows: 6,
  ceilingDepth: 0,
  continued: false,
  reason: GameOverReason.victory,
);

void main() {
  group(NoAdsGateway, () {
    test('reports neither format ready', () {
      const gateway = NoAdsGateway();

      // These two flags are the whole gate on both ad paths, so everything
      // else in this group is a consequence of them.
      expect(gateway.rewardedReady, isFalse);
      expect(gateway.interstitialReady, isFalse);
    });

    test('start and stop complete without throwing', () async {
      const gateway = NoAdsGateway();

      // Contract of `AdsGateway`: both are fired unawaited from startup, so
      // neither may take the launch down with it.
      await expectLater(gateway.start(), completes);
      await expectLater(gateway.stop(), completes);
    });

    test('a rewarded show that is reached anyway fails rather than grants', () async {
      const gateway = NoAdsGateway();

      // Unreachable through `rewardedReady`, but if the offer were ever
      // shown, the run has to finalize — and `failed` is the path that does.
      await expectLater(gateway.showRewarded(), completion(RewardedOutcome.failed));
    });

    test('an interstitial show throws, so no impression is recorded', () async {
      const gateway = NoAdsGateway();

      // The caller reads a throw as "the player never saw it", which is what
      // leaves `interstitial_shown` unrecorded and the cadence clock
      // unstamped. Returning normally would claim an ad was shown.
      await expectLater(gateway.showInterstitial(), throwsException);
    });
  });

  group(NoConsentGateway, () {
    test('stays fail-closed and never requires a privacy form', () async {
      final gateway = NoConsentGateway();

      expect(gateway.canRequestAds, isFalse);
      expect(gateway.privacyOptionsRequired.value, isFalse);

      // Gathering is what would open the form; there is nothing to gather
      // for a build that requests no ads, and it must still leave the app
      // playable rather than throw.
      await expectLater(gateway.gather(), completes);
      await expectLater(gateway.showPrivacyOptions(), completes);

      expect(gateway.canRequestAds, isFalse);
      expect(gateway.privacyOptionsRequired.value, isFalse);
    });
  });

  // The claim worth proving: a build wired to the no-ads gateway needs no
  // change above the `AdsGateway` interface. Each case is paired with the
  // same controller on `FakeAdsGateway`, which reports both formats ready —
  // without that pair, a passing assertion here would not distinguish "the
  // gateway suppressed it" from "the test never reached the ad path".
  group('a session running on NoAdsGateway', () {
    /// Each controller gets its own sink, or the control's events would land
    /// in the list the negative assertion reads.
    (GameSessionController, _RecordingAnalyticsSink) build(AdsGateway ads) {
      final analytics = _RecordingAnalyticsSink();
      return (
        GameSessionController(
          ads: ads,
          entitlements: FakeEntitlementRepository(),
          analytics: analytics,
          settings: InMemorySettingsRepository(),
          now: () => DateTime(2026, 9, 6, 21),
        ),
        analytics,
      );
    }

    /// Plays [count] runs to a win. `onRunStarted` is not decoration: a
    /// finalized run sits in `results`, and `_finalizeRun` returns early from
    /// there, so without it only the first game over would count.
    Future<void> playRuns(GameSessionController session, int count) async {
      for (var run = 0; run < count; run++) {
        session
          ..onRunStarted()
          ..onGameOver(_victory);
        await pumpEventQueue();
      }
    }

    test('never offers Continue on a defeat', () async {
      final (offered, _) = build(FakeAdsGateway());
      offered
        ..onRunStarted()
        ..onGameOver(_defeat);
      expect(
        offered.state.phase,
        SessionPhase.continueOffer,
        reason: 'the control must reach the offer, or the assertion below proves nothing',
      );

      final (silent, analytics) = build(const NoAdsGateway());
      silent
        ..onRunStarted()
        ..onGameOver(_defeat);
      await pumpEventQueue();

      expect(silent.state.phase, SessionPhase.results);
      expect(analytics.names, isNot(contains('continue_offer_shown')));

      await offered.close();
      await silent.close();
    });

    test('never shows an interstitial once the cadence would allow one', () async {
      // Three completed runs is exactly the first cadence slot: the first
      // interstitial is due at `minCompletedRunsBeforeFirstInterstitial`,
      // and 3 is also a multiple of `completedRunsPerInterstitial`.
      final (shown, shownAnalytics) = build(FakeAdsGateway());
      await playRuns(shown, 3);
      expect(
        shownAnalytics.names,
        contains('interstitial_shown'),
        reason: 'the control must reach the cadence, or the assertion below proves nothing',
      );

      final (silent, analytics) = build(const NoAdsGateway());
      await playRuns(silent, 3);

      expect(silent.state.completedRuns, 3);
      expect(silent.state.phase, SessionPhase.results);
      expect(analytics.names, isNot(contains('interstitial_shown')));

      await shown.close();
      await silent.close();
    });
  });
}
