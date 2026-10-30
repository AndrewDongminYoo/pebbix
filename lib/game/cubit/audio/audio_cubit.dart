// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:equatable/equatable.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/cubit/audio/bounded_audio_pool.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';

part 'audio_state.dart';

/// Why the loop is currently silenced. The reasons overlap — an ad can
/// start before a background and end after it — so each is tracked
/// separately and the loop only resumes once none is left.
enum AudioPauseReason { lifecycle, ad }

/// The optional `AudioPool` factory seam for tests that observe cues without real players.
/// The default backend is [BoundedAudioPool]; its native-channel tests deliver prepared and error events.
typedef CreateAudioPool = Future<AudioPool> Function({
  required String path,
  required int maxPlayers,
  AudioCache? audioCache,
});

// Keep the existing injected AudioPool API while using a bounded native backend.
typedef _EffectPool = ({Future<StopFunction> Function({double volume}) start, Future<void> Function() dispose});

/// One pool per cue, because a pool serves a single source. Two is enough
/// headroom for a cue that overlaps itself — a shot fired while the last
/// one still rings — with a fixed native player budget.
const _playersPerCue = 2;

class AudioCubit extends Cubit<AudioState> {
  new({
    required AudioCache audioCache,
    required Bgm backgroundMusic,
    GameSettings settings = const GameSettings(),
    this._createPool,
  }) : _cache = audioCache,
       super(
         AudioState(
           bgm: backgroundMusic,
           musicEnabled: settings.musicEnabled,
           sfxEnabled: settings.sfxEnabled,
         ),
       );

  /// The preloaded cache every one-shot is built from. Private rather than
  /// held in state: nothing outside reads it, and `AudioState` exists to
  /// drive rebuilds.
  final AudioCache _cache;

  final CreateAudioPool? _createPool;

  /// One warm pool per cue, keyed by asset. The *future* is cached, not the
  /// pool, so two cues firing before the first finishes warming share one
  /// pool instead of racing to build two.
  final Map<String, Future<_EffectPool>> _pools = {};

  /// Cues asked to stop before they had a player to stop. A cue crosses
  /// two awaits — warming its pool, then starting it — and a stop can land
  /// in either gap; recording the intent is what makes [stopEffect] work at
  /// any point in that lifecycle rather than only at the end of it.
  final Set<String> _cancelled = {};

  /// Cue assets worth keeping warm, learned at [start].
  final Set<String> _sfxAssets = {};

  /// The newest stop handle per cue, kept so a cue can be cut short when the state it announced ends.
  final Map<String, StopFunction> _playing = {};

  /// Cues currently starting, awaited before pool disposal.
  /// The injected `AudioPool` backend needs this guard because its disposal does not take the pool's lock.
  /// [BoundedAudioPool] also serializes its own start and disposal operations.
  final Set<Future<void>> _startingCues = {};

  String? _bgmAsset;

  /// Whether the loop has ever been started. `Bgm.isPlaying` cannot answer
  /// this — it flips to false on pause — and `Bgm.play` re-sources the
  /// player, so resuming through it would restart the track from the top.
  bool _bgmStarted = false;

  /// Reasons the loop is silenced right now. `_bgmStarted` cannot stand in
  /// for this: a background arriving before [start] has nothing to pause
  /// yet, and the start that follows would otherwise begin the loop into an
  /// already-backgrounded app.
  final Set<AudioPauseReason> _pausedFor = {};

  /// Set before [close] disposes the loop, so a call still awaiting an
  /// earlier future cannot reach a disposed player — and so a cue fired on
  /// the way out never opens a new one. `isClosed` is no help: it only
  /// flips after `super.close()`, which runs last.
  bool _closing = false;

  /// Boot entry: starts the loop when the seeded settings allow it. The
  /// constructor only seeds state, so without this the loop would wait for
  /// the player to open Settings.
  Future<void> start(String bgmAsset, {List<String> effects = const []}) async {
    _bgmAsset = bgmAsset;
    _sfxAssets.addAll(effects);
    _warmPools();
    await _syncBgm();
  }

