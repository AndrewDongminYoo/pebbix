// 🎯 Dart imports:
import 'dart:async';
import 'dart:developer';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

typedef RecordFlutterFatal = Future<void> Function(FlutterErrorDetails details);
typedef RecordCrashError = Future<void> Function(Object error, StackTrace stackTrace, {required bool fatal});

Future<void> _sendFlutterFatalToSdk(FlutterErrorDetails details) => // coverage:ignore-line
    FirebaseCrashlytics.instance.recordFlutterFatalError(details); // coverage:ignore-line
Future<void> _sendCrashErrorToSdk(Object error, StackTrace stackTrace, {required bool fatal}) => // coverage:ignore-line
    FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: fatal); // coverage:ignore-line

/// Keeps error reporting best-effort, including when Crashlytics is offline.
class FirebaseCrashReporter {
  new({RecordFlutterFatal? recordFlutterFatal, RecordCrashError? recordError})
    : _recordFlutterFatal = recordFlutterFatal ?? _sendFlutterFatalToSdk,
      _recordError = recordError ?? _sendCrashErrorToSdk;

  final RecordFlutterFatal _recordFlutterFatal;
  final RecordCrashError _recordError;

  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      reportFramework(details);
    };
    PlatformDispatcher.instance.onError = reportAsync;
  }

  void reportFramework(FlutterErrorDetails details) {
    _send(() => _recordFlutterFatal(details));
  }

  bool reportAsync(Object error, StackTrace stackTrace) {
    log('Uncaught async error', error: error, stackTrace: stackTrace);
    _send(() => _recordError(error, stackTrace, fatal: true));
    return true;
  }

  void reportNonFatal(Object error, StackTrace stackTrace) {
    _send(() => _recordError(error, stackTrace, fatal: false));
  }

  void _send(Future<void> Function() record) {
    unawaited(
      Future<void>.sync(record).catchError((Object error, StackTrace stackTrace) {
        log('Crashlytics report failed', error: error, stackTrace: stackTrace);
      }),
    );
  }
}
