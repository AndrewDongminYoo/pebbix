// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/bubble_shooter.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

/// Live score and pressure readout shown above the game canvas.
class ScoreHud extends StatelessWidget {
  const new({required this.score, required this.pressure, super.key});

  final ValueListenable<int> score;
  final ValueListenable<PressureState> pressure;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isCompact = mediaQuery.size.height <= 360 || mediaQuery.textScaler.scale(1) > 1.3;
    final textTheme = Theme.of(context).textTheme;
    final scoreStyle = (isCompact ? textTheme.titleMedium : textTheme.titleLarge)?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );
    return Padding(
      padding: EdgeInsets.all(isCompact ? 8 : 16),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 6 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: isCompact ? 2 : 4,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: score,
                builder: (context, value, _) {
                  return Text(
                    context.l10n.scoreLabel(value),
                    style: scoreStyle,
                  );
                },
              ),
              ValueListenableBuilder<PressureState>(
                valueListenable: pressure,
                builder: (context, value, _) {
                  return _PressureReadout(
                    pressure: value,
                    isCompact: isCompact,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressureReadout extends StatelessWidget {
  const new({required this.pressure, required this.isCompact});

  final PressureState pressure;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Only the final shot before a descent. The cadence floors at three
    // shots, so a two-shot threshold would keep the warning lit for two of
    // every three shots once the ceiling has descended three times — going
    // constant on exactly the turns where it most needs to discriminate.
    final isUrgent = pressure.shotsUntilDescent <= 1;
    final color = isUrgent ? Colors.amberAccent : Colors.white;
    final textTheme = Theme.of(context).textTheme;
    final style = (isCompact ? textTheme.bodySmall : textTheme.bodyMedium)?.copyWith(
      color: color,
      fontWeight: FontWeight.bold,
    );
    final aimLabel = pressure.aimAssist.label(l10n);

    final children = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (isUrgent)
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amberAccent,
              size: isCompact ? 16 : 18,
            ),
          Text(
            l10n.ceilingCountdown(pressure.shotsUntilDescent),
            style: style,
          ),
        ],
      ),
      Text(l10n.ceilingDepth(pressure.ceilingOffset), style: style),
      Text(aimLabel, style: style),
    ];
    if (isCompact) {
      return Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: children,
    );
  }
}