  /// Builds the cue pools before anything triggers them. Preloading fills
  /// [AudioCache] with the bytes but a pool still has to create and source
  /// a player, and unwarmed that lands on the first shot, pop, descent and
  /// loss of the run — the ones a player judges the game by.
  void _warmPools() {
    if (!state.sfxEnabled || _closing) return;
    for (final asset in _sfxAssets) {
      // Rejected factory futures are evicted for retry. The default backend
      // contains native failures and retains a retired, silent pool instead.
      unawaited(_poolFor(asset).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  /// The pool serving [asset], built on first use and shared thereafter.
  Future<_EffectPool> _poolFor(String asset) {
    final existing = _pools[asset];
    if (existing != null) return existing;
    final creating = _createEffectPool(asset);
    _pools[asset] = creating;
    // Retry rejected factory futures without evicting a newer replacement.
    // Native failures in the default backend resolve to a retired pool, which stays cached.
    unawaited(
      creating.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_pools[asset], creating)) _pools.remove(asset);
        },
      ),
    );
    return creating;
  }

  Future<_EffectPool> _createEffectPool(String asset) async {
    final create = _createPool;
    if (create != null) {
      final pool = await create(path: asset, maxPlayers: _playersPerCue, audioCache: _cache);
      return (start: pool.start, dispose: pool.dispose);
    }
    final pool = await BoundedAudioPool.createFromAsset(
      path: asset,
      maxPlayers: _playersPerCue,
      audioCache: _cache,
    );
    return (start: pool.start, dispose: pool.dispose);
  }

  /// Plays a cue from its own pool. A single player holds a single source,
  /// so a pop landing on the same turn as a descent warning would cut it —
  /// and that warning exists to be heard. The default backend reuses a fixed
  /// set of players, so missing completion events cannot accumulate players.
  ///
  /// Silenced SFX warm no pool at all, which is cheaper and more honest
  /// than players held at volume zero.
  Future<void> playEffect(String asset) async {
    if (!state.sfxEnabled || _closing) return;
    // A fresh trigger supersedes a stop aimed at the previous one.
    _cancelled.remove(asset);
    try {
      final pool = await _poolFor(asset);
      if (_cueIsMoot(asset)) return;
      final cue = pool.start();
      _startingCues.add(cue);
      final StopFunction stop;
      try {
        stop = await cue;
      } finally {
        _startingCues.remove(cue);
      }
      if (_cueIsMoot(asset)) {
        await _spend(stop);
        return;
      }
      // Keep only the newest handle for compatibility with injected AudioPool instances,
      // whose old handles can stop a reused player. BoundedAudioPool guards generations.
      // Only the newest overlapping instance can be stopped through this cubit.
      _playing[asset] = stop;
    } on Exception {
      // Contain rejected factory or playback calls at the fire-and-forget boundary.
      // _poolFor evicts rejected factories; the default backend retires native failures internally.
      return;
    }
  }

  /// Whether the cue has lost its reason to be heard: the route is tearing
  /// down, or something asked it to stop while it was still coming up.
  /// Checked at every await boundary, because a cue crosses two of them.
  bool _cueIsMoot(String asset) => _closing || _cancelled.remove(asset);

  /// Cuts a cue's newest playback short.
  /// The game-over jingle can outlive its state when Restart or Continue hands play back.
  Future<void> stopEffect(String asset) async {
    final stop = _playing.remove(asset);
    if (stop == null) {
      // No handle yet — the cue is still warming or starting. Record the
      // intent; [playEffect] spends it at its next boundary.
      _cancelled.add(asset);
      return;
    }
    await _spend(stop);
  }

  /// Spends a stop handle. Silencing is best-effort: every caller is
  /// fire-and-forget — the session listener uses `unawaited`, and [close]
  /// cannot be held up — so a backend that refuses would otherwise land as
  /// an uncaught async error with nobody to catch it.
  Future<void> _spend(StopFunction stop) async {
    try {
      await stop();
    } on Exception {
      return;
    }
  }

  /// Spends every live stop handle. A cue that refuses to stop must not
  /// hold up teardown.
  Future<void> _stopPlayingCues() async {
    final stops = _playing.values.toList();
    _playing.clear();
    for (final stop in stops) {
      await _spend(stop);
    }
  }

  /// Mirrors the persisted settings onto the loop. SFX need nothing here —
  /// [playEffect] reads the flag when the next cue fires, so an effect
  /// already in flight is never cut. BGM starts or pauses, because a muted
  /// loop would hold the audio session open for nothing.
  Future<void> applySettings(GameSettings settings) async {
    if (isClosed) return;
    // Emit before awaiting anything. Two switches flipped in quick
    // succession run concurrently, and an emit placed after the await
    // could land the older snapshot last; emitting on the way in keeps
    // the writes in the order the player made them.
    emit(
      state.copyWith(
        musicEnabled: settings.musicEnabled,
        sfxEnabled: settings.sfxEnabled,
      ),
    );
    _warmPools();
    await _syncBgm();
  }

  /// Spec §6: backgrounding, an interruption, or a showing ad pauses the
  /// loop.
  Future<void> pauseBackgroundMusic(AudioPauseReason reason) async {
    _pausedFor.add(reason);
    await _pauseBgm();
  }

  /// Clears one reason and restores the loop only once no reason is left
  /// and the setting allows it.
  Future<void> resumeBackgroundMusic(AudioPauseReason reason) async {
    _pausedFor.remove(reason);
    await _syncBgm();
  }

  Future<void> _pauseBgm() async {
    if (_closing || !_bgmStarted) return;
    await state.bgm.pause();
  }

  Future<void> _syncBgm() async {
    final asset = _bgmAsset;
    if (asset == null || _closing || _pausedFor.isNotEmpty) return;
    if (!state.musicEnabled) {
      await _pauseBgm();
      return;
    }
    if (_bgmStarted) {
      await state.bgm.resume();
      return;
    }
    _bgmStarted = true;
    await state.bgm.play(asset);
    // `Bgm.play` is a multi-step sequence ending in its own `resume()`, so a
    // pause dispatched while it was in flight got overtaken by that trailing
    // resume — leaving the loop audible with a reason still set or music off.
    // Re-check once play has settled and stop the loop if that happened.
    if (_pausedFor.isNotEmpty || !state.musicEnabled) await _pauseBgm();
  }

  @override
  Future<void> close() async {
    _closing = true;
    // Silence first: everything below is a platform round trip, and widget
    // teardown does not hold up the replacement route, so a cue left
    // running stays audible on the title screen across all of it.
    await _stopPlayingCues();
    // Every step here is best-effort and none may abort the rest: a loop
    // that refuses to tear down must not strand the cue pools or leave the
    // cubit unclosed behind it.
    try {
      await state.bgm.dispose();
    } on Exception {
      // Nothing left to try for the loop; the cues still need reclaiming.
    }
    // Let a cue that already entered start() come out before its pool is
    // disposed — AudioPool.dispose does not take the pool's lock. Bounded
    // by a platform call, unlike a warming pool.
    await Future.wait(_startingCues.toList()).catchError(
      (Object _) => <void>[],
    );
    // Chain disposal rather than awaiting it, so teardown never waits on an
    // asset load, and consume the failure: a warmup that rejects after the
    // route is gone would otherwise surface as an uncaught async error.
    for (final pool in _pools.values) {
      unawaited(
        pool.then((warm) => warm.dispose()).catchError((Object _) {}),
      );
    }
    _pools.clear();
    return await super.close();
  }
}
