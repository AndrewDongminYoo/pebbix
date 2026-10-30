// 🌎 Project imports:
import 'package:bubble_shooter/app/app.dart';
import 'package:bubble_shooter/bootstrap.dart';
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/production_services.dart';

Future<void> main() async {
  await bootstrap(() async {
    final setup = adSetupFor(AppFlavor.production);
    final services = await loadProductionServices();
    final gateways = createGateways(setup);
    return App(
      settings: services.settings,
      consent: gateways.consent,
      ads: gateways.ads,
      entitlements: createEntitlements(setup, settings: services.settings, analytics: services.analytics),
      analytics: services.analytics,
    );
  });
}
