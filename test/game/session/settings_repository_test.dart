// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';

void main() {
  group(GameSettings, () {
    test('props carry the settings and opt-in analytics choice', () {
      const settings = GameSettings(musicEnabled: false);
      expect(settings.props, [false, true, true, false]);
    });

    test('copyWith keeps every unspecified field', () {
      const settings = GameSettings(
        musicEnabled: false,
        sfxEnabled: false,
        hapticsEnabled: false,
      );
      final same = settings.copyWith();
      expect(same.props, settings.props);

      final flipped = settings.copyWith(hapticsEnabled: true);
      expect(flipped.props, [false, false, true, false]);

      final optedIn = settings.copyWith(analyticsEnabled: true);
      expect(optedIn.analyticsEnabled, isTrue);
      expect(optedIn.copyWith(musicEnabled: true).analyticsEnabled, isTrue);
    });
  });

  group(InMemorySettingsRepository, () {
    test('starts on spec defaults and persists every surface', () async {
      final repo = InMemorySettingsRepository();
      expect(repo.settings, const GameSettings());
      expect(repo.highScore, 0);
      expect(repo.tutorialSeen, isFalse);
      expect(repo.cachedAdsRemoved, isFalse);

      await repo.saveSettings(const GameSettings(sfxEnabled: false));
      await repo.saveHighScore(12480);
      await repo.markTutorialSeen();
      await repo.cacheAdsRemoved(removed: true);

      expect(repo.settings.sfxEnabled, isFalse);
      expect(repo.highScore, 12480);
      expect(repo.tutorialSeen, isTrue);
      expect(repo.cachedAdsRemoved, isTrue);
    });

    test('seeded state is readable before any write', () {
      final repo = InMemorySettingsRepository(
        settings: const GameSettings(musicEnabled: false),
        highScore: 990,
        tutorialSeen: true,
        cachedAdsRemoved: true,
      );
      expect(repo.settings.musicEnabled, isFalse);
      expect(repo.highScore, 990);
      expect(repo.tutorialSeen, isTrue);
      expect(repo.cachedAdsRemoved, isTrue);
    });
  });
}
