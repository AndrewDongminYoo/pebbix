import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubble_shooter/app/app_bloc_observer.dart';
import 'package:bubble_shooter/firebase_telemetry_bootstrap.dart';
import 'package:bubble_shooter/game/session/firebase_crash_reporter.dart';
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/production_services.dart' as production;
import 'package:bubble_shooter/production_telemetry.dart';

void main() {
  test('production installs crash reporting before a settings load failure', () async {
    final calls = <String>[];
    final failure = StateError('settings unavailable');

    await expectLater(
      production.loadProductionServices(
        createTelemetry: ({required analyticsEnabled}) async {
          calls
            ..add('telemetry:$analyticsEnabled')
            ..add('crash-handlers');
          return _ConsentSink();
        },
        loadSettings: () async {
          calls.add('settings');
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(calls, ['telemetry:false', 'crash-handlers', 'settings']);
  });

  test('production does not replay a saved Analytics opt-in in the crash-only release', () async {
    final calls = <String>[];
    final activeSink = _ConsentSink();
    final settings = InMemorySettingsRepository();
    await settings.saveSettings(const GameSettings(analyticsEnabled: true));

    final services = await production.loadProductionServices(
      createTelemetry: ({required analyticsEnabled}) async {
        calls.add('telemetry:$analyticsEnabled');
        return activeSink;
      },
      loadSettings: () async {
        calls.add('settings');
        return settings;
      },
    );

    expect(calls, ['telemetry:false', 'settings']);
    expect(activeSink.choices, isEmpty);
    expect(services.settings, same(settings));
    expect(services.analytics, same(activeSink));
  });

  test('stalled telemetry initialization cannot hold production startup', () async {
    final stalled = Completer<void>();
    final settings = InMemorySettingsRepository();
    var settingsLoaded = false;

    final services = await production
        .loadProductionServices(
          createTelemetry: ({required analyticsEnabled}) => startFirebaseTelemetry(
            initialize: () => stalled.future,
            createAnalytics: () => throw StateError('must not run'),
            installCrashHandlers: () => throw StateError('must not run'),
            timeout: const Duration(milliseconds: 10),
          ),
          loadSettings: () async {
            settingsLoaded = true;
            return settings;
          },
        )
        .timeout(const Duration(milliseconds: 100));

    expect(services.analytics, isNot(isA<AnalyticsCollectionControl>()));
    expect(settingsLoaded, isTrue);
  });

  test('native bootstrap uses the injected SDK boundary and saved choice', () async {
    final activeSink = _ConsentSink();
    final calls = <String>[];

    final sink = await createProductionTelemetry(
      analyticsEnabled: true,
      supportedPlatform: true,
      initialize: () async => calls.add('initialize'),
      activateCrashlytics: () async => calls.add('activate'),
      createAnalytics: () {
        calls.add('analytics');
        return activeSink;
      },
      installCrashHandlers: () => calls.add('crash'),
    );

    expect(sink, same(activeSink));
    expect(activeSink.choices, [true]);
    expect(calls, ['initialize', 'crash', 'analytics', 'activate']);
  });

  test('production default initializes Crashlytics without a native Analytics control', () async {
    final calls = <String>[];

    final sink = await createProductionTelemetry(
      analyticsEnabled: true,
      supportedPlatform: true,
      initialize: () async => calls.add('initialize'),
      activateCrashlytics: () async => calls.add('activate'),
      installCrashHandlers: () => calls.add('crash-handlers'),
    );

    expect(sink.runtimeType, AnalyticsSink);
    expect(sink, isNot(isA<AnalyticsCollectionControl>()));
    expect(() => sink.track('run_start'), returnsNormally);
    expect(calls, ['initialize', 'crash-handlers', 'activate']);
  });

  test('Crashlytics activation failure preserves handlers and Analytics', () async {
    final activeSink = _ConsentSink();
    final calls = <String>[];

    final sink = await createProductionTelemetry(
      analyticsEnabled: true,
      supportedPlatform: true,
      initialize: () async => calls.add('initialize'),
      activateCrashlytics: () async {
        calls.add('activate');
        throw StateError('Crashlytics unavailable');
      },
      createAnalytics: () {
        calls.add('analytics');
        return activeSink;
      },
      installCrashHandlers: () => calls.add('crash-handlers'),
    );

    expect(sink, same(activeSink));
    expect(activeSink.choices, [true]);
    expect(calls, ['initialize', 'crash-handlers', 'analytics', 'activate']);
  });

  test('stalled Crashlytics activation cannot hold the Analytics sink', () async {
    final stalled = Completer<void>();
    final activeSink = _ConsentSink();
    var installed = false;
    final outcome = await Future.any<Object>([
      startFirebaseTelemetry(
        initialize: () async {},
        activateCrashlytics: () => stalled.future,
        createAnalytics: () => activeSink,
        installCrashHandlers: () => installed = true,
        analyticsEnabled: true,
        timeout: const Duration(milliseconds: 100),
      ),
      Future<Object>.delayed(const Duration(milliseconds: 20), () => 'startup delayed'),
    ]);
    stalled.complete();

    expect(outcome, same(activeSink));
    expect(activeSink.choices, [true]);
    expect(installed, isTrue);
  });

  test('native bootstrap skips Firebase on unsupported platforms', () async {
    final sink = await createProductionTelemetry(
      analyticsEnabled: true,
      supportedPlatform: false,
      initialize: () async => throw StateError('must not run'),
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => throw StateError('must not run'),
    );

    expect(sink, isA<AnalyticsSink>());
    expect(sink, isNot(isA<AnalyticsCollectionControl>()));
  });

  test('native bootstrap detects an unsupported host platform', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final sink = await createProductionTelemetry(analyticsEnabled: true);
      expect(sink, isNot(isA<AnalyticsCollectionControl>()));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('startup restores saved Analytics choice before returning its sink', () async {
    final activeSink = _ConsentSink();
    var installed = false;

    final sink = await startFirebaseTelemetry(
      initialize: () async {},
      createAnalytics: () => activeSink,
      installCrashHandlers: () => installed = true,
      analyticsEnabled: true,
    );

    expect(sink, same(activeSink));
    expect(activeSink.choices, [true]);
    expect(installed, isTrue);
  });

  test('successful Firebase startup installs reporting and returns its sink', () async {
    var installed = 0;
    const activeSink = AnalyticsSink();

    final sink = await startFirebaseTelemetry(
      initialize: () async {},
      createAnalytics: () => activeSink,
      installCrashHandlers: () => installed++,
    );

    expect(sink, same(activeSink));
    expect(installed, 1);
  });

  test('failed Firebase startup keeps the app on a no-op sink', () async {
    var installed = false;

    final sink = await startFirebaseTelemetry(
      initialize: () async => throw StateError('offline'),
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => installed = true,
    );

    expect(sink, isA<AnalyticsSink>());
    expect(() => sink.track('run_start'), returnsNormally);
    expect(installed, isFalse);
  });

  test('stalled Firebase startup cannot hold the app indefinitely', () async {
    final stalled = Completer<void>();

    final sink = await startFirebaseTelemetry(
      initialize: () => stalled.future,
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => throw StateError('must not run'),
      timeout: const Duration(milliseconds: 10),
    );

    expect(sink, isA<AnalyticsSink>());
    expect(() => sink.track('run_start'), returnsNormally);
  });

  test('late Firebase initialization still activates Crashlytics', () async {
    final initialization = Completer<void>();
    final calls = <String>[];

    final sink = await startFirebaseTelemetry(
      initialize: () => initialization.future,
      activateCrashlytics: () async => calls.add('activate'),
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => calls.add('handlers'),
      timeout: const Duration(milliseconds: 10),
    );

    expect(sink, isNot(isA<AnalyticsCollectionControl>()));
    expect(calls, isEmpty);
    initialization.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['handlers', 'activate']);
  });

  test('late Firebase initialization failure leaves Crashlytics inactive', () async {
    final initialization = Completer<void>();
    var activations = 0;
    var installations = 0;

    final sink = await startFirebaseTelemetry(
      initialize: () => initialization.future,
      activateCrashlytics: () async => activations++,
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => installations++,
      timeout: const Duration(milliseconds: 10),
    );

    expect(sink, isNot(isA<AnalyticsCollectionControl>()));
    initialization.completeError(StateError('Firebase unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(activations, 0);
    expect(installations, 0);
  });

  test('late Firebase initialization installs handlers without an activation callback', () async {
    final initialization = Completer<void>();
    var installations = 0;

    await startFirebaseTelemetry(
      initialize: () => initialization.future,
      createAnalytics: () => throw StateError('must not run'),
      installCrashHandlers: () => installations++,
      timeout: const Duration(milliseconds: 10),
    );

    expect(installations, 0);
    initialization.complete();
    await Future<void>.delayed(Duration.zero);
    expect(installations, 1);
  });

  test('stalled consent setup cannot hold the app indefinitely', () async {
    final stalled = Completer<void>();
    final activeSink = _StalledConsentSink(stalled.future);
    var installed = false;
    final sink = await startFirebaseTelemetry(
      initialize: () async {},
      createAnalytics: () => activeSink,
      installCrashHandlers: () => installed = true,
      analyticsEnabled: true,
      timeout: const Duration(milliseconds: 10),
    ).timeout(const Duration(milliseconds: 100));

    expect(sink, same(activeSink));
    await (sink as AnalyticsCollectionControl).setAnalyticsEnabled(enabled: false);
    expect(activeSink.withdrawals, 1);
    expect(installed, isTrue);
  });

  test('Firebase initialization and consent setup share one startup budget', () async {
    final stalled = Completer<void>();
    final sink = _StalledConsentSink(stalled.future);
    final outcome = await Future.any<String>([
      startFirebaseTelemetry(
        initialize: () async {},
        createAnalytics: () => sink,
        installCrashHandlers: () {},
        analyticsEnabled: true,
        timeout: const Duration(milliseconds: 10),
        elapsed: () => const Duration(milliseconds: 10),
      ).then((_) => 'telemetry'),
      Future<String>.delayed(const Duration(milliseconds: 5), () => 'deadline'),
    ]);

    expect(outcome, 'telemetry');
  });

  test('production Bloc errors are sent as nonfatal reports', () async {
    final previousObserver = Bloc.observer;
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    final reports = <bool>[];
    final reporter = FirebaseCrashReporter(
      recordError: (_, _, {required fatal}) async => reports.add(fatal),
    );

    try {
      await createProductionTelemetry(
        analyticsEnabled: false,
        supportedPlatform: true,
        initialize: () async {},
        createAnalytics: () => const AnalyticsSink(),
        crashReporter: reporter,
      );
      final bloc = _ErrorCubit()
        ..changeState()
        ..triggerError(StateError('recoverable'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(reports, [false]);
      await bloc.close();
    } finally {
      Bloc.observer = previousObserver;
      FlutterError.onError = previousFlutterHandler;
      PlatformDispatcher.instance.onError = previousPlatformHandler;
    }
  });

  test('late Firebase initialization reports errors from an existing Bloc', () async {
    final previousObserver = Bloc.observer;
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    final initialization = Completer<void>();
    final handlersInstalled = Completer<void>();
    final reports = <bool>[];
    final reporter = FirebaseCrashReporter(
      recordError: (_, _, {required fatal}) async => reports.add(fatal),
    );
    Bloc.observer = AppBlocObserver();

    try {
      await startFirebaseTelemetry(
        initialize: () => initialization.future,
        createAnalytics: () => const AnalyticsSink(),
        installCrashHandlers: () {
          installProductionCrashHandlers(reporter);
          handlersInstalled.complete();
        },
        timeout: const Duration(milliseconds: 10),
      );
      final bloc = _ErrorCubit();
      initialization.complete();
      await handlersInstalled.future;
      bloc.triggerError(StateError('late startup'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);

      expect(reports, [false]);
      await bloc.close();
    } finally {
      Bloc.observer = previousObserver;
      FlutterError.onError = previousFlutterHandler;
      PlatformDispatcher.instance.onError = previousPlatformHandler;
    }
  });
}

class _ConsentSink extends AnalyticsSink implements AnalyticsCollectionControl {
  final choices = <bool>[];

  @override
  Future<void> setAnalyticsEnabled({required bool enabled}) async => choices.add(enabled);
}

class _StalledConsentSink extends AnalyticsSink implements AnalyticsCollectionControl {
  new(this.future);

  final Future<void> future;
  int withdrawals = 0;

  @override
  Future<void> setAnalyticsEnabled({required bool enabled}) {
    if (enabled) return future;
    withdrawals++;
    return Future<void>.value();
  }
}

// ignore: prefer_file_naming_conventions
class _ErrorCubit extends Cubit<int> {
  new() : super(0);

  void changeState() => emit(1);

  void triggerError(Object error, StackTrace stackTrace) => addError(error, stackTrace);
}
