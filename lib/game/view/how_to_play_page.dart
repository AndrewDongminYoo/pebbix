// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/components/components.dart';
import 'package:bubble_shooter/game/domain/domain.dart';
import 'package:bubble_shooter/game/widgets/game_menu_page.dart';
import 'package:bubble_shooter/l10n/l10n.dart';
import 'package:bubble_shooter/loading/loading.dart';

/// One page of rules, opened by the player from Title or Pause.
///
/// It explains what the game already does (product-owner review, items 1
/// and 7), so it stays a reference rather than a tutorial: the first-run hint
/// still covers the first shot, and nothing here opens on its own.
class HowToPlayPage extends StatelessWidget {
  const new({required this.images, super.key});

  /// The preloaded sprite cache. The legend draws the same engraved bubbles
  /// the board does, and falls back to the same procedural painter for any
  /// image that is not cached.
  final Images images;

  static Route<void> route(Images images) => MaterialPageRoute<void>(builder: (_) => HowToPlayPage(images: images));

  /// Both entry points open the page through here, so neither can show a
  /// legend drawn from anything but the app's preloaded sprites.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(route(context.read<PreloadCubit>().state.images));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Sprite? spriteFor(BubbleColor color) {
      final path = color.spriteAsset.path;
      return images.containsKey(path) ? Sprite(images.fromCache(path)) : null;
    }

    Widget rule(IconData icon, String text) => ListTile(leading: Icon(icon), title: Text(text));
    Widget special(ShotKind kind, BubbleColor base, String text) => ListTile(
      leading: LegendBubble(shot: (color: base, kind: kind), sprite: spriteFor(base)),
      title: Text(text),
    );

    return GameMenuPage(
      title: l10n.howToPlayTitle,
      children: [
        rule(Icons.touch_app, l10n.howToPlayAim),
        const Divider(),
        rule(Icons.join_full, l10n.howToPlayMatch),
        rule(Icons.south, l10n.howToPlayDrop),
        rule(Icons.call_split, l10n.howToPlayBounce),
        const Divider(),
        rule(Icons.vertical_align_bottom, l10n.howToPlayCeiling),
        rule(Icons.timeline, l10n.howToPlayAimGuide),
        const Divider(),
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(l10n.howToPlayBubbles, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in BubbleColor.values)
                LegendBubble(
                  shot: (color: color, kind: ShotKind.normal),
                  sprite: spriteFor(color),
                ),
            ],
          ),
        ),
        ListTile(title: Text(l10n.howToPlayColors)),
        special(ShotKind.bomb, BubbleColor.red, l10n.howToPlayBomb),
        special(ShotKind.rainbow, BubbleColor.blue, l10n.howToPlayRainbow),
      ],
    );
  }
}

/// One bubble of the legend, drawn by the board's own painter, markers
/// included.
class LegendBubble extends StatelessWidget {
  const new({required this.shot, required this.sprite, super.key});

  final LauncherShot shot;
  final Sprite? sprite;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(32),
    painter: _BubblePainter(shot: shot, sprite: sprite),
  );
}

class _BubblePainter extends CustomPainter {
  const new({required this.shot, required this.sprite});

  final LauncherShot shot;
  final Sprite? sprite;

  @override
  void paint(Canvas canvas, Size size) =>
      paintLauncherShot(canvas, size.center(Offset.zero), size.shortestSide / 2, shot, sprite: sprite);

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => oldDelegate.shot != shot || oldDelegate.sprite != sprite;
}
