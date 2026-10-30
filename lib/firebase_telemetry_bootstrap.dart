// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:bloc/bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/app_bloc_observer.dart';
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/firebase_crash_reporter.dart';
import 'package:bubble_shooter/production_telemetry.dart';

/// Native production wiring with seams for platform and SDK startup checks.
Future<AnalyticsSink> createProductionTelemetry({
  required bool analyticsEnabled,
  bool? supportedPlatform,
  Future<void> Function()? initialize,
  Future<void> Function()? activateCrashlytics,
  AnalyticsSink Function()? createAnalytics,
  void Function()? installCrashHandlers,
  FirebaseCrashReporter? crashReporter,
}) {
  final isSupported = supportedPlatform ?? _supportsFirebase;
  if (!isSupported) {
    return Future<AnalyticsSink>.value(const AnalyticsSink());
  }

  return startFirebaseTelemetry(
    initialize: initialize ?? _initializeNativeFirebase,
    activateCrashlytics: activateCrashlytics ?? (initialize == null ? _activateNativeCrashlytics : null),
    createAnalytics: createAnalytics ?? () => const AnalyticsSink(),
    installCrashHandlers:
        installCrashHandlers ?? () => installProductionCrashHandlers(crashReporter ?? FirebaseCrashReporter()),
    analyticsEnabled: analyticsEnabled,
  );
}

bool get _supportsFirebase =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

// coverage:ignore-start
Future<void> _initializeNativeFirebase() async {
  await Firebase.initializeApp();
}

Future<void> _activateNativeCrashlytics() => FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
// coverage:ignore-end

void installProductionCrashHandlers(FirebaseCrashReporter reporter) {
  reporter.install();
  final observer = Bloc.observer;
  if (observer is AppBlocObserver) {
    observer.reportNonFatal = reporter.reportNonFatal;
  } else {
    Bloc.observer = AppBlocObserver(reportNonFatal: reporter.reportNonFatal);
  }
}
