// SPDX-FileCopyrightText: 2026 kr.donminzzi
// SPDX-License-Identifier: MIT

// 🎯 Dart imports:
import 'dart:async';
import 'dart:developer';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';

/// A fixed set of players for one cue, retired if the native backend fails.
/// Playback completion is not needed to reclaim a slot.
class BoundedAudioPool {
  new _();

  final List<AudioPlayer> _players = [];
  final List<StreamSubscription<AudioEvent>> _subscriptions = [];
  final List<int> _generations = [];
  Future<void> _pending = Future<void>.value();
  Future<void>? _disposing;
  var _next = 0;
  var _disposed = false;

  static Future<BoundedAudioPool> createFromAsset({
    required String path,
    required int maxPlayers,
    required AudioCache audioCache,
  }) async {
    if (maxPlayers < 1) throw ArgumentError.value(maxPlayers, 'maxPlayers');
    final pool = BoundedAudioPool._();
    try {
      await pool._serialize(() async {
        for (var i = 0; i < maxPlayers && !pool._disposed; i++) {
          final player = _EffectPlayer()
            ..audioCache = audioCache
            // Cues have no progress UI, so native position polling is unnecessary.
            ..positionUpdater = null;
          pool._players.add(player);
          pool._generations.add(0);
          pool._subscriptions.add(player.eventStream.listen((_) {}, onError: pool._fail));
          await player.setReleaseMode(ReleaseMode.stop);
          if (pool._disposed) return;
          await player.setSource(AssetSource(path));
        }
      });
    } on Exception catch (error, stackTrace) {
      pool._fail(error, stackTrace);
    }
    if (pool._disposed) await pool.dispose();
    return pool;
  }

  Future<StopFunction> start({double volume = 1}) => _serialize(() async {
    if (_disposed) return _ignore;
    final index = _next;
    _next = (_next + 1) % _players.length;
    final player = _players[index];
    final generation = ++_generations[index];
    try {
      // Reusing a busy slot cuts only this cue's oldest playback.
      await player.stop();
      if (_disposed) return _ignore;
      await player.setVolume(volume);
      if (_disposed) return _ignore;
      await player.resume();
    } on Exception catch (error, stackTrace) {
      _fail(error, stackTrace);
      return _ignore;
    }
    return () => _serialize(() async {
      // An old handle must never stop a newer playback on the same player.
      if (_disposed || _generations[index] != generation) return;
      try {
        await player.stop();
      } on Exception catch (error, stackTrace) {
        _fail(error, stackTrace);
      }
    });
  });

  void _fail(Object error, StackTrace stackTrace) {
    log('Effect audio unavailable for this session', error: error, stackTrace: stackTrace);
    unawaited(dispose());
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _serialize(() async {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      for (final player in _players) {
        try {
          await player.dispose();
        } on Object catch (error, stackTrace) {
          // One failed player must not prevent cleanup of the remaining slots.
          // A rejected native create also leaves audioplayers' late fields unset.
          log('Effect audio disposal failed', error: error, stackTrace: stackTrace);
        }
      }
      _subscriptions.clear();
      _players.clear();
    });
  }

  static Future<void> _ignore() async {}
}

/// AudioPlayer.dispose calls release before it cancels streams and disposes native state.
/// A failed native stop or release must not skip that final cleanup.
class _EffectPlayer extends AudioPlayer {
  @override
  Future<void> release() async {
    try {
      await super.release();
    } on Exception catch (error, stackTrace) {
      log('Effect audio release failed; continuing disposal', error: error, stackTrace: stackTrace);
    }
  }
}
