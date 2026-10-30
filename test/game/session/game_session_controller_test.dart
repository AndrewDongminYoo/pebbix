// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/game/session/session.dart';

/// Simulates an ad SDK that throws instead of returning an outcome.
class ThrowingAdsGateway extends FakeAdsGateway {
  @override
  Future<RewardedOutcome> showRewarded() async => throw Exception('sdk');

  @override
  Future<void> showInterstitial() async => throw Exception('sdk');
}

/// Hands out a fresh pending future per show, so a test can resolve an
/// earlier ad while a later one is still on screen — which is what an ad
/// callback outliving the run that asked for it looks like.
class QueuedAds extends FakeAdsGateway {
  final rewarded = <Completer<RewardedOutcome>>[];
  final interstitials = <Completer<void>>[];

  @override
  Future<RewardedOutcome> showRewarded() {
    final completer = Completer<RewardedOutcome>();
    rewarded.add(completer);
    return completer.future;
  }

  @override
  Future<void> showInterstitial() {
    final completer = Completer<void>();
    interstitials.add(completer);
    return completer.future;
  }
}

class RecordingAnalyticsSink implements AnalyticsSink {
  final List<(String, Map<String, Object?>)> events = [];

  @override
  void track(String event, [Map<String, Object?> parameters = const {}]) {
    events.add((event, parameters));
  }

  Iterable<String> get names => events.map((e) => e.$1);
}

/// Counts high-score writes so the "only on an improvement" guard is
/// observable — a redundant save stores the same value and would otherwise
/// be invisible to an assertion on the stored score.
class CountingSettingsRepository extends InMemorySettingsRepository {
  new({super.highScore, super.tutorialSeen, super.tutorialBegun});

  int saveHighScoreCalls = 0;

  @override
  Future<void> saveHighScore(int score) {
    saveHighScoreCalls++;
    return super.saveHighScore(score);
  }
}

const defeatStats = GameOverStats(
  score: 100,
  shotCount: 5,
  maxOccupiedRows: 11,
  ceilingDepth: 2,
  continued: false,
  reason: GameOverReason.defeat,
);

const victoryStats = GameOverStats(
  score: 300,
  shotCount: 9,
  maxOccupiedRows: 6,
  ceilingDepth: 0,
  continued: false,
  reason: GameOverReason.victory,
);

