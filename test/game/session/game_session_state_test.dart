// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';

void main() {
  test('copyWith keeps every unspecified field', () {
    const state = GameSessionState(
      phase: SessionPhase.results,
      runNumber: 2,
      completedRuns: 1,
      continueUsedOrAttempted: true,
      highScore: 320,
      tutorialSeen: true,
    );
    final copy = state.copyWith();
    expect(copy.phase, SessionPhase.results);
    expect(copy.runNumber, 2);
    expect(copy.completedRuns, 1);
    expect(copy.continueUsedOrAttempted, isTrue);
    expect(copy.highScore, 320);
    expect(copy.tutorialSeen, isTrue);
    expect(state.props, [
      SessionPhase.results,
      2,
      1,
      true,
      null,
      null,
      null,
      320,
      true,
    ]);
  });
}
