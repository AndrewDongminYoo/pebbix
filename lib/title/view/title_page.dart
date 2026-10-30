// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flame/components.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/settings_route.dart';
import 'package:bubble_shooter/game/game.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';

class TitlePage extends StatelessWidget {
  const new({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const TitlePage());
  }

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(body: TitleView()),
    );
  }
}

class TitleView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final images = context.read<PreloadCubit>().state.images;
    Sprite? spriteFor(BubbleColor color) {
      final path = color.spriteAsset.path;
      return images.containsKey(path) ? Sprite(images.fromCache(path)) : null;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Assets.images.background.image(fit: BoxFit.cover),
        SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The board's own palette and painter, so the first screen
                  // already shows the engraved bubbles the player will shoot.
                  for (final color in BubbleColor.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox.square(
                        dimension: 36,
                        child: LegendBubble(
                          shot: (color: color, kind: ShotKind.normal),
                          sprite: spriteFor(color),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.titleAppBarTitle,
                textAlign: TextAlign.center,
                style: textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: 250,
                height: 64,
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(
                      context,
                    ).pushReplacement<void, void>(GamePage.route());
                  },
                  child: Center(child: Text(l10n.titleButtonStart)),
                ),
              ),
              const SizedBox(height: 8),
              // Under Start rather than beside the settings icon: the player
              // who needs the rules is the one who has not played yet.
              TextButton(
                onPressed: () => unawaited(HowToPlayPage.open(context)),
                child: Text(
                  l10n.howToPlayTitle,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                tooltip: l10n.settingsTitle,
                // Shared with the pause panel's route, so this entry point
                // cannot offer less than that one — spec §Privacy needs the
                // policy readable before the first game, and UMP needs its
                // consent row wherever the region requires it.
                onPressed: () => unawaited(openSettings(context)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
