import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubble_shooter/game/session/firebase_crash_reporter.dart';

void main() {
  test('installed handlers forward framework and uncaught async errors', () async {
    final previousFlutterHandler = FlutterError.onError;
    final previousAsyncHandler = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutterHandler;
      PlatformDispatcher.instance.onError = previousAsyncHandler;
    });
    FlutterError.onError = (_) {};
    final recorded = <(Object, bool)>[];
    FirebaseCrashReporter(
      recordFlutterFatal: (details) async => recorded.add((details.exception, true)),
      recordError: (error, stackTrace, {required fatal}) async => recorded.add((error, fatal)),
    ).install();

    final frameworkError = StateError('framework');
    final asyncError = StateError('async');
    FlutterError.reportError(FlutterErrorDetails(exception: frameworkError));
    expect(PlatformDispatcher.instance.onError?.call(asyncError, StackTrace.current), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(recorded, [(frameworkError, true), (asyncError, true)]);
  });

  test('routes framework, async, and explicit nonfatal errors once', () async {
    final fatalFlutter = <Object>[];
    final recorded = <(Object, bool)>[];
    final reporter = FirebaseCrashReporter(
      recordFlutterFatal: (details) async {
        fatalFlutter.add(details.exception);
      },
      recordError: (error, stackTrace, {required fatal}) async {
        recorded.add((error, fatal));
      },
    );
    final frameworkError = StateError('framework');
    final asyncError = StateError('async');
    final nonfatalError = StateError('nonfatal');

    reporter.reportFramework(FlutterErrorDetails(exception: frameworkError));
    expect(reporter.reportAsync(asyncError, StackTrace.current), isTrue);
    reporter.reportNonFatal(nonfatalError, StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(fatalFlutter, [frameworkError]);
    expect(recorded, [(asyncError, true), (nonfatalError, false)]);
  });

  test('a failed Crashlytics call does not throw into gameplay', () async {
    final reporter = FirebaseCrashReporter(
      recordFlutterFatal: (_) async => throw StateError('offline'),
      recordError: (error, stackTrace, {required fatal}) async => throw StateError('offline'),
    );

    expect(() => reporter.reportNonFatal(StateError('game'), StackTrace.current), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });
}
