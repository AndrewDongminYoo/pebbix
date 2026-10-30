// 📦 Package imports:
import 'package:equatable/equatable.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

enum SessionPhase {
  playing,
  continueOffer,
  rewardedShowing,
  results,
  interstitialShowing,
}

final class GameSessionState extends Equatable {
  const new({
    this.phase = SessionPhase.playing,
    this.runNumber = 0,
    this.completedRuns = 0,
    this.continueUsedOrAttempted = false,
    this.lastGameOver,
    this.lastInterstitialAt,
    this.runStartedAt,
    this.highScore = 0,
    this.tutorialSeen = false,
  });

  final SessionPhase phase;

  /// 1-based index of the current *started* run, counted monotonically.
  /// Deriving it from [completedRuns] would reuse a number whenever an
  /// attempt is abandoned — a pause-restart, say — leaving the funnel with
  /// two `run_start` events sharing one id and no `run_end` between them.
  final int runNumber;

  /// Finalized runs — a continued run finalizes once (spec §4).
  final int completedRuns;

  /// True once Continue was used or attempted in the current game-over
  /// cycle; such a cycle never shows an interstitial.
  final bool continueUsedOrAttempted;

  final GameOverStats? lastGameOver;
  final DateTime? lastInterstitialAt;
  final DateTime? runStartedAt;

  /// Best score ever recorded, seeded from the settings store at
  /// construction and updated when a run beats it.
  final int highScore;

  /// True once the first-run hint has been dismissed by a first shot.
  final bool tutorialSeen;

  /// An ad future is in flight. Restarting into it, and letting the BGM
  /// play over it, are both wrong, so its two readers share one definition.
  bool get adShowing => phase == SessionPhase.rewardedShowing || phase == SessionPhase.interstitialShowing;

  /// Nullable fields are only ever overwritten, never cleared — the
  /// session has no need to forget them.
  GameSessionState copyWith({
    SessionPhase? phase,
    int? runNumber,
    int? completedRuns,
    bool? continueUsedOrAttempted,
    GameOverStats? lastGameOver,
    DateTime? lastInterstitialAt,
    DateTime? runStartedAt,
    int? highScore,
    bool? tutorialSeen,
  }) => GameSessionState(
    phase: phase ?? this.phase,
    runNumber: runNumber ?? this.runNumber,
    completedRuns: completedRuns ?? this.completedRuns,
    continueUsedOrAttempted: continueUsedOrAttempted ?? this.continueUsedOrAttempted,
    lastGameOver: lastGameOver ?? this.lastGameOver,
    lastInterstitialAt: lastInterstitialAt ?? this.lastInterstitialAt,
    runStartedAt: runStartedAt ?? this.runStartedAt,
    highScore: highScore ?? this.highScore,
    tutorialSeen: tutorialSeen ?? this.tutorialSeen,
  );

  @override
  List<Object?> get props => [
    phase,
    runNumber,
    completedRuns,
    continueUsedOrAttempted,
    lastGameOver,
    lastInterstitialAt,
    runStartedAt,
    highScore,
    tutorialSeen,
  ];
}
