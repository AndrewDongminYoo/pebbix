// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what the app would ask the platform to open.
///
/// Installed in place of the real launcher so a widget test can tap the
/// policy row without a browser opening on the test host, and so the
/// assertion is about the URL that reached the platform rather than about a
/// callback having fired.
class FakeUrlLauncher extends Fake with MockPlatformInterfaceMixin implements UrlLauncherPlatform {
  new _();

  /// Installs this fake for one test and restores the previous instance
  /// afterwards, so a test that never touches a link is unaffected.
  factory install() {
    final previous = UrlLauncherPlatform.instance;
    final fake = FakeUrlLauncher._();
    UrlLauncherPlatform.instance = fake;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    return fake;
  }

  final opened = <String>[];

  /// Set false to make the platform refuse, the way a device with no browser
  /// or a blocked scheme would.
  bool succeeds = true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return succeeds;
  }

  @override
  Future<bool> canLaunch(String url) async => succeeds;
}
