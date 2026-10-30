// 🌎 Project imports:
import 'package:bubble_shooter/firebase_telemetry_bootstrap.dart';
import 'package:bubble_shooter/game/session/session.dart';

Future<({SettingsRepository settings, AnalyticsSink analytics})> loadProductionServices({
  Future<AnalyticsSink> Function({required bool analyticsEnabled})? createTelemetry,
  Future<SettingsRepository> Function()? loadSettings,
}) async {
  final analytics = await (createTelemetry ?? createProductionTelemetry)(analyticsEnabled: false);
  final settings = await (loadSettings ?? SharedPreferencesSettingsRepository.load)();
  return (settings: settings, analytics: analytics);
}
