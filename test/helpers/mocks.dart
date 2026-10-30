// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/loading/loading.dart';

class MockPreloadCubit extends MockCubit<PreloadState> implements PreloadCubit;

class MockAudioCache extends Mock implements AudioCache;

/// Observes the [Navigator] passed to `pumpApp`, so navigation can be
/// asserted without reaching into the destination page.
class MockNavigatorObserver extends Mock implements NavigatorObserver;

/// Fallback for `any(named: 'newRoute')` on [NavigatorObserver] calls;
/// register it with `registerFallbackValue` before stubbing or verifying.
class FakeRoute extends Fake implements Route<void>;
