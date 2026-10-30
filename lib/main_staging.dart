// 🌎 Project imports:
import 'package:bubble_shooter/app/app.dart';
import 'package:bubble_shooter/bootstrap.dart';
import 'package:bubble_shooter/game/session/session.dart';

Future<void> main() async {
  await bootstrap(() async {
    final setup = adSetupFor(AppFlavor.staging);
    final gateways = createGateways(setup);
    final settings = await SharedPreferencesSettingsRepository.load();
    const analytics = AnalyticsSink();
    return App(
      settings: settings,
      consent: gateways.consent,
      ads: gateways.ads,
      entitlements: createEntitlements(setup, settings: settings, analytics: analytics),
      analytics: analytics,
    );
  });
}
