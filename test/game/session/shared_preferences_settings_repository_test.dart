// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';

/// Stalls the very first write so a second snapshot can run its whole
/// sequence underneath it — the interleaving the repository guards against.
class _StallingStore extends InMemorySharedPreferencesStore {
  new() : super.withData(const {});

  final _firstWrite = Completer<void>();
  var _writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (_writes++ == 0) await _firstWrite.future;
    return await super.setValue(valueType, key, value);
  }

  void release() => _firstWrite.complete();
}

class _StallingMusicStore extends InMemorySharedPreferencesStore {
  new() : super.withData(const {'flutter.privacy.analyticsEnabled': true});

  final musicWriteStarted = Completer<void>();
  final _releaseMusic = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.settings.musicEnabled') {
      musicWriteStarted.complete();
      await _releaseMusic.future;
    }
    return await super.setValue(valueType, key, value);
  }

  void release() => _releaseMusic.complete();
}

/// A repository as the next app launch would build it. A plain
/// [SharedPreferencesSettingsRepository.load] would hand back the
/// process-wide [SharedPreferences] with its populated cache,
/// so only dropping that cache reads what actually reached the store.
Future<SharedPreferencesSettingsRepository> _relaunch() {
  SharedPreferences.resetStatic();
  return SharedPreferencesSettingsRepository.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(SharedPreferencesSettingsRepository, () {
    test('serves spec defaults from an empty store', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await SharedPreferencesSettingsRepository.load();

      expect(repo.settings, const GameSettings());
      expect(repo.highScore, 0);
      expect(repo.tutorialSeen, isFalse);
      expect(repo.tutorialBegun, isFalse);
      expect(repo.cachedAdsRemoved, isFalse);
    });

    test('round-trips every surface through the store', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await SharedPreferencesSettingsRepository.load();

      await repo.saveSettings(
        const GameSettings(musicEnabled: false, hapticsEnabled: false, analyticsEnabled: true),
      );
      await repo.saveHighScore(12480);
      await repo.markTutorialSeen();
      await repo.markTutorialBegun();
      await repo.cacheAdsRemoved(removed: true);

      final reloaded = await _relaunch();
      expect(
        reloaded.settings,
        const GameSettings(musicEnabled: false, hapticsEnabled: false, analyticsEnabled: true),
      );
      expect(reloaded.highScore, 12480);
      expect(reloaded.tutorialSeen, isTrue);
      // Survives the relaunch, which is the whole point of the flag: the
      // controller's in-memory latch dies with the process.
      expect(reloaded.tutorialBegun, isTrue);
      expect(reloaded.cachedAdsRemoved, isTrue);
    });

    test('withdrawal reaches durable storage before unrelated settings writes', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _StallingMusicStore();
      SharedPreferencesStorePlatform.instance = store;
      final repo = await SharedPreferencesSettingsRepository.load();

      final saving = repo.saveSettings(const GameSettings());
      await store.musicWriteStarted.future;
      try {
        final relaunched = await _relaunch();
        expect(relaunched.settings.analyticsEnabled, isFalse);
      } finally {
        store.release();
        await saving;
      }
    });

    test('overlapping snapshot writes keep the latest selection', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _StallingStore();
      SharedPreferencesStorePlatform.instance = store;
      final repo = await SharedPreferencesSettingsRepository.load();

      // Two switches flipped before the first write lands. Unserialized,
      // the older snapshot's remaining keys overwrite the newer ones — in
      // the plugin's synchronous cache as well as in the store.
      final first = repo.saveSettings(const GameSettings(sfxEnabled: false));
      final second = repo.saveSettings(
        const GameSettings(musicEnabled: false),
      );
      store.release();
      await Future.wait([first, second]);

      final reloaded = await _relaunch();
      expect(reloaded.settings, const GameSettings(musicEnabled: false));
    });

    test('overlapping entitlement writes keep the latest state', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _StallingStore();
      SharedPreferencesStorePlatform.instance = store;
      final repo = await SharedPreferencesSettingsRepository.load();

      // A restore clearing the cache and a purchase granting it, overlapping.
      // Unserialized, the older `false` can land after the newer `true` and
      // the next offline launch shows forced ads to a paying player.
      final cleared = repo.cacheAdsRemoved(removed: false);
      final granted = repo.cacheAdsRemoved(removed: true);
      // Readable before either lands, so the offer never reads the value it
      // is replacing.
      expect(repo.cachedAdsRemoved, isTrue);
      store.release();
      await Future.wait([cleared, granted]);

      final reloaded = await _relaunch();
      expect(reloaded.cachedAdsRemoved, isTrue);
    });

    test('a queued snapshot reads back while its write is in flight', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _StallingStore();
      SharedPreferencesStorePlatform.instance = store;
      final repo = await SharedPreferencesSettingsRepository.load();

      // Reopening Settings before a slow write lands must show the choice
      // the player just made, not the snapshot it is replacing — the page
      // seeds itself from this getter and saves whatever it was seeded with.
      const chosen = GameSettings(musicEnabled: false);
      final saving = repo.saveSettings(chosen);
      expect(repo.settings, chosen);

      store.release();
      await saving;
      expect(repo.settings, chosen);
    });

    test('overlapping high-score writes leave the higher one stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _StallingStore();
      SharedPreferencesStorePlatform.instance = store;
      final repo = await SharedPreferencesSettingsRepository.load();

      // Two record runs finalize before the first write lands. Unserialized,
      // the earlier lower score reaches the store last and the next launch
      // restores a high score the player already beat.
      final first = repo.saveHighScore(1200);
      final second = repo.saveHighScore(3400);
      store.release();
      await Future.wait([first, second]);

      expect(repo.highScore, 3400);
      final reloaded = await _relaunch();
      expect(reloaded.highScore, 3400);
    });
  });
}
