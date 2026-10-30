// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

/// Haptics boundary: turns the cue the game already names for sound into a
/// vibration, subject to the player's setting.
///
/// The game emits one cue per outcome worth feeling — a launched shot, a
/// resolved match or drop, the ceiling closing in, the run ending — and it
/// emits them through `PlaySfx`, which carries the asset path. Keying the
/// strengths off those same paths is why the game needs no second callback
/// and no platform import: haptics stay a companion to the audio cue rather
/// than a parallel event surface the domain has to maintain.
///
/// Strengths ladder with consequence, so a shot is lighter than a pop and a
/// game over is the only heavy one. Anything not in the table — the
/// background loop — is silent to the hand.
class HapticsGateway {
  const new(this._settings);

  final SettingsRepository _settings;

  /// Late-bound rather than `const`, because the generated asset paths are
  /// getters. A renamed audio file changes both this table and the game's
  /// own call, so the pairing cannot drift apart.
  static final Map<String, Future<void> Function()> _cues = {
    Assets.audio.shoot: HapticFeedback.selectionClick,
    Assets.audio.pop: HapticFeedback.lightImpact,
    Assets.audio.descent: HapticFeedback.mediumImpact,
    Assets.audio.gameover: HapticFeedback.heavyImpact,
  };

  /// Plays the vibration paired with [asset], if the player wants haptics
  /// and the cue has one.
  ///
  /// Fire-and-forget by contract: the caller is `PlaySfx`, which the game
  /// invokes mid-frame and cannot await. A platform without a vibrator
  /// answers the channel with an error rather than silence, and the web
  /// build has no handler at all, so the failure is swallowed here — a
  /// missing vibration must never interrupt a shot.
  void forCue(String asset) {
    if (!_settings.settings.hapticsEnabled) return;
    final feedback = _cues[asset];
    if (feedback == null) return;
    unawaited(feedback().catchError((Object _) {}));
  }

  /// The single cue callback the game is handed: [playSfx] sounds it and
  /// this gateway vibrates with it.
  ///
  /// Composed here rather than in the view so the pairing is covered by a
  /// unit test — reaching it through the view would mean building a real
  /// `BubbleShooter` and its image cache to exercise two lines.
  void Function(String) pairedWith(void Function(String) playSfx) => (asset) {
    playSfx(asset);
    forCue(asset);
  };
}
