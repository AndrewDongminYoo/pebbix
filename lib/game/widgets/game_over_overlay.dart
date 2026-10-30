// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/l10n/l10n.dart';

/// What a finished run did, beyond its score.
///
/// Declared here rather than taken as a `GameOverStats`: nothing in
/// `lib/game/widgets/` imports the domain, and the caller already holds the
/// stats. The values arrive together or not at all, which is why they are one
/// record instead of separate nullable fields.
typedef RunSummary = ({int shotCount, int ceilingDepth, bool continued});

/// End-of-game panel with the final score and a restart button.
class GameOverOverlay extends StatelessWidget {
  const new({
    required this.isVictory,
    required this.score,
    required this.bestScore,
    required this.onRestart,
    required this.onHome,
    this.showContinue = false,
    this.onContinue,
    this.onDecline,
    this.summary,
    super.key,
  });

  final bool isVictory;
  final int score;
  final int bestScore;

  /// Null disables the restart button (e.g. while an ad is showing, so a
  /// stale ad callback can never race a freshly started run).
  final VoidCallback? onRestart;

  /// Spec §3: Home stays reachable regardless of ad state, so unlike restart
  /// it is never disabled. Leaving settles the run and releases the page's
  /// binding; the session itself is app-scoped and outlives the page, so what
  /// makes a late ad callback harmless is that it no longer owns the run it
  /// was started for — not that anything got closed.
  final VoidCallback onHome;
  final bool showContinue;
  final VoidCallback? onContinue;
  final VoidCallback? onDecline;

  /// Null while the run is not finalized — the continue offer is a decision
  /// with a deadline, and this is a retrospective.
  final RunSummary? summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final rewardStyle = textTheme.bodyMedium?.copyWith(color: Colors.white70);
    final rewardFacts = [l10n.continueRewardCeiling, l10n.continueRewardScore, l10n.continueRewardOnce];
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black54,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const padding = EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              );
              final minimumHeight = (constraints.maxHeight - padding.vertical).clamp(0.0, double.infinity);
              return SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minimumHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isVictory ? l10n.victoryTitle : l10n.defeatTitle,
                        style: textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.scoreLabel(score),
                        style: textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.bestScoreLabel(bestScore),
                        style: textTheme.titleMedium?.copyWith(color: Colors.white70),
                      ),
                      if (summary case final run?) ...[
                        const SizedBox(height: 12),
                        // Shots and their yield read as one fact — the same
                        // score off fewer shots is the bank shots and cluster
                        // drops this game exists to teach. A run that fired
                        // nothing has neither to report.
                        if (run.shotCount > 0)
                          Text(
                            l10n.runShotsLabel(run.shotCount, score / run.shotCount),
                            style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                        Text(
                          l10n.ceilingDepth(run.ceilingDepth),
                          style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                        ),
                        // Only when it happened: a "not used" row is noise,
                        // and the line exists to make the ad's value visible.
                        if (run.continued)
                          Text(
                            l10n.runContinuedLabel,
                            style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                      ],
                      const SizedBox(height: 24),
                      if (showContinue) ...[
                        // Said before the tap, not after it: the button alone
                        // asks for an ad without naming what the ad buys.
                        // Three separate facts rather than one string, because
                        // Flutter breaks Korean between any two syllables: a
                        // single line split "점수 유지" in half at 200% text on
                        // a 320-wide screen. A Wrap moves whole facts instead.
                        // Each separator is glued to the fact before it with
                        // a no-break space, so no line starts with a dot, and
                        // screen readers skip it.
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          children: [
                            for (final (index, fact) in rewardFacts.indexed)
                              Text.rich(
                                TextSpan(
                                  text: fact,
                                  children: [
                                    if (index < rewardFacts.length - 1)
                                      const TextSpan(text: '\u00A0·', semanticsLabel: ''),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                                style: rewardStyle,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: onContinue,
                          child: Text(l10n.continueWithAd),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: onDecline,
                          child: Text(
                            l10n.skipContinue,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ] else
                        ElevatedButton(
                          onPressed: onRestart,
                          child: Text(l10n.playAgain),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onHome,
                        child: Text(
                          l10n.homeButton,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
