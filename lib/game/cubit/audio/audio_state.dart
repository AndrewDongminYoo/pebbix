part of 'audio_cubit.dart';

class AudioState extends Equatable {
  const new({
    required this.bgm,
    this.musicEnabled = true,
    this.sfxEnabled = true,
  });

  final Bgm bgm;
  final bool musicEnabled;
  final bool sfxEnabled;

  AudioState copyWith({bool? musicEnabled, bool? sfxEnabled}) {
    return AudioState(
      bgm: bgm,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    );
  }

  @override
  List<Object> get props => [musicEnabled, sfxEnabled];
}
