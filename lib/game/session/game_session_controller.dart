// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/game/session/ads_gateway.dart';
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/entitlement_repository.dart';
import 'package:bubble_shooter/game/session/game_session_state.dart';
import 'package:bubble_shooter/game/session/session_config.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';

/// Owns the session state machine of spec §4:
/// playing → gameOver → continueOffer → rewardedShowing → reviving → playing
/// gameOver → results → interstitialShowing → results
class GameSessionController extends Cubit<GameSessionState> {
  new({
    required this._ads,
    required this._entitlements,
    required this._analytics,
    required this._settings,
    this._config = const SessionConfig(),
    this._now = DateTime.now,
  }) : super(
         GameSessionState(
           highScore: _settings.highScore,
           tutorialSeen: _settings.tutorialSeen,
         ),
       );

  final AdsGateway _ads;
  final EntitlementRepository _entitlements;
  final AnalyticsSink _analytics;
  final SettingsRepository _settings;
  final SessionConfig _config;
  final DateTime Function() _now;

  /// Null until [attach], and again after [detach]. A reward that lands while
  /// nothing is attached must not reach a disposed game, so the missing
  /// callback reads as "revive refused" rather than as a crash.
  bool Function()? _revive;

  /// Reads the attached game's live score, which the controller cannot
  /// otherwise know: [GameOverStats] only exists once a run has ended, and a
  /// run walked away from mid-play never produces one. Null between bindings
  /// for the same reason [_revive] is.
  int Function()? _score;

  /// Identifies the current binding, so a page disposed after its successor
  /// has already attached cannot release the live one.
  Object? _binding;

  StreamSubscription<GameEvent>? _subscription;

  /// Stamped with the paired `tutorial_begin`, and doubles as the in-session
  /// "already begun" latch: `tutorialSeen` only flips on the first shot, so a
  /// restart before that shot would re-fire `tutorial_begin` were this not
  /// already set. `runStartedAt` cannot serve here: that restart resets it
  /// while the tutorial it was measuring is still running, understating the
  /// interval. The across-launch latch is `SettingsRepository.tutorialBegun`;
  /// this field is not it, because the elapsed time it holds is only
  /// meaningful within the launch that stamped it.
  DateTime? _tutorialBegunAt;

  /// The run whose `run_abandon` has already been sent, so leaving the
  /// foreground twice in one run reports one abandonment rather than two.
  ///
  /// Keyed on [GameSessionState.runNumber] rather than a boolean: the
  /// controller is app-scoped and every started run gets a new number, so
  /// this is what tells "the run that already reported" from "a later run
  /// standing where it stood" — the same reason [_stillOwns] exists.
  ///
  /// Starts at 0, which is also the run number a session carries before its
  /// first run. `playing` is the initial phase, so a page torn down or
  /// handed over before any `RunStarted` would otherwise report abandoning
  /// a run that never began.
  int _abandonedRun = 0;

  /// Binds one game instance to the session: its domain events route into the
  /// state machine, and its revive is what a granted reward calls.
  ///
  /// The session outlives the game page (AND-117), so this replaces whatever
  /// was attached before — cancelling first, because a second listen on a
  /// live subscription runs every handler twice.
  /// Returns the token that identifies this binding; hand it back to
  /// [detach] so a page can only release the game it lent.
  Object attach({
    required Stream<GameEvent> events,
    required bool Function() revive,
    required int Function() score,
  }) {
    // Taking over from a page that has not been disposed yet — Home tapped
    // from a pending offer and Start pressed again while the replacement
    // animates. Its own teardown will correctly no-op once this binding
    // supersedes it, so its unanswered loss has to be settled here or it
    // loses its run_end, its high score, and its place in the cadence.
    if (_binding != null) abandonRun();
    unawaited(_subscription?.cancel());
    _revive = revive;
    _score = score;
    _binding = Object();
    _subscription = events.listen((event) {
      switch (event) {
        case RunStarted():
          onRunStarted();
        case GameOverReached(:final stats):
          onGameOver(stats);
        case ShotFired():
          onShotFired();
      }
    });
    return _binding!;
  }

  /// Settles a run the page is walking away from and releases its binding,
  /// without ending the session — the cadence carries into the next entry.
  ///
  /// A no-op when [token] is no longer the current binding. `pushReplacement`
  /// builds the incoming page before disposing the outgoing one, so an
  /// unguarded teardown would let a stale page cancel the live game's
  /// subscription, drop its revive, and settle a run that is not its own.
  Future<void> detach(Object token) async {
    if (!identical(_binding, token)) return;
    // Every way out of the game reaches here, so an unanswered loss is
    // settled once rather than at each exit.
    abandonRun();
    // Released before the await, never after: cancelling is asynchronous, so
    // a new game can attach in between, and clearing the fields on the far
    // side would drop the binding it just made — refusing its rewarded
    // Continue and leaving its subscription with nothing to cancel it.
    final subscription = _subscription;
    _binding = null;
    _subscription = null;
    _revive = null;
    _score = null;
    await subscription?.cancel();
  }

