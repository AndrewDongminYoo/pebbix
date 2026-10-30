// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/cubit/cubit.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

class _MockAudioCache extends Mock implements AudioCache;

class _MockAudioPool extends Mock implements AudioPool;

class _MockBgm extends Mock implements Bgm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // File-level, not inside the group: under `very_good test --optimization`
  // every test file shares one isolate and one merged entrypoint.
  setUpAll(() {
    registerFallbackValue(AssetSource(''));
    registerFallbackValue(ReleaseMode.release);
  });

  group('AudioCubit', () {
    late AudioCache cache;
    late Bgm bgm;

    /// Every pool built, in the order the cues asked for one.
    late Map<String, AudioPool> pools;

    /// Holds pool construction open so a test can land teardown mid-warmup.
    Completer<void>? warmupGate;

    /// Holds `AudioPool.start` open so a test can land teardown mid-cue.
    Completer<void>? startGate;

    /// Makes pool construction throw while it returns true.
    bool Function()? failFirstPool;

    Future<AudioPool> buildPool({
      required String path,
      required int maxPlayers,
      AudioCache? audioCache,
    }) async {
      expect(audioCache, same(cache), reason: 'pools use the injected cache');
      await warmupGate?.future;
      if (failFirstPool?.call() ?? false) {
        throw Exception('native player preparation failed');
      }
      final seeded = pools[path];
      if (seeded != null) return seeded;
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer((
        _,
      ) async {
        await startGate?.future;
        return () async {};
      });
      when(pool.dispose).thenAnswer((_) async {});
      pools[path] = pool;
      return pool;
    }

    AudioCubit buildCubit({GameSettings settings = const GameSettings()}) => AudioCubit(
      audioCache: cache,
      backgroundMusic: bgm,
      settings: settings,
      createPool: buildPool,
    );

    setUp(() {
      cache = _MockAudioCache();
      bgm = _MockBgm();
      pools = {};
      warmupGate = null;
      startGate = null;
      failFirstPool = null;
      when(() => bgm.play(any())).thenAnswer((_) async {});
      when(bgm.pause).thenAnswer((_) async {});
      when(bgm.resume).thenAnswer((_) async {});
      when(bgm.dispose).thenAnswer((_) async {});
    });

    test('AudioState props and copyWith preserve both settings', () {
      final state = AudioState(
        bgm: bgm,
        musicEnabled: false,
        sfxEnabled: false,
      );

      final copy = state.copyWith();

      expect(state.props, <Object>[false, false]);
      expect(copy.bgm, same(bgm));
      expect(copy.musicEnabled, isFalse);
      expect(copy.sfxEnabled, isFalse);
    });

    test('constructor seeds settings flags', () {
      final cubit = buildCubit(
        settings: const GameSettings(
          musicEnabled: false,
          sfxEnabled: false,
        ),
      );
      addTearDown(cubit.close);

      expect(cubit.state.musicEnabled, isFalse);
      expect(cubit.state.sfxEnabled, isFalse);
    });

    test('start plays the loop when music is enabled', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');

      verify(() => bgm.play('music.mp3')).called(1);
    });

    test('start stays idle when music is disabled', () async {
      final cubit = buildCubit(
        settings: const GameSettings(musicEnabled: false),
      );
      addTearDown(cubit.close);

      await cubit.start('music.mp3');

      verifyNever(() => bgm.play(any()));
      verifyNever(bgm.pause);
    });

    test('playEffect draws each cue from its own pool', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      // A pop and a descent warning fire on the same landing. A pool serves
      // one source, so sharing one would make the second cut the first —
      // and that warning exists to be heard.
      await cubit.playEffect('pop.mp3');
      await cubit.playEffect('descent.mp3');

      expect(pools.keys, ['pop.mp3', 'descent.mp3']);
      for (final pool in pools.values) {
        verify(pool.start).called(1);
      }
    });

    test('a repeated cue reuses its pool instead of building one', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playEffect('shoot.mp3');
      await cubit.playEffect('shoot.mp3');

      // The pool keeps the source loaded and hands players back when the
      // sound ends; rebuilding per shot is the cost it exists to remove.
      expect(pools, hasLength(1));
      verify(() => pools['shoot.mp3']!.start()).called(2);
    });

    test('two cues racing the same warmup share one pool', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final gate = warmupGate = Completer<void>();

      // Both fire before the first pool finishes warming. Caching the
      // future rather than the pool is what stops them building two.
      final first = cubit.playEffect('pop.mp3');
      final second = cubit.playEffect('pop.mp3');
      gate.complete();
      await Future.wait([first, second]);

      expect(pools, hasLength(1));
    });

    test('playEffect warms no pool while sfx are off', () async {
      final cubit = buildCubit(settings: const GameSettings(sfxEnabled: false));
      addTearDown(cubit.close);

      await cubit.playEffect('pop.mp3');
      await cubit.playEffect(Assets.audio.bomb);
      await cubit.playEffect(Assets.audio.rainbow);

      // Cheaper and more honest than players held at volume zero.
      expect(pools, isEmpty);
    });

    test('special activations and removals use independently playable pools', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await Future.wait([
        cubit.playEffect(Assets.audio.bomb),
        cubit.playEffect(Assets.audio.rainbow),
        cubit.playEffect(Assets.audio.pop),
      ]);
      expect(pools.keys, unorderedEquals([Assets.audio.bomb, Assets.audio.rainbow, Assets.audio.pop]));
      for (final pool in pools.values) {
        verify(pool.start).called(1);
      }
    });

    test('playEffect warms no pool once closing', () async {
      final cubit = buildCubit();
      await cubit.close();

      // The game can land a final cue as the route tears down.
      await cubit.playEffect('gameover.mp3');

      expect(pools, isEmpty);
    });

    test('a teardown mid-warmup never reaches the speaker', () async {
      final cubit = buildCubit();
      final gate = warmupGate = Completer<void>();

      // Back or Home right after a shot closes the route while the cue's
      // pool is still warming. The entry guard cannot see a teardown that
      // has not happened yet.
      final cue = cubit.playEffect('pop.mp3');
      await cubit.close();
      gate.complete();
      await cue;
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => pools['pop.mp3']!.start());
      // And it must not strand: close chained the disposal before the pool
      // even existed.
      verify(pools['pop.mp3']!.dispose).called(1);
    });

    test('close lets an in-flight cue finish before disposing', () async {
      final cubit = buildCubit();
      await cubit.playEffect('pop.mp3');
      final pool = pools['pop.mp3']!;
      final gate = startGate = Completer<void>();

      // Back or Home lands after the cue cleared the teardown guard but
      // while start() still holds the pool's lock.
      final cue = cubit.playEffect('pop.mp3');
      // Let the cue get past the teardown guard and into start() — closing
      // before that only exercises the guard, not the race.
      await Future<void>.delayed(Duration.zero);
      final closing = cubit.close();
      await Future<void>.delayed(Duration.zero);

      // AudioPool.dispose does not take that lock, so disposing now would
      // race start(): it would reserve or build a player the dispose has
      // already walked past, leaving it playing past the route with
      // nothing left to reclaim it.
      verifyNever(pool.dispose);

      gate.complete();
      await cue;
      await closing;
      await Future<void>.delayed(Duration.zero);

      verify(pool.dispose).called(1);
    });

    test('a cue that fails mid-start still lets teardown finish', () async {
      final cubit = buildCubit();
      await cubit.playEffect('pop.mp3');
      final pool = pools['pop.mp3']!;
      final gate = Completer<void>();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer((
        _,
      ) async {
        await gate.future;
        throw Exception('the platform refused the cue');
      });

      final cue = cubit.playEffect('pop.mp3');
      await Future<void>.delayed(Duration.zero);
      final closing = cubit.close();
      // Let close get past the loop teardown and reach its wait on the
      // in-flight cues while this one is still pending, so the rejection
      // lands on the wait rather than before it.
      await Future<void>.delayed(Duration.zero);
      gate.complete();

      // A cue the platform rejects is not a reason to wedge the route —
      // nor to surface an uncaught error through a void callback.
      await expectLater(cue, completes);
      await closing;
      await Future<void>.delayed(Duration.zero);

      verify(pool.dispose).called(1);
    });

    test('stopEffect cuts a cue whose moment has passed', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      var stopped = 0;
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer(
        (_) async =>
            () async => stopped++,
      );
      when(pool.dispose).thenAnswer((_) async {});
      pools['gameover.mp3'] = pool;

      await cubit.playEffect('gameover.mp3');
      // Restart hands play back while the 1.1 s jingle is still ringing; it
      // announced a state that is over.
      await cubit.stopEffect('gameover.mp3');

      expect(stopped, 1);

      // The handle is spent — a second stop is not a second interruption.
      await cubit.stopEffect('gameover.mp3');
      expect(stopped, 1);
    });

    test('stopEffect ignores a cue that never played', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.stopEffect('gameover.mp3');

      expect(pools, isEmpty);
    });

    test('start warms a pool for every cue before it fires', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3', effects: ['pop.mp3', 'shoot.mp3']);

      // AudioCache holds the bytes, but a pool still has to source a
      // player — unwarmed that cost lands on the run's first shot.
      expect(pools.keys, unorderedEquals(['pop.mp3', 'shoot.mp3']));
    });

    test('start warms nothing while sfx are off', () async {
      final cubit = buildCubit(settings: const GameSettings(sfxEnabled: false));
      addTearDown(cubit.close);

      await cubit.start('music.mp3', effects: ['pop.mp3']);

      expect(pools, isEmpty);
    });

    test('turning sfx on warms the cues that were skipped', () async {
      final cubit = buildCubit(settings: const GameSettings(sfxEnabled: false));
      addTearDown(cubit.close);
      await cubit.start('music.mp3', effects: ['pop.mp3']);
      expect(pools, isEmpty);

      await cubit.applySettings(const GameSettings());
      await Future<void>.delayed(Duration.zero);

      expect(pools.keys, ['pop.mp3']);
    });

    test('a pool that fails to build is retried on the next cue', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      var attempts = 0;
      failFirstPool = () => attempts++ == 0;

      // A transient native failure must not silence the cue for the rest
      // of the run, which caching the rejected future would do.
      await cubit.playEffect('pop.mp3');
      expect(pools, isEmpty);

      await cubit.playEffect('pop.mp3');

      expect(attempts, 2);
      verify(pools['pop.mp3']!.start).called(1);
    });

    test('a stop lands on a cue still warming its pool', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final gate = warmupGate = Completer<void>();

      // Restart can beat the very first game-over cue to its pool.
      final cue = cubit.playEffect('gameover.mp3');
      await cubit.stopEffect('gameover.mp3');
      gate.complete();
      await cue;

      verifyNever(pools['gameover.mp3']!.start);
    });

    test('a stop lands on a cue still starting', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      var stopped = 0;
      final pool = _MockAudioPool();
      final gate = Completer<void>();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer((
        _,
      ) async {
        await gate.future;
        return () async => stopped++;
      });
      when(pool.dispose).thenAnswer((_) async {});
      pools['gameover.mp3'] = pool;

      final cue = cubit.playEffect('gameover.mp3');
      await Future<void>.delayed(Duration.zero);
      await cubit.stopEffect('gameover.mp3');
      gate.complete();
      await cue;

      // The handle did not exist when the stop arrived, so the intent has
      // to be spent the moment start() hands one back.
      expect(stopped, 1);
    });

    test('a fresh trigger supersedes a stop aimed at the last one', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.stopEffect('pop.mp3');
      await cubit.playEffect('pop.mp3');

      // A stale intent must not silence the next cue for that asset.
      verify(pools['pop.mp3']!.start).called(1);
    });

    test('a cue whose start fails never escapes the cubit', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer(
        (_) async => throw Exception('the backend rejected the cue'),
      );
      when(pool.dispose).thenAnswer((_) async {});
      pools['pop.mp3'] = pool;

      // playEffect is injected as a void PlaySfx, so an escaping error
      // reaches Flutter as an uncaught async error with no caller to see it.
      await expectLater(cubit.playEffect('pop.mp3'), completes);
    });

    test('close silences playing cues before tearing down the loop', () async {
      final order = <String>[];
      final cubit = buildCubit();
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer(
        (_) async =>
            () async => order.add('cue stopped'),
      );
      when(pool.dispose).thenAnswer((_) async {});
      pools['gameover.mp3'] = pool;
      when(bgm.dispose).thenAnswer((_) async => order.add('bgm disposed'));

      await cubit.playEffect('gameover.mp3');
      await cubit.close();

      // Teardown does not hold up the replacement route, so anything still
      // audible when close starts is audible on the title screen.
      expect(order, ['cue stopped', 'bgm disposed']);
    });

    test('close swallows a warmup that rejects after teardown', () async {
      final cubit = buildCubit();
      final gate = warmupGate = Completer<void>();
      failFirstPool = () => true;

      final cue = cubit.playEffect('pop.mp3');
      await cubit.close();
      gate.complete();
      await cue;
      await Future<void>.delayed(Duration.zero);

      // The disposal chain close() attached must consume the rejection, or
      // it surfaces as an uncaught async error after navigation.
      expect(pools, isEmpty);
    });

    test('stopEffect swallows a backend that refuses', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer(
        (_) async =>
            () async => throw Exception('the player would not stop'),
      );
      when(pool.dispose).thenAnswer((_) async {});
      pools['gameover.mp3'] = pool;
      await cubit.playEffect('gameover.mp3');

      // The session listener fires this with `unawaited`, so a rejection
      // here has nobody to catch it and reaches Flutter uncaught.
      await expectLater(cubit.stopEffect('gameover.mp3'), completes);
    });

    test('a loop that will not tear down still frees the cues', () async {
      final cubit = buildCubit();
      when(bgm.dispose).thenAnswer(
        (_) async => throw Exception('the loop would not tear down'),
      );
      await cubit.playEffect('pop.mp3');
      final pool = pools['pop.mp3']!;

      await expectLater(cubit.close(), completes);
      await Future<void>.delayed(Duration.zero);

      // Otherwise the route walks away holding every warmed pool.
      verify(pool.dispose).called(1);
    });

    test('a repeated cue never cuts its own successor', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final stopped = <int>[];
      var issued = 0;
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer((
        _,
      ) async {
        final id = issued++;
        return () async => stopped.add(id);
      });
      when(pool.dispose).thenAnswer((_) async {});
      pools['shoot.mp3'] = pool;

      // AudioPool hands the same player back out and keys stop() on its
      // id, so a handle held from an earlier instance does not target that
      // instance — it targets whatever is playing on that player now.
      await cubit.playEffect('shoot.mp3');
      await cubit.playEffect('shoot.mp3');
      await cubit.playEffect('shoot.mp3');
      await Future<void>.delayed(Duration.zero);

      expect(stopped, isEmpty, reason: 'a shot must not silence the next');
    });

    test('close survives a cue that refuses to stop', () async {
      final cubit = buildCubit();
      final pool = _MockAudioPool();
      when(() => pool.start(volume: any(named: 'volume'))).thenAnswer(
        (_) async =>
            () async => throw Exception('the player would not stop'),
      );
      when(pool.dispose).thenAnswer((_) async {});
      pools['pop.mp3'] = pool;
      await cubit.playEffect('pop.mp3');

      // Silencing is best-effort; a stubborn cue must not strand the route.
      await expectLater(cubit.close(), completes);
    });

    test('close disposes every pool it warmed', () async {
      final cubit = buildCubit();
      await cubit.playEffect('pop.mp3');
      await cubit.playEffect('shoot.mp3');

      await cubit.close();
      await Future<void>.delayed(Duration.zero);

      // Players live in the pools, so leaving one behind leaks all of them.
      for (final pool in pools.values) {
        verify(pool.dispose).called(1);
      }
    });

    test('applySettings pauses and resumes an existing loop', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');
      await cubit.applySettings(
        const GameSettings(musicEnabled: false),
      );
      await cubit.applySettings(const GameSettings());

      verify(() => bgm.play('music.mp3')).called(1);
      verify(bgm.pause).called(1);
      verify(bgm.resume).called(1);
    });

    test('applySettings never cuts an effect already in flight', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playEffect('pop.mp3');
      await cubit.applySettings(const GameSettings(sfxEnabled: false));

      // Silencing sfx must not reach back into the player carrying the pop;
      // the flag is read by the next cue, not applied to the running one.
      verifyNever(() => pools['pop.mp3']!.dispose());
      expect(cubit.state.sfxEnabled, isFalse);
    });

    test('pauseBackgroundMusic only pauses a started loop', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);
      verifyNever(bgm.pause);

      // The interruption has to clear before a start can take — that is
      // exactly what keeps a fast background from starting the loop.
      await cubit.resumeBackgroundMusic(AudioPauseReason.lifecycle);
      await cubit.start('music.mp3');
      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);

      verify(bgm.pause).called(1);
    });

    test('resumeBackgroundMusic keeps disabled music paused', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');
      await cubit.applySettings(
        const GameSettings(musicEnabled: false),
      );
      clearInteractions(bgm);

      await cubit.resumeBackgroundMusic(AudioPauseReason.lifecycle);

      verify(bgm.pause).called(1);
      verifyNever(bgm.resume);
    });

    test('a background before start never starts the loop', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      // The interruption lands before the page ever starts the loop, so
      // there is nothing to pause yet — the reason itself has to hold the
      // start off, or the loop begins into a backgrounded app.
      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);
      await cubit.start('music.mp3');

      verifyNever(() => bgm.play(any()));

      await cubit.resumeBackgroundMusic(AudioPauseReason.lifecycle);

      verify(() => bgm.play('music.mp3')).called(1);
    });

    test('applySettings stays silent while interrupted', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');
      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);
      clearInteractions(bgm);

      await cubit.applySettings(const GameSettings());

      verifyNever(() => bgm.play(any()));
      verifyNever(bgm.resume);
    });

    test('a music toggle does not latch the interruption flag', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');
      await cubit.applySettings(const GameSettings(musicEnabled: false));
      await cubit.applySettings(const GameSettings());

      verify(bgm.resume).called(1);
    });

    test('overlapping pause reasons each hold the loop silent', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.start('music.mp3');
      await cubit.pauseBackgroundMusic(AudioPauseReason.ad);
      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);
      clearInteractions(bgm);

      // An ad can end while the app is still backgrounded, and a
      // foreground can arrive while the ad is still up — either resume
      // alone must leave the other reason holding.
      await cubit.resumeBackgroundMusic(AudioPauseReason.ad);
      verifyNever(bgm.resume);

      await cubit.resumeBackgroundMusic(AudioPauseReason.lifecycle);
      verify(bgm.resume).called(1);
    });

    test('the newest settings win when two applications overlap', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.start('music.mp3');

      final resuming = Completer<void>();
      when(bgm.resume).thenAnswer((_) => resuming.future);

      final sfx = cubit.applySettings(const GameSettings(sfxEnabled: false));
      final music = cubit.applySettings(
        const GameSettings(musicEnabled: false),
      );
      // Two switches flipped in quick succession, the first still resuming
      // the loop when the second lands: the older snapshot must not emit
      // last, which is why applySettings emits on the way in.
      resuming.complete();
      await Future.wait([sfx, music]);

      expect(cubit.state.musicEnabled, isFalse);
      expect(cubit.state.sfxEnabled, isTrue);
    });

    test('a pause during the play load stops the loop once it takes', () async {
      final playing = Completer<void>();
      final playCalled = Completer<void>();
      when(() => bgm.play(any())).thenAnswer((_) {
        if (!playCalled.isCompleted) playCalled.complete();
        return playing.future;
      });
      final cubit = buildCubit(
        settings: const GameSettings(musicEnabled: false),
      );
      addTearDown(cubit.close);
      await cubit.start('music.mp3');

      // Music turns on, so Bgm.play begins its multi-step load; wait until
      // that load is genuinely in flight, then let a background land during
      // it.
      final applying = cubit.applySettings(const GameSettings());
      await playCalled.future;
      await cubit.pauseBackgroundMusic(AudioPauseReason.lifecycle);
      playing.complete();
      await applying;

      // Bgm.play ends in its own resume(), which would otherwise overtake the
      // pause dispatched mid-load and leave the loop audible in the
      // background. The post-load re-check issues a second, decisive pause.
      verify(bgm.pause).called(2);
    });

    test('a lifecycle resume after teardown never restarts the loop', () async {
      final cubit = buildCubit();
      await cubit.start('music.mp3');
      clearInteractions(bgm);

      // AppLifecycleListener outlives the frame that disposes the page, so
      // a foreground can arrive after close and must not reach a disposed
      // player. `isClosed` is no help — it flips only after super.close().
      await cubit.close();
      await cubit.resumeBackgroundMusic(AudioPauseReason.lifecycle);

      verifyNever(bgm.resume);
      verifyNever(() => bgm.play(any()));
    });

    test('close disposes the loop', () async {
      final cubit = buildCubit();

      await cubit.close();

      verify(bgm.dispose).called(1);
    });
  });
}
