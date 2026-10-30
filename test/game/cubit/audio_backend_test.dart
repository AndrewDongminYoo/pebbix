// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/cubit/audio/audio_cubit.dart';
import 'package:bubble_shooter/game/cubit/audio/bounded_audio_pool.dart';

class _MockCache extends Mock implements AudioCache;

class _MockBgm extends Mock implements Bgm;

/// Keeps the package's players and event subscriptions real, replacing only Android.
class _NativeAudio {
  final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = <String>[];
  final disposed = <String>[];
  final resumed = <String>[];
  final stopped = <String>[];
  final channels = <MethodChannel>[];
  Future<void> Function(String method, String id)? beforeCall;

  void install() {
    messenger
      ..setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null)
      ..setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global/events'), (_) async => null)
      ..setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
        final arguments = call.arguments as Map<Object?, Object?>;
        final id = arguments['playerId']! as String;
        await beforeCall?.call(call.method, id);
        switch (call.method) {
          case 'create':
            created.add(id);
            final channel = MethodChannel('xyz.luan/audioplayers/events/$id');
            channels.add(channel);
            messenger.setMockMethodCallHandler(channel, (_) async => null);
          case 'setSourceUrl':
            await event(id, {'event': 'audio.onPrepared', 'value': true});
          case 'resume':
            resumed.add(id);
          case 'stop':
            stopped.add(id);
          case 'dispose':
            disposed.add(id);
          case 'getCurrentPosition':
            return 0;
        }
        return null;
      });
  }

  Future<void> event(String id, Map<String, Object> value) async {
    await messenger.handlePlatformMessage(
      'xyz.luan/audioplayers/events/$id',
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  Future<void> fail(String id) async {
    await messenger.handlePlatformMessage(
      'xyz.luan/audioplayers/events/$id',
      const StandardMethodCodec().encodeErrorEnvelope(
        code: 'AndroidAudioError',
        message: 'MEDIA_ERROR_UNKNOWN {what:1}',
        details: 'MEDIA_ERROR_UNKNOWN {extra:-19}',
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  void uninstall() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    // GamePage's suite uses this same no-op handler in the optimized runner.
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (_) async => null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native audio failures', () {
    late _NativeAudio native;
    late AudioCache cache;
    late Bgm bgm;
    late AudioLogLevel previousLogLevel;

    setUp(() {
      native = _NativeAudio()..install();
      previousLogLevel = AudioLogger.logLevel;
      AudioLogger.logLevel = AudioLogLevel.none;
      cache = _MockCache();
      bgm = _MockBgm();
      when(() => cache.loadPath(any())).thenAnswer((call) async => '/cache/${call.positionalArguments.single}');
      when(bgm.dispose).thenAnswer((_) async {});
    });

    tearDown(() async {
      await Future<void>.delayed(Duration.zero);
      native.uninstall();
      AudioLogger.logLevel = previousLogLevel;
    });

    test('a native playback error cannot escape the default effect backend', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final cubit = AudioCubit(audioCache: cache, backgroundMusic: bgm);
        await cubit.playEffect('pop.mp3');
        expect(native.resumed, isNotEmpty, reason: 'the fixture must reach native playback');
        await native.fail(native.resumed.last);
        await cubit.close();
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty, reason: 'AndroidAudioError must not reach the global fatal handler');
      expect(native.disposed, unorderedEquals(native.created));
    });

    test('overlapping cues cannot create an unbounded number of native players', () async {
      final cubit = AudioCubit(audioCache: cache, backgroundMusic: bgm);
      addTearDown(cubit.close);

      for (var i = 0; i < 12; i++) {
        await cubit.playEffect('pop.mp3');
      }

      expect(native.resumed, hasLength(12));
      expect(native.created.length, lessThanOrEqualTo(2));
    });

    test('a failed cue stays silent while other cues remain playable', () async {
      final cubit = AudioCubit(audioCache: cache, backgroundMusic: bgm);
      await cubit.playEffect('pop.mp3');
      final failedPlayers = native.created.toList();
      await native.fail(native.resumed.last);
      await cubit.playEffect('pop.mp3');

      expect(native.resumed, hasLength(1));
      expect(native.created, failedPlayers);
      expect(native.disposed, unorderedEquals(failedPlayers));

      await cubit.playEffect('shoot.mp3');
      expect(native.resumed, hasLength(2));
      expect(failedPlayers, isNot(contains(native.resumed.last)));
      await cubit.close();
      await Future<void>.delayed(Duration.zero);
      expect(native.disposed, unorderedEquals(native.created));
    });

    test('initialization failure disposes partial players and does not retry each cue', () async {
      var sources = 0;
      native.beforeCall = (method, id) async {
        if (method == 'setSourceUrl' && ++sources == 2) {
          await native.fail(id);
          throw PlatformException(code: 'AndroidAudioError');
        }
      };
      final cubit = AudioCubit(audioCache: cache, backgroundMusic: bgm);
      await cubit.playEffect('pop.mp3');
      await cubit.playEffect('pop.mp3');

      expect(native.created, hasLength(2));
      expect(native.disposed, unorderedEquals(native.created));
      expect(native.resumed, isEmpty);
      await cubit.close();
    });

    test('native creation failure cannot escape partial player cleanup', () async {
      final failures = <Object>[];
      var creations = 0;
      native.beforeCall = (method, _) async {
        if (method == 'create' && ++creations == 2) {
          throw PlatformException(code: 'AndroidAudioError');
        }
      };

      await runZonedGuarded(() async {
        try {
          final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
          await pool.start();
          await pool.dispose();
        } on Object catch (error) {
          failures.add(error);
        }
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => failures.add(error));

      expect(creations, 2, reason: 'the fixture must fail after one successful native allocation');
      expect(failures, isEmpty, reason: 'partial initialization cleanup must not escape the effect backend');
      expect(native.resumed, isEmpty);
      expect(native.disposed, unorderedEquals(native.created));
    });

    for (final method in ['stop', 'setVolume', 'resume']) {
      test('a failed $method retires the effect backend', () async {
        final cubit = AudioCubit(audioCache: cache, backgroundMusic: bgm);
        await cubit.playEffect('pop.mp3');
        final players = native.created.toList();
        native.beforeCall = (call, _) async {
          if (call == method) throw PlatformException(code: 'AndroidAudioError');
        };

        await cubit.playEffect('pop.mp3');
        await cubit.playEffect('pop.mp3');
        await Future<void>.delayed(Duration.zero);

        expect(native.created, players);
        expect(native.resumed, hasLength(1));
        expect(native.disposed, unorderedEquals(players));
        await cubit.close();
      });
    }

    test('a stop handle cannot stop the next playback on a reused slot', () async {
      final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
      final firstStop = await pool.start();
      await pool.start();
      final latestStop = await pool.start();
      final stopsBefore = native.stopped.length;

      await firstStop();
      expect(native.stopped, hasLength(stopsBefore));
      await latestStop();
      expect(native.stopped, hasLength(stopsBefore + 1));
      expect(native.stopped.last, native.resumed.last);
      await pool.dispose();
      final stopsAfterDisposal = native.stopped.length;
      await latestStop();
      expect(native.stopped, hasLength(stopsAfterDisposal));
    });

    test('a failed stop handle retires all slots', () async {
      final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
      final stop = await pool.start();
      native.beforeCall = (method, _) async {
        if (method == 'stop') throw PlatformException(code: 'AndroidAudioError');
      };

      await stop();
      await pool.dispose();
      expect(native.disposed, unorderedEquals(native.created));
    });

    test('a failed disposal does not strand the other slots', () async {
      final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
      final attempts = <String>[];
      native.beforeCall = (method, id) async {
        if (method == 'dispose') {
          attempts.add(id);
          if (id == native.created.first) throw PlatformException(code: 'disposal failed');
        }
      };

      await pool.dispose();
      await pool.dispose();
      expect(attempts, native.created);
      expect(native.disposed, [native.created.last]);
    });

    for (final method in ['stop', 'setVolume']) {
      test('disposal during $method prevents a late resume', () async {
        final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
        final entered = Completer<void>();
        final release = Completer<void>();
        native.beforeCall = (call, _) async {
          if (call == method && !entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        };
        final starting = pool.start();
        await entered.future;
        final disposing = pool.dispose();
        expect(native.disposed, isEmpty, reason: 'cleanup waits for the in-flight command');
        release.complete();
        final stop = await starting;
        await disposing;
        await stop();

        expect(native.resumed, isEmpty);
        expect(native.disposed, unorderedEquals(native.created));
      });
    }

    test('an error during initialization cannot prepare another player', () async {
      native.beforeCall = (method, id) async {
        if (method == 'setReleaseMode') await native.fail(id);
      };
      final pool = await BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 2, audioCache: cache);
      await pool.start();

      expect(native.created, hasLength(1));
      expect(native.disposed, native.created);
      expect(native.resumed, isEmpty);
    });

    test('a pool rejects an empty player budget before native allocation', () async {
      await expectLater(
        BoundedAudioPool.createFromAsset(path: 'pop.mp3', maxPlayers: 0, audioCache: cache),
        throwsArgumentError,
      );
      expect(native.created, isEmpty);
    });
  });
}
