// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flame/cache.dart';
import 'package:meta/meta.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/gen/assets.gen.dart';

part 'preload_state.dart';

class PreloadCubit extends Cubit<PreloadState> {
  new(Images images, AudioCache audio) : super(PreloadState.initial(images: images, audio: audio));

  /// Load items sequentially allows display of what is being loaded
  Future<void> loadSequentially() async {
    final phases = [
      PreloadPhase(
        'audio',
        // Every generated entry, not a hand-written copy of the list: a cue
        // left off would load late on its first play, and no test catches it.
        () => state.audio.loadAll(Assets.audio.values),
      ),
      PreloadPhase(
        'images',
        () => state.images.loadAll(
          Assets.images.values.map((image) => image.path).toList(),
        ),
      ),
    ];

    emit(state.copyWith(totalCount: phases.length));
    for (final phase in phases) {
      emit(state.copyWith(currentLabel: phase.label));
      // Throttle phases to take at least 1/5 seconds
      await Future.wait([
        Future.delayed(Duration.zero, phase.start),
        Future<void>.delayed(const Duration(milliseconds: 200)),
      ]);
      emit(state.copyWith(loadedCount: state.loadedCount + 1));
    }
  }
}

@immutable
class PreloadPhase {
  const new(this.label, this.start);

  final String label;
  final Future<void> Function() start;
}
