// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/domain.dart';

void main() {
  const stats = GameOverStats(
    score: 120,
    shotCount: 7,
    maxOccupiedRows: 9,
    ceilingDepth: 2,
    continued: false,
    reason: GameOverReason.defeat,
  );

  test('GameOverStats equality is value-based', () {
    expect(
      stats,
      const GameOverStats(
        score: 120,
        shotCount: 7,
        maxOccupiedRows: 9,
        ceilingDepth: 2,
        continued: false,
        reason: GameOverReason.defeat,
      ),
    );
    expect(stats == stats.copyless(score: 121), isFalse);
    expect(stats == stats.copyless(ceilingDepth: 3), isFalse);
  });

  test('events are value-equal', () {
    expect(const RunStarted(), const RunStarted());
    expect(const ShotFired(), const ShotFired());
    expect(const GameOverReached(stats), const GameOverReached(stats));
    // Const canonicalization short-circuits == via identical(), so touch
    // the props directly to prove the equality contract.
    expect(const RunStarted().props, isEmpty);
    expect(const ShotFired().props, isEmpty);
    expect(const GameOverReached(stats).props, [stats]);
  });
}

extension on GameOverStats {
  GameOverStats copyless({int? score, int? ceilingDepth}) => GameOverStats(
    score: score ?? this.score,
    shotCount: shotCount,
    maxOccupiedRows: maxOccupiedRows,
    ceilingDepth: ceilingDepth ?? this.ceilingDepth,
    continued: continued,
    reason: reason,
  );
}
