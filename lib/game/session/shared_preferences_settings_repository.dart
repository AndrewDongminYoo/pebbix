// 📦 Package imports:
import 'package:shared_preferences/shared_preferences.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/settings_repository.dart';

/// The shipping [SettingsRepository]: loads the platform store once via
/// [load], then serves synchronous reads from it (spec §2 package D).
class SharedPreferencesSettingsRepository implements SettingsRepository {
  new _(this._prefs);

  static const _musicKey = 'settings.musicEnabled';
  static const _sfxKey = 'settings.sfxEnabled';
  static const _hapticsKey = 'settings.hapticsEnabled';
  static const _analyticsKey = 'privacy.analyticsEnabled';
  static const _highScoreKey = 'progress.highScore';
  static const _tutorialSeenKey = 'progress.tutorialSeen';
  static const _tutorialBegunKey = 'progress.tutorialBegun';
  static const _adsRemovedKey = 'entitlement.adsRemovedCache';

  final SharedPreferences _prefs;

  /// Writes run one after another. Two snapshots saved in quick succession
  /// would otherwise interleave their key writes, and an older one could
  /// land a key after a newer one — leaving the store holding a selection
  /// the player already replaced, or a high score they already beat.
  Future<void> _writes = Future<void>.value();

  /// The newest values requested, held so reads never wait on [_writes].
  /// The plugin's own cache updates at call time, so queueing the writes
  /// without these would let a read taken mid-queue miss the choice that
  /// produced it — and then save that stale snapshot straight back.
  GameSettings? _latestSettings;
  int? _latestHighScore;
  bool? _latestAdsRemoved;

  static Future<SharedPreferencesSettingsRepository> load() async => SharedPreferencesSettingsRepository._(
    await SharedPreferences.getInstance(),
  );

  /// Queues [write] behind every earlier one. A failure must not poison the
  /// chain for every later save, so only the caller sees it.
  Future<void> _queue(Future<void> Function() write) {
    final queued = _writes.then((_) => write());
    _writes = queued.catchError((Object _) {});
    return queued;
  }

  @override
  GameSettings get settings =>
      _latestSettings ??
      GameSettings(
        musicEnabled: _prefs.getBool(_musicKey) ?? true,
        sfxEnabled: _prefs.getBool(_sfxKey) ?? true,
        hapticsEnabled: _prefs.getBool(_hapticsKey) ?? true,
        analyticsEnabled: _prefs.getBool(_analyticsKey) ?? false,
      );

  @override
  Future<void> saveSettings(GameSettings settings) {
    _latestSettings = settings;
    return _queue(() async {
      await _prefs.setBool(_analyticsKey, settings.analyticsEnabled);
      await _prefs.setBool(_musicKey, settings.musicEnabled);
      await _prefs.setBool(_sfxKey, settings.sfxEnabled);
      await _prefs.setBool(_hapticsKey, settings.hapticsEnabled);
    });
  }

  @override
  int get highScore => _latestHighScore ?? _prefs.getInt(_highScoreKey) ?? 0;

  @override
  Future<void> saveHighScore(int score) {
    _latestHighScore = score;
    return _queue(() => _prefs.setInt(_highScoreKey, score));
  }

  @override
  bool get tutorialSeen => _prefs.getBool(_tutorialSeenKey) ?? false;

  @override
  Future<void> markTutorialSeen() async {
    await _prefs.setBool(_tutorialSeenKey, true);
  }

  @override
  bool get tutorialBegun => _prefs.getBool(_tutorialBegunKey) ?? false;

  @override
  Future<void> markTutorialBegun() async {
    await _prefs.setBool(_tutorialBegunKey, true);
  }

  @override
  bool get cachedAdsRemoved => _latestAdsRemoved ?? _prefs.getBool(_adsRemovedKey) ?? false;

  @override
  Future<void> cacheAdsRemoved({required bool removed}) {
    // Queued like every other write here. A restore clearing the cache and a
    // purchase granting it can overlap, and an older `false` landing after a
    // newer `true` would show forced ads to a paying player on the next
    // offline launch.
    _latestAdsRemoved = removed;
    return _queue(() => _prefs.setBool(_adsRemovedKey, removed));
  }
}
