/// No-op Analytics boundary retained for a future opt-in release.
class AnalyticsSink {
  const new();

  void track(String event, [Map<String, Object?> parameters = const {}]) {}
}

/// Applies the player's separate choice to native Analytics collection.
abstract interface class AnalyticsCollectionControl {
  Future<void> setAnalyticsEnabled({required bool enabled});
}
