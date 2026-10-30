// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/widgets/tutorial_hint.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('renders the hint without absorbing pointers', (tester) async {
    await tester.pumpApp(const TutorialHint());

    expect(find.text('Drag to aim, release to shoot'), findsOneWidget);
    // MaterialApp's own scaffolding contributes several IgnorePointers, so
    // scope the lookup to the hint's subtree.
    final ignorePointer = find.descendant(
      of: find.byType(TutorialHint),
      matching: find.byType(IgnorePointer),
    );
    expect(ignorePointer, findsOneWidget);
    expect(tester.widget<IgnorePointer>(ignorePointer).ignoring, isTrue);
  });
}
