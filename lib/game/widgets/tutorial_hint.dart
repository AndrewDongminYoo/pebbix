// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/l10n/l10n.dart';

/// First-run one-touch hint (spec §2 package C). It never intercepts
/// input — the hint's whole job is to get the player to drag through it.
class TutorialHint extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                const Icon(
                  Icons.touch_app_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                Flexible(
                  child: Text(
                    context.l10n.tutorialHint,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
