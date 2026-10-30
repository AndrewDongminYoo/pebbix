// 📦 Package imports:
import 'package:equatable/equatable.dart';

enum GameOverReason { victory, defeat }

/// Run statistics captured at the moment a game over is reached.
/// A game over answered by Continue has NOT finalized the run — the
/// session layer decides finalization (spec §4).
final class GameOverStats extends Equatable {
  const new({
    required this.score,
    required this.shotCount,
    required this.maxOccupiedRows,
    required this.ceilingDepth,
    required this.continued,
    required this.reason,
  });

  final int score;
  final int shotCount;
  final int maxOccupiedRows;
  final int ceilingDepth;
  final bool continued;
  final GameOverReason reason;

  @override
  List<Object> get props => [
    score,
    shotCount,
    maxOccupiedRows,
    ceilingDepth,
    continued,
    reason,
  ];
}

/// Domain events the game emits so analytics never enters the game.
sealed class GameEvent extends Equatable {
  const new();

  @override
  List<Object> get props => [];
}

final class RunStarted extends GameEvent {
  const new();
}

final class GameOverReached extends GameEvent {
  const new(this.stats);

  final GameOverStats stats;

  @override
  List<Object> get props => [stats];
}

/// The player committed a shot. Emitted once per fired projectile, before
/// it lands, so the tutorial can time the first shot (spec §7).
final class ShotFired extends GameEvent {
  const new();
}
