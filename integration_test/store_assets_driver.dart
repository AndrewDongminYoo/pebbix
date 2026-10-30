// 🎯 Dart imports:
import 'dart:io';

// 📦 Package imports:
import 'package:integration_test/integration_test_driver_extended.dart';

// 🌎 Project imports:
import '../tool/store_assets/store_assets.dart';

Future<void> main() async {
  final config = DriverOutputConfig.fromEnvironment(
    environment: Platform.environment,
    repositoryRoot: Directory.current.absolute.path,
  );
  final writer = ScreenshotWriter(config);
  await integrationDriver(
    onScreenshot: (name, bytes, [_]) async {
      await writer.write(name, bytes);
      return true;
    },
    responseDataCallback: null,
  );
}