  /// Whether a continuation that left during run [run], expecting to come
  /// back to [phase], is still the one the session is waiting on.
  ///
  /// An ad callback outlives the run that asked for it: the controller is
  /// app-scoped, Home stays enabled while an ad is up, and the SDK callback
  /// has no time bound. The phase alone cannot tell "mine" from "a newer run
  /// standing at the same point" — [GameSessionState.runNumber] is monotonic
  /// per started run, so it is what separates them.
  ///
  /// This is what [isClosed] used to carry, back when the controller died
  /// with the page that made it.
  bool _stillOwns(int run, SessionPhase phase) => !isClosed && state.runNumber == run && state.phase == phase;

  void onRunStarted() {
    final runNumber = state.runNumber + 1;
    _analytics.track('run_start', {'run_number': runNumber});
    emit(
      state.copyWith(
        phase: SessionPhase.playing,
        runNumber: runNumber,
        continueUsedOrAttempted: false,
        runStartedAt: _now(),
      ),
    );
    if (!state.tutorialSeen && _tutorialBegunAt == null && !_settings.tutorialBegun) {
      _tutorialBegunAt = _now();
      unawaited(_settings.markTutorialBegun());
      _analytics.track('tutorial_begin');
    }
  }

  /// Completes the first-run tutorial on the first launched shot (spec §7).
  /// Later shots are ignored.
  void onShotFired() {
    if (state.tutorialSeen) return;
    final startedAt = _tutorialBegunAt;
    _analytics.track('tutorial_complete', {
      'time_to_first_shot_ms': startedAt == null ? 0 : _now().difference(startedAt).inMilliseconds,
    });
    unawaited(_settings.markTutorialSeen());
    emit(state.copyWith(tutorialSeen: true));
  }

  void onGameOver(GameOverStats stats) {
    final canOffer = stats.reason == GameOverReason.defeat && !stats.continued && _ads.rewardedReady;
    if (!canOffer) {
      unawaited(_finalizeRun(stats));
      return;
    }
    _analytics.track('continue_offer_shown', {
      'score': stats.score,
      'ad_ready': true,
    });
    emit(
      state.copyWith(phase: SessionPhase.continueOffer, lastGameOver: stats),
    );
  }

  Future<void> requestContinue() async {
    if (state.phase != SessionPhase.continueOffer) return;
    final stats = state.lastGameOver!;
    final run = state.runNumber;
    emit(
      state.copyWith(
        phase: SessionPhase.rewardedShowing,
        continueUsedOrAttempted: true,
      ),
    );
    _analytics.track('continue_ad_started');
    RewardedOutcome outcome;
    try {
      outcome = await _ads.showRewarded();
    } on Exception {
      // An SDK/offline throw must never wedge the session in
      // rewardedShowing — route it through the normal failure path.
      outcome = RewardedOutcome.failed;
    }
    // Abandoning the run finalizes it while this future is still pending, and
    // the player can leave and lose again before the ad ever answers — so a
    // late reward could otherwise revive an already-finalized run, or hand a
    // newer one a continue it never earned.
    if (!_stillOwns(run, SessionPhase.rewardedShowing)) return;
    final revived = outcome == RewardedOutcome.earned && (_revive?.call() ?? false);
    if (revived) {
      _analytics.track('continue_reward_granted', {
        'score_before_revive': stats.score,
      });
      // The continue cycle ends here; the revived run's own game over is
      // a fresh cycle and stays interstitial-eligible.
      emit(
        state.copyWith(
          phase: SessionPhase.playing,
          continueUsedOrAttempted: false,
        ),
      );
      return;
    }
    _analytics.track('continue_failed', {
      'reason': outcome == RewardedOutcome.earned ? 'revive_rejected' : outcome.name,
    });
    await _finalizeRun(stats);
  }

  void declineContinue() {
    if (state.phase != SessionPhase.continueOffer) return;
    unawaited(_finalizeRun(state.lastGameOver!));
  }

  /// Finalizes a run the player walks away from, so an unanswered loss does
  /// not lose its `run_end`, its high score, and its place in the interstitial
  /// cadence.
  ///
  /// Called from [detach], and from [attach] when a new page takes the
  /// session over before the outgoing one is disposed. This controller is
  /// app-scoped and outlives both, which is why the ad continuations guard on
  /// [_stillOwns] rather than on `isClosed`.
  void abandonRun() {
    if (state.phase == SessionPhase.playing) {
      preserveRecord();
      return;
    }
    if (state.phase != SessionPhase.continueOffer && state.phase != SessionPhase.rewardedShowing) {
      return;
    }
    // No interstitial: the player is already leaving, so one would open
    // over whatever replaced the game. Spec §4 only places interstitials
    // at the natural results stop.
    unawaited(_finalizeRun(state.lastGameOver!, allowInterstitial: false));
  }

