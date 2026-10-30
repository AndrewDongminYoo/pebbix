// 📦 Package imports:
import 'package:equatable/equatable.dart';

/// Player settings and the separate Analytics opt-in choice.
class GameSettings extends Equatable {
  const new({
    this.musicEnabled = true,
    this.sfxEnabled = true,
    this.hapticsEnabled = true,
    this.analyticsEnabled = false,
  });

  final bool musicEnabled;
  final bool sfxEnabled;
  final bool hapticsEnabled;
  final bool analyticsEnabled;

  GameSettings copyWith({
    bool? musicEnabled,
    bool? sfxEnabled,
    bool? hapticsEnabled,
    bool? analyticsEnabled,
  }) {
    return GameSettings(
      musicEnabled: musicEnabled ?? this.musicEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
    );
  }

  @override
  List<Object> get props => [musicEnabled, sfxEnabled, hapticsEnabled, analyticsEnabled];
}

/// Single-writer persistence contract for spec §2 packages C + D, fixed
/// before the UI, persistence, and audio implementations parallelize
/// (spec §9 sequencing rule).
///
/// Implementations load their backing store once at boot and then serve
/// synchronous reads; writes are fire-safe futures. The `remove_ads`
/// cache mirrors the last verified store state only — the store remains
/// the source of truth (spec §4).
abstract interface class SettingsRepository {
  GameSettings get settings;
  Future<void> saveSettings(GameSettings settings);

  int get highScore;
  Future<void> saveHighScore(int score);

  bool get tutorialSeen;
  Future<void> markTutorialSeen();

  /// Whether `tutorial_begin` has already been sent for this install.
  ///
  /// Separate from [tutorialSeen], which only flips on the first launched
  /// shot: a player who opens the game and closes it before shooting has
  /// begun the tutorial without seeing it through, and the funnel counts
  /// one begin per install rather than one per launch.
  bool get tutorialBegun;
  Future<void> markTutorialBegun();

  bool get cachedAdsRemoved;
  Future<void> cacheAdsRemoved({required bool removed});
}