void main() {
  late FakeAdsGateway ads;
  late FakeEntitlementRepository entitlements;
  late RecordingAnalyticsSink analytics;
  late CountingSettingsRepository settings;
  late bool reviveResult;
  late int reviveCalls;
  late DateTime currentTime;
  late int liveScore;
  late StreamController<GameEvent> gameEvents;

  setUp(() {
    ads = FakeAdsGateway();
    entitlements = FakeEntitlementRepository();
    analytics = RecordingAnalyticsSink();
    settings = CountingSettingsRepository();
    reviveResult = true;
    reviveCalls = 0;
    currentTime = DateTime(2026, 8, 7, 21);
    liveScore = 0;
    gameEvents = StreamController<GameEvent>.broadcast();
  });

  tearDown(() => gameEvents.close());

  /// Attached at construction the way [GameView] does it, so every test below
  /// runs against a controller that is bound to a game.
  GameSessionController build() =>
      GameSessionController(
        ads: ads,
        entitlements: entitlements,
        analytics: analytics,
        settings: settings,
        now: () => currentTime,
      )..attach(
        events: gameEvents.stream,
        revive: () {
          reviveCalls++;
          return reviveResult;
        },
        score: () => liveScore,
      );

  blocTest<GameSessionController, GameSessionState>(
    'onRunStarted resets the continue flag and tracks run_start',
    build: build,
    seed: () => const GameSessionState(
      phase: SessionPhase.results,
      runNumber: 2,
      completedRuns: 2,
      continueUsedOrAttempted: true,
    ),
    act: (cubit) => cubit.onRunStarted(),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.playing);
      expect(cubit.state.runNumber, 3);
      expect(cubit.state.continueUsedOrAttempted, isFalse);
      expect(cubit.state.runStartedAt, DateTime(2026, 8, 7, 21));
      final (name, params) = analytics.events.first;
      expect(name, 'run_start');
      expect(params, {'run_number': 3});
      expect(analytics.names, ['run_start', 'tutorial_begin']);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'started runs are numbered monotonically, not by completed runs',
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..onRunStarted(),
    verify: (cubit) {
      // An abandoned attempt — a pause-restart, say — never finalizes, so
      // numbering from completedRuns would issue the same run_number twice
      // with no run_end between them.
      expect(cubit.state.runNumber, 2);
      expect(cubit.state.completedRuns, 0);
      expect(
        analytics.events.where((event) => event.$1 == 'run_start').map((event) => event.$2['run_number']),
        [1, 2],
      );
    },
  );

  test('state seeds high score and tutorial status from settings', () async {
    settings = CountingSettingsRepository(
      highScore: 480,
      tutorialSeen: true,
    );
    final cubit = build();

    expect(cubit.state.highScore, 480);
    expect(cubit.state.tutorialSeen, isTrue);

    await cubit.close();
  });

  blocTest<GameSessionController, GameSessionState>(
    'onRunStarted tracks tutorial_begin at most once per controller',
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..onRunStarted(),
    verify: (cubit) {
      expect(
        analytics.names.where((name) => name == 'tutorial_begin'),
        hasLength(1),
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'onRunStarted skips tutorial_begin when the tutorial was already seen',
    setUp: () => settings = CountingSettingsRepository(tutorialSeen: true),
    build: build,
    act: (cubit) => cubit.onRunStarted(),
    verify: (cubit) {
      expect(analytics.names, isNot(contains('tutorial_begin')));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'onShotFired completes the tutorial with measured first-shot time',
    build: build,
    act: (cubit) {
      cubit.onRunStarted();
      currentTime = currentTime.add(const Duration(milliseconds: 1250));
      cubit.onShotFired();
    },
    verify: (cubit) {
      expect(cubit.state.tutorialSeen, isTrue);
      expect(settings.tutorialSeen, isTrue);
      final (name, params) = analytics.events.last;
      expect(name, 'tutorial_complete');
      expect(params, {'time_to_first_shot_ms': 1250});
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'tutorial timing spans from its own begin, not the latest restart',
    build: build,
    act: (cubit) {
      cubit.onRunStarted();
      currentTime = currentTime.add(const Duration(milliseconds: 4000));
      // A pause-restart before the first shot: tutorial_begin stays
      // latched, so its pair must keep measuring from the original stamp.
      cubit.onRunStarted();
      currentTime = currentTime.add(const Duration(milliseconds: 1500));
      cubit.onShotFired();
    },
    verify: (cubit) {
      expect(
        analytics.names.where((name) => name == 'tutorial_begin'),
        hasLength(1),
      );
      final (name, params) = analytics.events.last;
      expect(name, 'tutorial_complete');
      expect(params, {'time_to_first_shot_ms': 5500});
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a second shot does not complete the tutorial again',
    build: build,
    act: (cubit) => cubit
      ..onShotFired()
      ..onShotFired(),
    verify: (cubit) {
      expect(
        analytics.names.where((name) => name == 'tutorial_complete'),
        hasLength(1),
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a shot before run start reports zero first-shot time',
    build: build,
    act: (cubit) => cubit.onShotFired(),
    verify: (cubit) {
      final event = analytics.events.single;
      expect(event.$1, 'tutorial_complete');
      expect(event.$2, {'time_to_first_shot_ms': 0});
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'defeat with a ready rewarded ad offers Continue',
    build: build,
    act: (cubit) => cubit.onGameOver(defeatStats),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.continueOffer);
      expect(cubit.state.lastGameOver, defeatStats);
      expect(analytics.names, ['continue_offer_shown']);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'defeat without a ready ad finalizes straight to results',
    build: build,
    setUp: () => ads.rewardedReady = false,
    act: (cubit) => cubit.onGameOver(defeatStats),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.results);
      expect(cubit.state.completedRuns, 1);
      expect(analytics.names, ['run_end']);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'victory finalizes with run_end parameters',
    build: build,
    act: (cubit) => cubit.onGameOver(victoryStats),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.results);
      final (name, params) = analytics.events.single;
      expect(name, 'run_end');
      expect(params['score'], 300);
      expect(params['shot_count'], 9);
      expect(params['max_rows'], 6);
      expect(params['continued'], false);
      expect(params['reason'], 'victory');
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a new high score is persisted and emitted at finalization',
    setUp: () => settings = CountingSettingsRepository(highScore: 200),
    build: build,
    act: (cubit) => cubit.onGameOver(victoryStats),
    verify: (cubit) {
      expect(settings.highScore, 300);
      expect(settings.saveHighScoreCalls, 1);
      expect(cubit.state.highScore, 300);
    },
  );

  for (final existingHighScore in [300, 400]) {
    blocTest<GameSessionController, GameSessionState>(
      'a $existingHighScore high score is not overwritten by a 300 run',
      setUp: () => settings = CountingSettingsRepository(
        highScore: existingHighScore,
      ),
      build: build,
      act: (cubit) => cubit.onGameOver(victoryStats),
      verify: (cubit) {
        expect(settings.highScore, existingHighScore);
        expect(settings.saveHighScoreCalls, 0);
        expect(cubit.state.highScore, existingHighScore);
      },
    );
  }

  blocTest<GameSessionController, GameSessionState>(
    'abandonRun finalizes a loss left on the continue offer',
    setUp: () => settings = CountingSettingsRepository(highScore: 10),
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..onGameOver(defeatStats)
      ..abandonRun(),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.results);
      expect(cubit.state.completedRuns, 1);
      expect(settings.highScore, 100);
      expect(analytics.names, contains('run_end'));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'abandonRun finalizes a loss whose rewarded ad is still in flight',
    setUp: () {
      settings = CountingSettingsRepository();
      ads.rewardedOutcome = RewardedOutcome.dismissed;
    },
    build: build,
    act: (cubit) async {
      cubit
        ..onRunStarted()
        ..onGameOver(defeatStats);
      final pending = cubit.requestContinue();
      cubit.abandonRun();
      await pending;
    },
    verify: (cubit) {
      // The ad's own continuation lands here too; finalization is once per
      // game-over cycle, so the second arrival must change nothing.
      expect(cubit.state.completedRuns, 1);
      expect(
        analytics.names.where((name) => name == 'run_end'),
        hasLength(1),
      );
      expect(settings.saveHighScoreCalls, 1);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a reward landing after abandonment neither revives nor re-finalizes',
    setUp: () => settings = CountingSettingsRepository(),
    build: build,
    act: (cubit) async {
      cubit
        ..onRunStarted()
        ..onGameOver(defeatStats);
      final pending = cubit.requestContinue();
      cubit.abandonRun();
      await pending;
    },
    verify: (cubit) {
      // Route teardown does not close the controller until the transition
      // ends, so the late earned reward arrives on a live but finalized
      // controller and must not hand it back to playing.
      expect(reviveCalls, 0);
      expect(cubit.state.phase, SessionPhase.results);
      expect(analytics.names, isNot(contains('continue_reward_granted')));
      expect(
        analytics.names.where((name) => name == 'run_end'),
        hasLength(1),
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'an abandoned run never opens an interstitial',
    seed: () => const GameSessionState(completedRuns: 2),
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..onGameOver(defeatStats)
      ..abandonRun(),
    verify: (cubit) {
      // Cadence-eligible, but the player is already leaving: an
      // interstitial would open over whatever replaced the game.
      expect(cubit.state.completedRuns, 3);
      expect(ads.interstitialShownCount, 0);
      expect(analytics.names, isNot(contains('interstitial_shown')));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'abandonRun keeps a high score reached mid-play',
    setUp: () {
      settings = CountingSettingsRepository(highScore: 120);
      liveScore = 250;
    },
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..abandonRun(),
    verify: (cubit) {
      // The results HUD shows max(score, highScore) as Best, so a run
      // walked away from mid-play has to store what it already displayed.
      expect(settings.highScore, 250);
      expect(cubit.state.highScore, 250);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'abandonRun keeps a high score reached after a revive',
    setUp: () {
      settings = CountingSettingsRepository(highScore: 120);
      ads.rewardedOutcome = RewardedOutcome.earned;
    },
    build: build,
    act: (cubit) async {
      cubit
        ..onRunStarted()
        ..onGameOver(defeatStats);
      await cubit.requestContinue();
      liveScore = 400;
      cubit.abandonRun();
    },
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.playing);
      expect(settings.highScore, 400);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a second mid-play abandon measures against the record just set',
    setUp: () {
      settings = CountingSettingsRepository(highScore: 120);
      liveScore = 980;
    },
    build: build,
    act: (cubit) {
      cubit
        ..onRunStarted()
        ..abandonRun();
      // The controller is app-scoped (AND-117), so the next run measures
      // against the record this one just set rather than against the value
      // read at construction.
      liveScore = 500;
      cubit
        ..onRunStarted()
        ..abandonRun();
    },
    verify: (cubit) {
      expect(settings.highScore, 980);
      expect(settings.saveHighScoreCalls, 1);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'abandoning mid-play below the record leaves it alone',
    setUp: () {
      settings = CountingSettingsRepository(highScore: 500);
      liveScore = 90;
    },
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..abandonRun(),
    verify: (cubit) {
      expect(settings.highScore, 500);
      expect(settings.saveHighScoreCalls, 0);
    },
  );

  test('preserveRecord while a rewarded ad is up cannot settle the run', () async {
    final queued = QueuedAds();
    ads = queued;
    settings = CountingSettingsRepository(highScore: 120);
    liveScore = 980;
    final controller = build()
      ..onRunStarted()
      ..onGameOver(defeatStats);
    final pending = controller.requestContinue();
    expect(controller.state.phase, SessionPhase.rewardedShowing);

    // Showing the ad drives the app inactive, which is the same signal a
    // root-level Back sends. Settling here would refuse the reward the
    // player is in the middle of earning.
    controller.preserveRecord();

    queued.rewarded.single.complete(RewardedOutcome.earned);
    await pending;

    expect(reviveCalls, 1);
    expect(controller.state.phase, SessionPhase.playing);
    expect(controller.state.completedRuns, 0);
    expect(settings.saveHighScoreCalls, 0);
  });

  blocTest<GameSessionController, GameSessionState>(
    'abandonRun ends no run during normal play',
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..abandonRun(),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.playing);
      expect(analytics.names, isNot(contains('run_end')));
      // A scoreless run writes nothing, so the assertions above are not
      // carried by the improvement guard alone.
      expect(settings.saveHighScoreCalls, 0);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a mid-play exit reports run_abandon with the live run',
    setUp: () => liveScore = 370,
    build: build,
    act: (cubit) {
      cubit.onRunStarted();
      currentTime = currentTime.add(const Duration(seconds: 42));
      cubit.preserveRecord();
    },
    verify: (_) {
      expect(
        analytics.events.singleWhere((e) => e.$1 == 'run_abandon').$2,
        {'run_number': 1, 'score': 370, 'duration_ms': 42000},
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'leaving the foreground twice in one run reports one abandonment',
    setUp: () => liveScore = 120,
    build: build,
    act: (cubit) {
      // onInactive fires on every trip out of the foreground, and the page's
      // own teardown routes through abandonRun as well, so one run reaches
      // this path more than once.
      cubit
        ..onRunStarted()
        ..preserveRecord()
        ..preserveRecord()
        ..abandonRun();
    },
    verify: (_) {
      expect(analytics.names.where((name) => name == 'run_abandon'), hasLength(1));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'the next run reports its own abandonment',
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..preserveRecord()
      ..onRunStarted()
      ..preserveRecord(),
    verify: (_) {
      expect(
        analytics.events.where((e) => e.$1 == 'run_abandon').map((e) => e.$2['run_number']),
        [1, 2],
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a session that never started a run reports no abandonment',
    build: build,
    // `playing` is the initial phase and no RunStarted has arrived, so the
    // guard here is the run number, not the phase.
    act: (cubit) => cubit
      ..preserveRecord()
      ..abandonRun(),
    verify: (_) => expect(analytics.names, isNot(contains('run_abandon'))),
  );

  blocTest<GameSessionController, GameSessionState>(
    'a resumed run reports both its abandonment and its end',
    build: build,
    act: (cubit) => cubit
      ..onRunStarted()
      ..preserveRecord()
      ..onGameOver(victoryStats),
    verify: (_) {
      // Backgrounding is not leaving for good: the pair is what separates a
      // player who came back to finish from one who walked away.
      expect(analytics.names, containsAllInOrder(['run_abandon', 'run_end']));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'an ad showing over a live run reports no abandonment',
    setUp: () => ads.rewardedOutcome = RewardedOutcome.earned,
    build: build,
    act: (cubit) async {
      cubit
        ..onRunStarted()
        ..onGameOver(defeatStats);
      // Showing an ad drives the app inactive, which is the same signal a
      // root-level Back sends — but the player has not left the run.
      await cubit.requestContinue();
    },
    verify: (_) => expect(analytics.names, isNot(contains('run_abandon'))),
  );

  blocTest<GameSessionController, GameSessionState>(
    'the first run of an install persists that the tutorial began',
    build: build,
    act: (cubit) => cubit.onRunStarted(),
    verify: (_) {
      expect(analytics.names, contains('tutorial_begin'));
      expect(settings.tutorialBegun, isTrue);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a relaunch before the first shot does not repeat tutorial_begin',
    // A store that already carries the flag is what the next launch reads:
    // the in-memory latch dies with the controller, so only this stops the
    // event from firing again on every relaunch before the first shot.
    setUp: () => settings = CountingSettingsRepository(tutorialBegun: true),
    build: build,
    act: (cubit) => cubit.onRunStarted(),
    verify: (_) => expect(analytics.names, isNot(contains('tutorial_begin'))),
  );

  blocTest<GameSessionController, GameSessionState>(
    'an already-continued defeat is never offered Continue again',
    build: build,
    act: (cubit) => cubit.onGameOver(
      const GameOverStats(
        score: 100,
        shotCount: 5,
        maxOccupiedRows: 11,
        ceilingDepth: 2,
        continued: true,
        reason: GameOverReason.defeat,
      ),
    ),
    verify: (cubit) => expect(cubit.state.phase, SessionPhase.results),
  );

  blocTest<GameSessionController, GameSessionState>(
    'earned reward revives and returns to playing',
    build: build,
    act: (cubit) async {
      cubit.onGameOver(defeatStats);
      await cubit.requestContinue();
    },
    verify: (cubit) {
      expect(reviveCalls, 1);
      expect(cubit.state.phase, SessionPhase.playing);
      // The cycle flag resets on revive: the revived run's own game over
      // is a new cycle (interstitial-eligible again).
      expect(cubit.state.continueUsedOrAttempted, isFalse);
      expect(cubit.state.completedRuns, 0); // run NOT finalized
      expect(
        analytics.names,
        [
          'continue_offer_shown',
          'continue_ad_started',
          'continue_reward_granted',
        ],
      );
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a dismissed ad finalizes without reviving',
    build: build,
    setUp: () => ads.rewardedOutcome = RewardedOutcome.dismissed,
    act: (cubit) async {
      cubit.onGameOver(defeatStats);
      await cubit.requestContinue();
    },
    verify: (cubit) {
      expect(reviveCalls, 0);
      expect(cubit.state.phase, SessionPhase.results);
      expect(cubit.state.completedRuns, 1);
      expect(analytics.names, contains('continue_failed'));
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'an earned reward with a rejected revive finalizes',
    build: build,
    setUp: () => reviveResult = false,
    act: (cubit) async {
      cubit.onGameOver(defeatStats);
      await cubit.requestContinue();
    },
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.results);
      final failed = analytics.events.firstWhere(
        (e) => e.$1 == 'continue_failed',
      );
      expect(failed.$2['reason'], 'revive_rejected');
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a throwing rewarded ad finalizes instead of wedging the session',
    build: build,
    setUp: () => ads = ThrowingAdsGateway(),
    act: (cubit) async {
      cubit.onGameOver(defeatStats);
      await cubit.requestContinue();
    },
    verify: (cubit) {
      expect(reviveCalls, 0);
      expect(cubit.state.phase, SessionPhase.results);
      expect(cubit.state.completedRuns, 1);
      final failed = analytics.events.firstWhere(
        (e) => e.$1 == 'continue_failed',
      );
      expect(failed.$2['reason'], 'failed');
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'a successful revive resets the cycle flag for the next game over',
    build: build,
    act: (cubit) async {
      // Two finalized runs, then a continue in run 3: its FINAL game over
      // is a fresh cycle, so the 3rd finalized run still shows the ad.
      for (var i = 0; i < 2; i++) {
        cubit
          ..onRunStarted()
          ..onGameOver(victoryStats);
        await Future<void>.delayed(Duration.zero);
        currentTime = currentTime.add(const Duration(minutes: 5));
      }
      cubit
        ..onRunStarted()
        ..onGameOver(defeatStats);
      await cubit.requestContinue();
      expect(cubit.state.continueUsedOrAttempted, isFalse);
      cubit.onGameOver(
        const GameOverStats(
          score: 150,
          shotCount: 9,
          maxOccupiedRows: 11,
          ceilingDepth: 3,
          continued: true,
          reason: GameOverReason.defeat,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
    verify: (cubit) {
      expect(cubit.state.completedRuns, 3);
      expect(ads.interstitialShownCount, 1);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'declineContinue finalizes the run',
    build: build,
    act: (cubit) => cubit
      ..onGameOver(defeatStats)
      ..declineContinue(),
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.results);
      expect(cubit.state.completedRuns, 1);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'requestContinue and declineContinue are no-ops outside continueOffer',
    build: build,
    act: (cubit) async {
      await cubit.requestContinue();
      cubit.declineContinue();
    },
    verify: (cubit) {
      expect(cubit.state.phase, SessionPhase.playing);
      expect(analytics.events, isEmpty);
    },
  );

  blocTest<GameSessionController, GameSessionState>(
    'run_end includes the measured duration',
    build: build,
    act: (cubit) {
      cubit.onRunStarted();
      currentTime = currentTime.add(const Duration(seconds: 90));
      cubit.onGameOver(victoryStats);
    },
    verify: (cubit) {
      final (_, params) = analytics.events.last;
      expect(params['duration_ms'], 90000);
    },
  );

  group('interstitials', () {
    Future<void> finalizeRuns(GameSessionController cubit, int count) async {
      for (var i = 0; i < count; i++) {
        cubit
          ..onRunStarted()
          ..onGameOver(victoryStats);
        await Future<void>.delayed(Duration.zero);
        currentTime = currentTime.add(const Duration(minutes: 5));
      }
    }

    blocTest<GameSessionController, GameSessionState>(
      'shows on the 3rd finalized run and stamps the time',
      build: build,
      act: (cubit) => finalizeRuns(cubit, 3),
      verify: (cubit) {
        expect(ads.interstitialShownCount, 1);
        expect(cubit.state.lastInterstitialAt, isNotNull);
        expect(analytics.names, contains('interstitial_shown'));
        expect(cubit.state.phase, SessionPhase.results);
      },
    );

    blocTest<GameSessionController, GameSessionState>(
      'exempts the first two runs and off-cadence runs',
      build: build,
      act: (cubit) => finalizeRuns(cubit, 2),
      verify: (cubit) => expect(ads.interstitialShownCount, 0),
    );

    blocTest<GameSessionController, GameSessionState>(
      'respects the minimum interval between interstitials',
      build: build,
      act: (cubit) async {
        // 6 finalized runs at cadence 3 → candidates at 3 and 6, but with
        // no time passing after run 3 the 6th is suppressed.
        for (var i = 0; i < 6; i++) {
          cubit
            ..onRunStarted()
            ..onGameOver(victoryStats);
          await Future<void>.delayed(Duration.zero);
        }
      },
      verify: (cubit) => expect(ads.interstitialShownCount, 1),
    );

    blocTest<GameSessionController, GameSessionState>(
      'never shows for remove_ads purchasers',
      build: build,
      setUp: () => entitlements.adsRemoved = true,
      act: (cubit) => finalizeRuns(cubit, 6),
      verify: (cubit) => expect(ads.interstitialShownCount, 0),
    );

    blocTest<GameSessionController, GameSessionState>(
      'leaves the optional Continue to remove_ads purchasers',
      build: build,
      setUp: () => entitlements.adsRemoved = true,
      act: (cubit) async {
        cubit.onGameOver(defeatStats);
        await cubit.requestContinue();
      },
      verify: (cubit) {
        // Spec §4: the entitlement suppresses the forced interstitial and
        // nothing else. The offer, the reward and the revive all still run,
        // and the purchase UI says so — so the single interstitial check is
        // the only place the entitlement may be read.
        expect(reviveCalls, 1);
        expect(analytics.names, [
          'continue_offer_shown',
          'continue_ad_started',
          'continue_reward_granted',
        ]);
        expect(cubit.state.phase, SessionPhase.playing);
      },
    );

    blocTest<GameSessionController, GameSessionState>(
      'never shows in a cycle where Continue was attempted',
      build: build,
      setUp: () => ads.rewardedOutcome = RewardedOutcome.dismissed,
      act: (cubit) async {
        await finalizeRuns(cubit, 2);
        cubit
          ..onRunStarted()
          ..onGameOver(defeatStats);
        await cubit.requestContinue(); // dismissed → finalizes 3rd run
      },
      verify: (cubit) {
        expect(cubit.state.completedRuns, 3);
        expect(ads.interstitialShownCount, 0);
      },
    );

    blocTest<GameSessionController, GameSessionState>(
      'skips when no interstitial is loaded',
      build: build,
      setUp: () => ads.interstitialReady = false,
      act: (cubit) => finalizeRuns(cubit, 3),
      verify: (cubit) => expect(ads.interstitialShownCount, 0),
    );

    blocTest<GameSessionController, GameSessionState>(
      'a throwing interstitial still restores the results screen',
      build: build,
      setUp: () => ads = ThrowingAdsGateway(),
      act: (cubit) => finalizeRuns(cubit, 3),
      verify: (cubit) {
        expect(cubit.state.phase, SessionPhase.results);
        expect(cubit.state.lastInterstitialAt, isNull);
        expect(analytics.names, isNot(contains('interstitial_shown')));
      },
    );

    blocTest<GameSessionController, GameSessionState>(
      'skips off-cadence runs past the first threshold',
      build: build,
      act: (cubit) => finalizeRuns(cubit, 4),
      // Run 3 is the only candidate; run 4 is off-cadence (4 % 3 != 0).
      verify: (cubit) => expect(ads.interstitialShownCount, 1),
    );
  });

  group('attach', () {
    blocTest<GameSessionController, GameSessionState>(
      'routes game events to the handlers',
      build: build,
      act: (cubit) async {
        final events = StreamController<GameEvent>.broadcast();
        cubit.attach(events: events.stream, revive: () => true, score: () => liveScore);
        events
          ..add(const RunStarted())
          ..add(const ShotFired())
          ..add(const GameOverReached(victoryStats));
        await Future<void>.delayed(Duration.zero);
        await events.close();
      },
      verify: (cubit) {
        expect(cubit.state.completedRuns, 1);
        expect(cubit.state.tutorialSeen, isTrue);
        expect(settings.tutorialSeen, isTrue);
        expect(
          analytics.names,
          containsAllInOrder([
            'run_start',
            'tutorial_begin',
            'tutorial_complete',
            'run_end',
          ]),
        );
      },
    );

    test('close cancels the binding so later events are ignored', () async {
      final cubit = build();
      final events = StreamController<GameEvent>.broadcast();
      cubit.attach(events: events.stream, revive: () => true, score: () => liveScore);
      await cubit.close();
      events.add(const RunStarted());
      await Future<void>.delayed(Duration.zero);
      expect(analytics.events, isEmpty);
      await events.close();
    });

    test('the session survives a game handing over to the next one', () async {
      final controller = build();
      final first = StreamController<GameEvent>.broadcast();
      final binding = controller.attach(
        events: first.stream,
        revive: () => true,
        score: () => liveScore,
      );
      controller
        ..onRunStarted()
        ..onGameOver(
          const GameOverStats(
            score: 100,
            shotCount: 3,
            maxOccupiedRows: 4,
            ceilingDepth: 1,
            continued: true,
            reason: GameOverReason.defeat,
          ),
        );
      await Future<void>.delayed(Duration.zero);
      await controller.detach(binding);
      await first.close();

      // Leaving through Home and starting again is a new game, not a new
      // session: AND-117's whole point is that the cadence outlives the page.
      final second = StreamController<GameEvent>.broadcast();
      controller
        ..attach(events: second.stream, revive: () => true, score: () => liveScore)
        ..onRunStarted();

      expect(controller.state.completedRuns, 1);
      expect(controller.state.runNumber, 2);
      await second.close();
    });

    test('re-attaching does not double-count the next event', () async {
      final controller = build();
      final events = StreamController<GameEvent>.broadcast();
      controller
        ..attach(events: events.stream, revive: () => true, score: () => liveScore)
        ..attach(events: events.stream, revive: () => true, score: () => liveScore);

      events.add(const RunStarted());
      await Future<void>.delayed(Duration.zero);

      // A second listen on a live subscription would run every handler twice,
      // so one entry would report as two runs.
      expect(controller.state.runNumber, 1);
      await events.close();
    });

    test('taking over settles the run the outgoing page left', () async {
      final controller = build()
        ..onRunStarted()
        ..onGameOver(
          const GameOverStats(
            score: 250,
            shotCount: 7,
            maxOccupiedRows: 5,
            ceilingDepth: 1,
            continued: false,
            reason: GameOverReason.defeat,
          ),
        );
      expect(controller.state.phase, SessionPhase.continueOffer);

      final live = StreamController<GameEvent>.broadcast();
      controller.attach(events: live.stream, revive: () => true, score: () => liveScore);
      await Future<void>.delayed(Duration.zero);

      // Settling belongs to whichever of the two happens first. The outgoing
      // page's teardown no-ops once this binding supersedes it, so a loss
      // left on the offer would otherwise never reach run_end at all.
      expect(controller.state.phase, SessionPhase.results);
      expect(controller.state.completedRuns, 1);
      expect(settings.highScore, 250);
      await live.close();
    });

    test('an interstitial finishing after a new run does not end it', () async {
      final queued = QueuedAds();
      ads = queued;
      final controller = build();

      // Home stays enabled while an ad is up, so the player can leave during
      // the interstitial and start again before its callback ever returns.
      for (var run = 0; run < 3; run++) {
        controller
          ..onRunStarted()
          ..onGameOver(victoryStats);
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.state.phase, SessionPhase.interstitialShowing);

      controller.onRunStarted();
      expect(controller.state.phase, SessionPhase.playing);

      queued.interstitials.single.complete();
      await Future<void>.delayed(Duration.zero);

      // The ad was shown, so the cadence clock is stamped — but the new run
      // must not be dragged to results, which would hide the playing-only
      // controls and make its own finalization return early.
      expect(controller.state.lastInterstitialAt, isNotNull);
      expect(controller.state.phase, SessionPhase.playing);

      controller.onGameOver(victoryStats);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.completedRuns, 4);
    });

    test('a stale reward cannot answer a newer offer', () async {
      final queued = QueuedAds();
      ads = queued;
      final controller = build()
        ..onRunStarted()
        ..onGameOver(defeatStats);
      unawaited(controller.requestContinue());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, SessionPhase.rewardedShowing);

      // The player leaves mid-ad and starts again, and the new run loses too,
      // so the session is back at the very same point when the first ad
      // finally reports its reward.
      controller
        ..onRunStarted()
        ..onGameOver(defeatStats);
      unawaited(controller.requestContinue());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, SessionPhase.rewardedShowing);

      queued.rewarded.first.complete(RewardedOutcome.earned);
      await Future<void>.delayed(Duration.zero);

      // The phase cannot tell the two apart — only the run number can. A
      // stale reward reviving here would hand the new run a continue it
      // never earned.
      expect(reviveCalls, 0);
      expect(controller.state.phase, SessionPhase.rewardedShowing);
    });

    test('a stale interstitial cannot end a newer one', () async {
      final queued = QueuedAds();
      ads = queued;
      final controller = build();

      // Six finalized runs reach two cadence points, so the session is
      // showing its second interstitial when the first one comes back.
      for (var run = 0; run < 6; run++) {
        controller
          ..onRunStarted()
          ..onGameOver(victoryStats);
        await Future<void>.delayed(Duration.zero);
      }
      expect(queued.interstitials, hasLength(2));
      expect(controller.state.phase, SessionPhase.interstitialShowing);

      queued.interstitials.first.complete();
      await Future<void>.delayed(Duration.zero);

      // Both runs sit in interstitialShowing, so the phase alone would have
      // let the older ad close the newer one's.
      expect(controller.state.phase, SessionPhase.interstitialShowing);
    });

    test('a detach in flight does not wipe the next binding', () async {
      final controller = build();
      final first = StreamController<GameEvent>.broadcast();
      final stale = controller.attach(
        events: first.stream,
        revive: () => true,
        score: () => liveScore,
      );

      // Cancelling a subscription is asynchronous, so a new game can attach
      // between detach's ownership check and its cleanup.
      final pending = controller.detach(stale);
      final live = StreamController<GameEvent>.broadcast();
      controller.attach(
        events: live.stream,
        revive: () {
          reviveCalls++;
          return true;
        },
        score: () => liveScore,
      );
      await pending;

      live.add(const RunStarted());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.runNumber, 1);

      // Clearing the fields after the await would have dropped the revive the
      // new page just attached, refusing its rewarded Continue.
      controller.onGameOver(
        const GameOverStats(
          score: 5,
          shotCount: 1,
          maxOccupiedRows: 1,
          ceilingDepth: 0,
          continued: false,
          reason: GameOverReason.defeat,
        ),
      );
      await controller.requestContinue();

      expect(reviveCalls, 1);
      await first.close();
      await live.close();
    });

    test('a stale page cannot release the live binding', () async {
      final controller = build();
      final stale = controller.attach(
        events: gameEvents.stream,
        revive: () => true,
        score: () => liveScore,
      );
      final live = StreamController<GameEvent>.broadcast();
      controller.attach(events: live.stream, revive: () => true, score: () => liveScore);

      // pushReplacement disposes the outgoing page after the incoming one has
      // attached, so this teardown lands once the new game already owns the
      // session.
      await controller.detach(stale);

      live.add(const RunStarted());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.runNumber, 1);
      await live.close();
    });

    test('a reward landing after detach cannot revive a dead game', () async {
      ads.rewardedOutcome = RewardedOutcome.earned;
      final controller = build();
      final binding = controller.attach(
        events: gameEvents.stream,
        revive: () {
          reviveCalls++;
          return reviveResult;
        },
        score: () => liveScore,
      );
      await controller.detach(binding);
      controller
        ..onRunStarted()
        ..onGameOver(
          const GameOverStats(
            score: 10,
            shotCount: 1,
            maxOccupiedRows: 2,
            ceilingDepth: 0,
            continued: false,
            reason: GameOverReason.defeat,
          ),
        );

      await controller.requestContinue();

      // detach drops the revive callback with the subscription, so the reward
      // finalizes the run instead of reaching a disposed BubbleShooter.
      expect(reviveCalls, 0);
      expect(controller.state.phase, SessionPhase.results);
    });
  });
}
