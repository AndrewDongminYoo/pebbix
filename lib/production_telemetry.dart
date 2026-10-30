// 🎯 Dart imports:
import 'dart:async';
import 'dart:developer';

// 🐦 Flutter imports:
// 🌎 Project imports:
import 'package:bubble_shooter/game/session/analytics_sink.dart';

/// A local SDK failure must not prevent the title screen from opening.
Future<AnalyticsSink> startFirebaseTelemetry({
  required Future<void> Function() initialize,
  required AnalyticsSink Function() createAnalytics,
  required void Function() installCrashHandlers,
  Future<void> Function()? activateCrashlytics,
  bool analyticsEnabled = false,
  Duration timeout = const Duration(seconds: 3),
  Duration Function()? elapsed,
}) async {
  final startup = Stopwatch()..start();
  try {
    final initialization = initialize();
    try {
      await initialization.timeout(timeout);
    } on TimeoutException {
      unawaited(_activateAfterLateInitialization(initialization, installCrashHandlers, activateCrashlytics, timeout));
      rethrow;
    }
    installCrashHandlers();
    final sink = createAnalytics();
    if (sink is AnalyticsCollectionControl) {
      try {
        final remaining = timeout - (elapsed?.call() ?? startup.elapsed);
        await (sink as AnalyticsCollectionControl)
            .setAnalyticsEnabled(enabled: analyticsEnabled)
            .timeout(remaining.isNegative ? Duration.zero : remaining);
      } on Object catch (error, stackTrace) {
        log('Analytics consent setup unavailable', error: error, stackTrace: stackTrace);
      }
    }
    if (activateCrashlytics != null) {
      final remaining = timeout - (elapsed?.call() ?? startup.elapsed);
      unawaited(_activateCrashlytics(activateCrashlytics, remaining));
    }
    return sink;
  } on Object catch (error, stackTrace) {
    log('Firebase telemetry unavailable', error: error, stackTrace: stackTrace);
    return const AnalyticsSink();
  }
}

Future<void> _activateAfterLateInitialization(
  Future<void> initialization,
  void Function() installCrashHandlers,
  Future<void> Function()? activate,
  Duration timeout,
) async {
  try {
    await initialization;
    installCrashHandlers();
    if (activate != null) {
      await _activateCrashlytics(activate, timeout);
    }
  } on Object catch (error, stackTrace) {
    log('Late Firebase initialization unavailable', error: error, stackTrace: stackTrace);
  }
}

Future<void> _activateCrashlytics(Future<void> Function() activate, Duration remaining) async {
  try {
    await activate().timeout(remaining.isNegative ? Duration.zero : remaining);
  } on Object catch (error, stackTrace) {
    log('Crashlytics collection setup unavailable', error: error, stackTrace: stackTrace);
  }
}
