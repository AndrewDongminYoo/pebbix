// 🎯 Dart imports:
import 'dart:convert';
import 'dart:io';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

const _script = 'ios/scripts/admob_app_id.sh';
const _sampleAppId = 'ca-app-pub-3940256099942544~1458002511';
const _appId = 'ca-app-pub-1234567890123456~1234567890';
const _rewarded = 'ca-app-pub-1234567890123456/1111111111';
const _interstitial = 'ca-app-pub-1234567890123456/2222222222';

const Map<String, String> _allDefines = {
  'ADMOB_APP_ID': _appId,
  'ADMOB_REWARDED_AD_UNIT_ID': _rewarded,
  'ADMOB_INTERSTITIAL_AD_UNIT_ID': _interstitial,
};

/// Runs the script the way the Xcode build phase does, with the build settings it reads.
///
/// [defines] is encoded the way flutter_tools writes `DART_DEFINES` into Generated.xcconfig.
/// [pathPrefix] puts a directory in front of `PATH`, to swap in a different `base64`.
ProcessResult _run({required String configuration, Map<String, String>? defines, String? pathPrefix}) {
  final environment = {'CONFIGURATION': configuration};
  if (defines != null) {
    environment['DART_DEFINES'] = [
      for (final MapEntry(:key, :value) in defines.entries) base64.encode(utf8.encode('$key=$value')),
    ].join(',');
  }
  if (pathPrefix != null) {
    environment['PATH'] = '$pathPrefix:${Platform.environment['PATH']}';
  }
  return Process.runSync('sh', [_script], environment: environment);
}

/// A `base64` that, like macOS's, decodes with `-D` and refuses GNU's `--decode`.
Directory _macStyleBase64() {
  final realBase64 = (Process.runSync('sh', ['-c', 'command -v base64']).stdout as String).trim();
  final directory = Directory.systemTemp.createTempSync('admob_app_id_base64_');
  addTearDown(() => directory.delete(recursive: true));
  final stub = File('${directory.path}/base64')
    ..writeAsStringSync('''
#!/bin/sh
[ "\$1" = -D ] || { echo "base64: unrecognized option: \$1" >&2; exit 64; }
exec '$realBase64' -d
''');
  Process.runSync('chmod', ['+x', stub.path]);
  return directory;
}

void _expectAppId(ProcessResult result, String appId) {
  expect(result.stderr, isEmpty);
  expect(result.exitCode, 0);
  expect(result.stdout, '$appId\n');
}

void _expectError(ProcessResult result, String message) {
  expect(result.exitCode, isNot(0));
  expect(result.stdout, isEmpty);
  expect(result.stderr, 'error: $message\n');
}

void main() {
  group('admob_app_id.sh', () {
    test('keeps the sample ID for every configuration but Release-production', () {
      for (final configuration in [
        'Debug-production',
        'Profile-production',
        'Release-development',
        'Release-staging',
      ]) {
        _expectAppId(_run(configuration: configuration, defines: _allDefines), _sampleAppId);
      }
    });

    test('keeps the sample ID for a production release without AdMob defines', () {
      _expectAppId(_run(configuration: 'Release-production'), _sampleAppId);
      _expectAppId(
        _run(configuration: 'Release-production', defines: {'FLUTTER_APP_FLAVOR': 'production'}),
        _sampleAppId,
      );
    });

    test('carries the real ID when a production release has every AdMob define', () {
      _expectAppId(
        _run(configuration: 'Release-production', defines: {'FLUTTER_APP_FLAVOR': 'production', ..._allDefines}),
        _appId,
      );
    });

    test("decodes the defines with a macOS-style base64 that refuses GNU's --decode", () {
      _expectAppId(
        _run(configuration: 'Release-production', defines: _allDefines, pathPrefix: _macStyleBase64().path),
        _appId,
      );
    });

    test('rejects a production release that is missing some AdMob defines', () {
      _expectError(
        _run(configuration: 'Release-production', defines: {'ADMOB_APP_ID': _appId}),
        'A production release needs all AdMob dart-defines; '
        'missing: ADMOB_REWARDED_AD_UNIT_ID, ADMOB_INTERSTITIAL_AD_UNIT_ID.',
      );
      _expectError(
        _run(
          configuration: 'Release-production',
          defines: {'ADMOB_REWARDED_AD_UNIT_ID': _rewarded, 'ADMOB_INTERSTITIAL_AD_UNIT_ID': _interstitial},
        ),
        'A production release needs all AdMob dart-defines; missing: ADMOB_APP_ID.',
      );
    });

    test('rejects an application ID that is not in AdMob form', () {
      _expectError(
        _run(configuration: 'Release-production', defines: {..._allDefines, 'ADMOB_APP_ID': _rewarded}),
        'ADMOB_APP_ID is not an AdMob application ID: $_rewarded',
      );
    });

    test('rejects unit IDs that carry the publisher but are not in AdMob form', () {
      _expectError(
        _run(
          configuration: 'Release-production',
          defines: {..._allDefines, 'ADMOB_REWARDED_AD_UNIT_ID': 'ca-app-pub-1234567890123456/not-a-unit'},
        ),
        'ADMOB_REWARDED_AD_UNIT_ID is not an AdMob ad unit ID: ca-app-pub-1234567890123456/not-a-unit',
      );
      _expectError(
        _run(
          configuration: 'Release-production',
          defines: {..._allDefines, 'ADMOB_INTERSTITIAL_AD_UNIT_ID': 'ca-app-pub-1234567890123456/'},
        ),
        'ADMOB_INTERSTITIAL_AD_UNIT_ID is not an AdMob ad unit ID: ca-app-pub-1234567890123456/',
      );
    });

    test("rejects Google's sample publisher as the production ID", () {
      _expectError(
        _run(
          configuration: 'Release-production',
          defines: {
            'ADMOB_APP_ID': _sampleAppId,
            'ADMOB_REWARDED_AD_UNIT_ID': 'ca-app-pub-3940256099942544/1712485313',
            'ADMOB_INTERSTITIAL_AD_UNIT_ID': 'ca-app-pub-3940256099942544/4411468910',
          },
        ),
        "ADMOB_APP_ID is Google's sample publisher, not this app's AdMob account.",
      );
    });

    test('rejects unit IDs from another AdMob account', () {
      _expectError(
        _run(
          configuration: 'Release-production',
          defines: {..._allDefines, 'ADMOB_INTERSTITIAL_AD_UNIT_ID': 'ca-app-pub-3940256099942544/4411468910'},
        ),
        'ADMOB_INTERSTITIAL_AD_UNIT_ID must belong to the ADMOB_APP_ID publisher ca-app-pub-1234567890123456.',
      );
    });

    test('rejects a DART_DEFINES entry that is not base64', () {
      final result = Process.runSync(
        'sh',
        [_script],
        environment: {'CONFIGURATION': 'Release-production', 'DART_DEFINES': 'not*base64'},
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('error: DART_DEFINES holds an entry that is not base64: not*base64'));
    });
  });
}
