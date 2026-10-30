// 🎯 Dart imports:
import 'dart:ui';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/gen/assets.gen.dart';
import 'package:bubble_shooter/loading/loading.dart';

class _MockImages extends Mock implements Images;

class _MockAudioCache extends Mock implements AudioCache;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(PreloadCubit, () {
    group('loadSequentially', () {
      late Images images;
      late AudioCache audio;
      final imagePaths = Assets.images.values.map((image) => image.path).toList();
      const audioPaths = [
        'assets/audio/background.mp3',
        'assets/audio/bomb.mp3',
        'assets/audio/descent.mp3',
        'assets/audio/gameover.mp3',
        'assets/audio/pop.mp3',
        'assets/audio/rainbow.mp3',
        'assets/audio/shoot.mp3',
      ];

      blocTest<PreloadCubit, PreloadState>(
        'loads assets',
        setUp: () {
          images = _MockImages();
          when(
            () => images.loadAll(imagePaths),
          ).thenAnswer((invocation) => Future.value(<Image>[]));

          audio = _MockAudioCache();
          when(() => audio.loadAll(audioPaths)).thenAnswer(
            (invocation) async => audioPaths.map(Uri.parse).toList(),
          );
        },
        build: () => PreloadCubit(images, audio),
        act: (bloc) => bloc.loadSequentially(),
        expect: () => [
          isA<PreloadState>()
              .having((s) => s.currentLabel, 'currentLabel', equals(''))
              .having((s) => s.totalCount, 'totalCount', equals(2)),
          isA<PreloadState>()
              .having((s) => s.currentLabel, 'currentLabel', equals('audio'))
              .having((s) => s.isComplete, 'isComplete', isFalse)
              .having((s) => s.loadedCount, 'loadedCount', equals(0)),
          isA<PreloadState>()
              .having((s) => s.currentLabel, 'currentLabel', equals('audio'))
              .having((s) => s.isComplete, 'isComplete', isFalse)
              .having((s) => s.loadedCount, 'loadedCount', equals(1)),
          isA<PreloadState>()
              .having((s) => s.currentLabel, 'currentLabel', equals('images'))
              .having((s) => s.isComplete, 'isComplete', isFalse)
              .having((s) => s.loadedCount, 'loadedCount', equals(1)),
          isA<PreloadState>()
              .having((s) => s.currentLabel, 'currentLabel', equals('images'))
              .having((s) => s.isComplete, 'isComplete', isTrue)
              .having((s) => s.loadedCount, 'loadedCount', equals(2)),
        ],
        verify: (bloc) {
          // Spelled out rather than echoing Assets.audio.values back: the
          // risk this guards is a cue shipped but left off the preload
          // list, and a test written from the same expression cannot see it.
          verify(() => audio.loadAll(audioPaths)).called(1);
          verify(
            () => images.loadAll(imagePaths),
          ).called(1);
        },
      );
    });
  });
}