  /// Reports a live run leaving the screen, and stores its score as the
  /// record without ending the run.
  ///
  /// The HUD shows `max(score, highScore)` as Best throughout a live run, so
  /// a run the player walks away from — before or after a revive — has to
  /// keep what it already displayed, or the record they saw is gone at the
  /// next launch. Nothing else is settled: the run never ended, so its
  /// `run_end` and its place in the cadence are not this method's to record.
  ///
  /// `run_abandon` says only that a playing run left the screen, once per
  /// run. A player who backgrounds the app and comes back to lose sends it
  /// and the later `run_end` both, which is how the funnel separates a
  /// resumed run from a walked-away one.
  ///
  /// Guarded on `playing` because the caller that leaves the app fires for
  /// an ad too: showing a rewarded or interstitial ad drives the app
  /// inactive, and both emit their phase before awaiting the SDK, so this is
  /// already a no-op by then. Settling the run there instead would refuse a
  /// reward the player went on to earn.
  void preserveRecord() {
    if (state.phase != SessionPhase.playing) return;
    final score = _score?.call() ?? 0;
    final best = _recordBest(score);
    if (best != state.highScore) emit(state.copyWith(highScore: best));
    if (_abandonedRun == state.runNumber) return;
    _abandonedRun = state.runNumber;
    final startedAt = state.runStartedAt;
    _analytics.track('run_abandon', {
      'run_number': state.runNumber,
      'score': score,
      'duration_ms': startedAt == null ? 0 : _now().difference(startedAt).inMilliseconds,
    });
  }

  Future<void> _finalizeRun(
    GameOverStats stats, {
    bool allowInterstitial = true,
  }) async {
    // One finalization per game-over cycle. Abandoning a run while the
    // rewarded ad is still in flight leaves that ad's continuation heading
    // here too, and a second pass would double-count run_end, the
    // finalized-run total, and the interstitial cadence.
    if (state.phase == SessionPhase.results || state.phase == SessionPhase.interstitialShowing) {
      return;
    }
    final completed = state.completedRuns + 1;
    final startedAt = state.runStartedAt;
    _analytics.track('run_end', {
      'score': stats.score,
      'duration_ms': startedAt == null ? 0 : _now().difference(startedAt).inMilliseconds,
      'shot_count': stats.shotCount,
      'max_rows': stats.maxOccupiedRows,
      'continued': stats.continued,
      'reason': stats.reason.name,
    });
    final highScore = _recordBest(stats.score);
    emit(
      state.copyWith(
        phase: SessionPhase.results,
        completedRuns: completed,
        lastGameOver: stats,
        highScore: highScore,
      ),
    );
    if (!allowInterstitial || !_shouldShowInterstitial(completed)) return;
    final run = state.runNumber;
    emit(state.copyWith(phase: SessionPhase.interstitialShowing));
    try {
      await _ads.showInterstitial();
    } on Exception {
      // A failed display must still return the finalized results screen,
      // without recording a show or stamping the interval clock — unless the
      // session moved on, in which case there is nothing to return to.
      if (!_stillOwns(run, SessionPhase.interstitialShowing)) return;
      emit(state.copyWith(phase: SessionPhase.results));
      return;
    }
    if (isClosed) return;
    _analytics.track('interstitial_shown', {'completed_run_count': completed});
    // The ad was shown whatever happened since, so the cadence clock is
    // stamped either way. Only the phase write is withheld: putting a later
    // run into `results` would hide the playing-only controls and make its
    // own finalization return early, costing it run_end, its high score, and
    // its place in the cadence.
    if (!_stillOwns(run, SessionPhase.interstitialShowing)) {
      emit(state.copyWith(lastInterstitialAt: _now()));
      return;
    }
    emit(
      state.copyWith(
        phase: SessionPhase.results,
        lastInterstitialAt: _now(),
      ),
    );
  }

  /// Stores [score] when it beats the stored best and returns whichever is
  /// higher. Writing only on an improvement is what stops a run abandoned
  /// below the record from overwriting it.
  int _recordBest(int score) {
    if (score <= state.highScore) return state.highScore;
    unawaited(_settings.saveHighScore(score));
    return score;
  }

  bool _shouldShowInterstitial(int completedRuns) {
    if (_entitlements.adsRemoved) return false;
    if (state.continueUsedOrAttempted) return false;
    if (!_ads.interstitialReady) return false;
    if (completedRuns < _config.minCompletedRunsBeforeFirstInterstitial) {
      return false;
    }
    if (completedRuns % _config.completedRunsPerInterstitial != 0) return false;
    final last = state.lastInterstitialAt;
    if (last != null && _now().difference(last) < _config.minInterstitialInterval) {
      return false;
    }
    return true;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return await super.close();
  }
}
