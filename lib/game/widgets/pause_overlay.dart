// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/l10n/l10n.dart';

/// Pause panel shown over a paused run (spec §2 package C).
class PauseOverlay extends StatelessWidget {
  const new({
    required this.onResume,
    required this.onHowToPlay,
    required this.onSettings,
    required this.onRestart,
    super.key,
  });

  final VoidCallback onResume;

  /// Opens the rules page over the paused run, which stays paused.
  final VoidCallback onHowToPlay;
  final VoidCallback onSettings;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    // Scrolls rather than clips (spec 0002 §8). With four actions, doubled
    // Korean text exactly fills a 568×320 host, so any inset would cut off
    // Restart; when everything fits, the panel stays centered as before.
    return ColoredBox(
      color: Colors.black54,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Text(
                  l10n.pauseTitle,
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: onResume,
                  child: Text(l10n.pauseResume),
                ),
                ElevatedButton(
                  onPressed: onHowToPlay,
                  child: Text(l10n.howToPlayTitle),
                ),
                ElevatedButton(
                  onPressed: onSettings,
                  child: Text(l10n.pauseSettings),
                ),
                TextButton(
                  onPressed: onRestart,
                  child: Text(
                    l10n.pauseRestart,
                    style: const TextStyle(color: Colors.white70),
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
