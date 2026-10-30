// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/gen/assets.gen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The platform channel `HapticFeedback` writes to. Mocking it is the seam:
  /// it records what a device would actually be asked to do, rather than what
  /// a wrapper of our own says it asked for.
  late List<String> played;

  void mockPlatform({bool failing = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (
        call,
      ) async {
        if (call.method != 'HapticFeedback.vibrate') return null;
        played.add(call.arguments as String? ?? 'HapticFeedbackType.vibrate');
        if (failing) {
          throw PlatformException(code: 'unavailable', message: 'no vibrator');
        }
        return null;
      },
    );
  }

  setUp(() {
    played = [];
    mockPlatform();
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  group(HapticsGateway, () {
    test('each felt cue vibrates at its own strength', () async {
      final haptics = HapticsGateway(InMemorySettingsRepository())
        ..forCue(Assets.audio.shoot)
        ..forCue(Assets.audio.pop)
        ..forCue(Assets.audio.descent)
        ..forCue(Assets.audio.gameover);
      await Future<void>.delayed(Duration.zero);

      expect(haptics, isNotNull);
      expect(played, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('a cue with no paired feedback stays silent', () async {
      HapticsGateway(InMemorySettingsRepository())
        ..forCue(Assets.audio.background)
        ..forCue(Assets.audio.bomb)
        ..forCue(Assets.audio.rainbow);
      await Future<void>.delayed(Duration.zero);

      expect(played, isEmpty);
    });

    test('a player with haptics off feels nothing', () async {
      final settings = InMemorySettingsRepository();
      await settings.saveSettings(const GameSettings(hapticsEnabled: false));

      HapticsGateway(settings).forCue(Assets.audio.gameover);
      await Future<void>.delayed(Duration.zero);

      expect(played, isEmpty);
    });

    test('turning haptics back on takes effect from the next cue', () async {
      final settings = InMemorySettingsRepository();
      await settings.saveSettings(const GameSettings(hapticsEnabled: false));
      final haptics = HapticsGateway(settings)..forCue(Assets.audio.pop);

      // Nothing rebuilds the gateway when Settings closes, so a stored
      // snapshot taken at construction would leave the toggle inert.
      await settings.saveSettings(const GameSettings());
      haptics.forCue(Assets.audio.pop);
      await Future<void>.delayed(Duration.zero);

      expect(played, ['HapticFeedbackType.lightImpact']);
    });

    test('the paired callback sounds the cue and vibrates with it', () async {
      final sounded = <String>[];
      final play = HapticsGateway(InMemorySettingsRepository()).pairedWith(sounded.add);

      play(Assets.audio.shoot);
      await Future<void>.delayed(Duration.zero);

      expect(sounded, [Assets.audio.shoot]);
      expect(played, ['HapticFeedbackType.selectionClick']);
    });

    test('a silenced hand still hears the cue', () async {
      final settings = InMemorySettingsRepository();
      await settings.saveSettings(const GameSettings(hapticsEnabled: false));
      final sounded = <String>[];

      HapticsGateway(settings).pairedWith(sounded.add)(Assets.audio.pop);
      await Future<void>.delayed(Duration.zero);

      // The two outputs answer to separate settings, so turning haptics off
      // must not take the sound with it.
      expect(sounded, [Assets.audio.pop]);
      expect(played, isEmpty);
    });

    test('a platform without a vibrator does not reach the caller', () async {
      mockPlatform(failing: true);

      // The caller is a mid-frame sound cue and cannot await, so a rejected
      // channel call has to die here rather than surface as an unhandled
      // async error.
      HapticsGateway(InMemorySettingsRepository()).forCue(Assets.audio.shoot);
      await Future<void>.delayed(Duration.zero);

      expect(played, ['HapticFeedbackType.selectionClick']);
    });
  });
}
