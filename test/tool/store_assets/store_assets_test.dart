// 🎯 Dart imports:
import 'dart:convert';
import 'dart:io';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import '../../../tool/store_assets/store_assets.dart';

({Directory outputDirectory, ScreenshotWriter writer}) _writerFixture() {
  final repository = Directory.systemTemp.createTempSync('store_assets_writer_');
  addTearDown(() => repository.delete(recursive: true));
  final outputDirectory = Directory(
    '${repository.path}/build/store_assets/.staging/raw/iphone-6.9/en-US',
  )..createSync(recursive: true);
  final config = DriverOutputConfig.fromEnvironment(
    environment: {
      'STORE_ASSET_DRIVER_OUTPUT_DIR': outputDirectory.path,
      'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
      'STORE_ASSET_DRIVER_LOCALE': 'en-US',
    },
    repositoryRoot: repository.path,
  );
  return (outputDirectory: outputDirectory, writer: ScreenshotWriter(config));
}

const _fixtureGitSha = '0123456789abcdef0123456789abcdef01234567';

Future<({Directory repository, Directory rawDirectory})> _rawMatrixFixture() async {
  final repository = Directory.systemTemp.createTempSync('store_assets_raw_');
  addTearDown(() => repository.delete(recursive: true));
  final rawDirectory = Directory('${repository.path}/build/store_assets/raw');
  for (final profile in StoreAssetProfile.values) {
    final profileDirectory = Directory('${rawDirectory.path}/${profile.id}')..createSync(recursive: true);
    final template = File('${profileDirectory.path}/template.png');
    final generated = Process.runSync('magick', [
      '-size',
      '${profile.physicalWidth}x${profile.physicalHeight}',
      'xc:#123456',
      '-alpha',
      'off',
      'PNG24:${template.path}',
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr as String?);
    final bytes = template.readAsBytesSync();
    template.deleteSync();
    final artifacts = <Map<String, Object?>>[];
    for (final locale in StoreAssetLocale.values) {
      final localeDirectory = Directory('${profileDirectory.path}/${locale.id}')..createSync();
      for (final fileName in sceneFileNames) {
        final file = File('${localeDirectory.path}/$fileName')..writeAsBytesSync(bytes);
        artifacts.add({
          'path': '${locale.id}/$fileName',
          'width': profile.physicalWidth,
          'height': profile.physicalHeight,
          'sha256': await sha256File(file),
        });
      }
    }
    artifacts.sort((left, right) => (left['path']! as String).compareTo(right['path']! as String));
    File('${profileDirectory.path}/capture.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'source_git_sha': _fixtureGitSha,
        'source_dirty': false,
        'device_id': 'fixture-${profile.id}',
        'target_platform': profile.platform == StoreAssetPlatform.ios ? 'ios' : 'android-arm64',
        'profile': profile.id,
        'physical_width': profile.physicalWidth,
        'physical_height': profile.physicalHeight,
        'logical_width': profile.logicalWidth,
        'logical_height': profile.logicalHeight,
        'device_pixel_ratio': profile.devicePixelRatio,
        'captured_locales': StoreAssetLocale.values.map((locale) => locale.id).toList(),
        'artifacts': artifacts,
      })}\n',
    );
  }
  return (repository: repository, rawDirectory: rawDirectory);
}

Future<({Directory repository, Directory finalDirectory})> _finalFixture() async {
  final repository = Directory.systemTemp.createTempSync('store_assets_final_');
  addTearDown(() => repository.delete(recursive: true));
  final finalDirectory = Directory('${repository.path}/build/store_assets/final');
  for (final profile in StoreAssetProfile.values) {
    final profileDirectory = Directory('${finalDirectory.path}/screenshots/${profile.id}')..createSync(recursive: true);
    final template = File('${profileDirectory.path}/template.png');
    final generated = Process.runSync('magick', [
      '-size',
      '${profile.physicalWidth}x${profile.physicalHeight}',
      'xc:#123456',
      '-alpha',
      'off',
      'PNG24:${template.path}',
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr as String?);
    final bytes = template.readAsBytesSync();
    template.deleteSync();
    for (final locale in StoreAssetLocale.values) {
      final localeDirectory = Directory('${profileDirectory.path}/${locale.id}')..createSync();
      for (final fileName in sceneFileNames) {
        File('${localeDirectory.path}/$fileName').writeAsBytesSync(bytes);
      }
    }
  }
  final featureGraphic = File('${finalDirectory.path}/feature-graphic.png');
  final generated = Process.runSync('magick', [
    '-size',
    '1024x500',
    'xc:#123456',
    '-alpha',
    'off',
    'PNG24:${featureGraphic.path}',
  ]);
  expect(generated.exitCode, 0, reason: generated.stderr as String?);
  await writeFinalManifest(finalDirectory: finalDirectory, sourceGitSha: _fixtureGitSha);
  return (repository: repository, finalDirectory: finalDirectory);
}

void main() {
  group('StoreAssetProfile', () {
    test('rejects an unknown device profile', () {
      expect(
        () => StoreAssetProfile.parse('watch'),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Unknown store-asset profile "watch". Expected iphone-6.9, ipad-13, or android-phone.',
          ),
        ),
      );
    });
  });

  group('selectFlutterTarget', () {
    test('rejects an unavailable device identifier', () {
      expect(
        () => selectFlutterTarget(
          devicesJson: '[]',
          deviceId: 'missing-device',
          profile: StoreAssetProfile.iphone69,
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Flutter device "missing-device" is not available.',
          ),
        ),
      );
    });

    test('rejects a target whose platform does not match the profile', () {
      const devicesJson = '''
[
  {
    "name": "Pixel Emulator",
    "id": "android-1",
    "isSupported": true,
    "targetPlatform": "android-x64",
    "emulator": true,
    "sdk": "Android 36",
    "capabilities": {
      "hotReload": true,
      "hotRestart": true,
      "screenshot": true,
      "flutterExit": true,
      "hardwareRendering": true,
      "startPaused": true
    }
  }
]
''';

      expect(
        () => selectFlutterTarget(
          devicesJson: devicesJson,
          deviceId: 'android-1',
          profile: StoreAssetProfile.iphone69,
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Flutter device "android-1" targets "android-x64", but profile "iphone-6.9" requires iOS.',
          ),
        ),
      );
    });

    test('rejects a supported physical device', () {
      const devicesJson = '''
[
  {
    "name": "Physical iPhone",
    "id": "physical-ios",
    "isSupported": true,
    "targetPlatform": "ios",
    "emulator": false
  }
]
''';

      expect(
        () => selectFlutterTarget(
          devicesJson: devicesJson,
          deviceId: 'physical-ios',
          profile: StoreAssetProfile.iphone69,
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Flutter device "physical-ios" is not a Simulator or Emulator.',
          ),
        ),
      );
    });

    test('rejects a listed target that Flutter marks unsupported', () {
      const devicesJson = '''
[
  {
    "name": "Unsupported iPhone",
    "id": "ios-unsupported",
    "isSupported": false,
    "targetPlatform": "ios"
  }
]
''';

      expect(
        () => selectFlutterTarget(
          devicesJson: devicesJson,
          deviceId: 'ios-unsupported',
          profile: StoreAssetProfile.iphone69,
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Flutter device "ios-unsupported" is listed but unsupported.',
          ),
        ),
      );
    });
  });

  group('buildCaptureInvocation', () {
    test('references runnable driver and target entrypoints', () {
      final invocation = buildCaptureInvocation(
        repositoryRoot: Directory.current.absolute.path,
        deviceId: 'simulator-id',
        profile: StoreAssetProfile.iphone69,
        locale: StoreAssetLocale.enUs,
      );
      final driverPath = invocation.arguments[invocation.arguments.indexOf('--driver') + 1];
      final targetPath = invocation.arguments[invocation.arguments.indexOf('--target') + 1];

      expect(File(driverPath).existsSync(), isTrue, reason: 'Missing Flutter drive host entrypoint: $driverPath');
      expect(File(targetPath).existsSync(), isTrue, reason: 'Missing Flutter drive application target: $targetPath');
    });

    test('keeps host output and application defines on separate channels', () {
      final invocation = buildCaptureInvocation(
        repositoryRoot: '/repo',
        deviceId: 'simulator-id',
        profile: StoreAssetProfile.iphone69,
        locale: StoreAssetLocale.korean,
      );

      expect(invocation.executable, 'flutter');
      expect(invocation.arguments, [
        'drive',
        '--debug',
        '--flavor',
        'production',
        '--device-id',
        'simulator-id',
        '--driver',
        'integration_test/store_assets_driver.dart',
        '--target',
        'integration_test/store_assets_test.dart',
        '--dart-define',
        'STORE_ASSET_PROFILE=iphone-6.9',
        '--dart-define',
        'STORE_ASSET_LOCALE=ko',
      ]);
      expect(invocation.environment, {
        'STORE_ASSET_DRIVER_OUTPUT_DIR': '/repo/build/store_assets/.staging/raw/iphone-6.9/ko',
        'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
        'STORE_ASSET_DRIVER_LOCALE': 'ko',
      });
    });
  });

  group('deterministicPngOutputArguments', () {
    test('strips volatile timestamps from repeated compositions', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_deterministic_png_');
      addTearDown(() => directory.delete(recursive: true));
      final hashes = <String>[];

      for (final (name, timestamp) in [
        ('first', '2026-09-01T00:00:00Z'),
        ('second', '2026-09-02T00:00:00Z'),
      ]) {
        final file = File('${directory.path}/$name.png');
        final result = Process.runSync('magick', [
          '-size',
          '8x8',
          'xc:#123456',
          '-set',
          'date:create',
          timestamp,
          '-set',
          'date:modify',
          timestamp,
          ...deterministicPngOutputArguments(file),
        ]);
        expect(result.exitCode, 0, reason: result.stderr as String?);
        await validatePng(file: file, expectedWidth: 8, expectedHeight: 8);
        hashes.add(await sha256File(file));
      }

      expect(hashes[1], hashes[0]);
    });
  });

  group('storeAssetTextLayerArguments', () {
    // The iPhone 6.9 screenshot geometry, not a convenient small one. `-size`
    // is a persistent ImageMagick setting that `( … )` inherits, and the
    // composer sets it to the canvas before appending this layer, so the
    // previous `label:` form fitted the text to the *canvas* and ignored
    // `-pointsize`; `-extent` then cropped a glyph-free region and every
    // screenshot shipped with no headline at all.
    //
    // That only reproduces when the box is smaller than the canvas. A fixture
    // where the two are equal passes on the broken form as well — measured at
    // 320x120/320x120, maximum channel 1.0 either way — so keep these numbers
    // production-shaped, and keep the crop.
    const canvasWidth = 1320;
    const canvasHeight = 2868;
    const boxWidth = 818;
    const boxHeight = 315;
    const boxX = 449;
    const boxY = 43;

    test('draws the headline inside its box at the requested point size', () {
      final directory = Directory.systemTemp.createTempSync('store_assets_text_layer_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/text.png');
      final result = Process.runSync('magick', [
        '-size',
        '${canvasWidth}x$canvasHeight',
        'xc:#0B1226',
        ...storeAssetTextLayerArguments(
          text: 'Aim with Precision',
          font: 'assets/fonts/store_headline_bold.ttf',
          pointSize: 75,
          lineHeight: 1.10,
          x: boxX,
          y: boxY,
          width: boxWidth,
          height: boxHeight,
          gravity: 'West',
        ),
        ...deterministicPngOutputArguments(file),
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String?);
      // Cropped to the headline box: the background is #0B1226, whose maximum
      // channel is 0.149, so anything at or below that is a band with no white
      // ink in it — which is exactly what the broken form produced.
      final maximumChannel = Process.runSync('magick', [
        file.path,
        '-crop',
        '${boxWidth}x$boxHeight+$boxX+$boxY',
        '+repage',
        '-format',
        '%[fx:maxima]',
        'info:',
      ]);
      expect(maximumChannel.exitCode, 0, reason: maximumChannel.stderr as String?);
      expect(double.parse((maximumChannel.stdout as String).trim()), greaterThan(0.9));
    });
  });

  group('DriverOutputConfig', () {
    test('rejects each missing host environment value', () {
      const complete = {
        'STORE_ASSET_DRIVER_OUTPUT_DIR': '/repo/build/store_assets/.staging/raw/iphone-6.9/en-US',
        'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
        'STORE_ASSET_DRIVER_LOCALE': 'en-US',
      };
      for (final variable in complete.keys) {
        final environment = Map<String, String>.of(complete)..remove(variable);
        expect(
          () => DriverOutputConfig.fromEnvironment(
            environment: environment,
            repositoryRoot: '/repo',
          ),
          throwsA(
            isA<StoreAssetException>().having(
              (error) => error.message,
              'message',
              'Missing host environment variable $variable.',
            ),
          ),
        );
      }
    });

    test('rejects an unsupported locale', () {
      expect(
        () => DriverOutputConfig.fromEnvironment(
          environment: const {
            'STORE_ASSET_DRIVER_OUTPUT_DIR': '/repo/build/store_assets/.staging/raw/iphone-6.9/fr',
            'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
            'STORE_ASSET_DRIVER_LOCALE': 'fr',
          },
          repositoryRoot: '/repo',
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Unknown store-asset locale "fr". Expected en-US or ko.',
          ),
        ),
      );
    });

    test('rejects an output path outside the exact locale staging directory', () {
      expect(
        () => DriverOutputConfig.fromEnvironment(
          environment: const {
            'STORE_ASSET_DRIVER_OUTPUT_DIR': '/tmp/out',
            'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
            'STORE_ASSET_DRIVER_LOCALE': 'en-US',
          },
          repositoryRoot: '/repo',
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Invalid driver output directory "/tmp/out". Expected '
                '"/repo/build/store_assets/.staging/raw/iphone-6.9/en-US".',
          ),
        ),
      );
    });

    test('rejects an exact lexical output path with a symlinked ancestor', () {
      final repository = Directory.systemTemp.createTempSync('store_assets_driver_');
      final external = Directory.systemTemp.createTempSync('store_assets_driver_external_');
      addTearDown(() => repository.delete(recursive: true));
      addTearDown(() => external.delete(recursive: true));
      final managedRoot = Directory('${repository.path}/build/store_assets')..createSync(recursive: true);
      Link('${managedRoot.path}/.staging').createSync(external.path);
      final output = '${managedRoot.path}/.staging/raw/iphone-6.9/en-US';

      expect(
        () => DriverOutputConfig.fromEnvironment(
          environment: {
            'STORE_ASSET_DRIVER_OUTPUT_DIR': output,
            'STORE_ASSET_DRIVER_PROFILE': 'iphone-6.9',
            'STORE_ASSET_DRIVER_LOCALE': 'en-US',
          },
          repositoryRoot: repository.path,
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('uses a symbolic link'),
          ),
        ),
      );
      expect(external.listSync(), isEmpty);
    });
  });

  group('ScreenshotWriter', () {
    test('rejects a screenshot name with a path separator', () async {
      final (:outputDirectory, :writer) = _writerFixture();

      await expectLater(
        writer.write('../01-aim.png', [1, 2, 3]),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Unsafe screenshot name "../01-aim.png".',
          ),
        ),
      );
      expect(outputDirectory.listSync(), isEmpty);
    });

    test('rejects a screenshot name outside the stable scene set', () async {
      final (:outputDirectory, :writer) = _writerFixture();

      await expectLater(
        writer.write('06-settings.png', [1, 2, 3]),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Unknown screenshot name "06-settings.png".',
          ),
        ),
      );
      expect(outputDirectory.listSync(), isEmpty);
    });

    test('writes a stable screenshot through a sibling temporary file', () async {
      final (:outputDirectory, :writer) = _writerFixture();
      const bytes = [137, 80, 78, 71, 1, 2, 3];

      await writer.write('01-aim.png', bytes);

      expect(File('${outputDirectory.path}/01-aim.png').readAsBytesSync(), bytes);
      expect(
        outputDirectory.listSync().map((entry) => entry.uri.pathSegments.last).toList(),
        ['01-aim.png'],
      );
    });

    test('rejects a duplicate screenshot name without replacing the first bytes', () async {
      final (:outputDirectory, :writer) = _writerFixture();
      await writer.write('01-aim.png', [1, 2, 3]);

      await expectLater(
        writer.write('01-aim.png', [4, 5, 6]),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Duplicate screenshot name "01-aim.png".',
          ),
        ),
      );
      expect(File('${outputDirectory.path}/01-aim.png').readAsBytesSync(), [1, 2, 3]);
    });

    test('preserves an existing screenshot when the temporary write fails', () async {
      final (:outputDirectory, :writer) = _writerFixture();
      final output = File('${outputDirectory.path}/01-aim.png')..writeAsBytesSync([9, 8, 7]);
      Directory('${outputDirectory.path}/.01-aim.png.tmp').createSync();

      await expectLater(
        writer.write('01-aim.png', [1, 2, 3]),
        throwsA(isA<FileSystemException>()),
      );
      expect(output.readAsBytesSync(), [9, 8, 7]);
    });

    test('rejects a temporary screenshot symlink without touching its external target', () async {
      final (:outputDirectory, :writer) = _writerFixture();
      final externalDirectory = Directory.systemTemp.createTempSync('store_assets_writer_external_');
      addTearDown(() => externalDirectory.delete(recursive: true));
      final external = File('${externalDirectory.path}/sentinel')..writeAsBytesSync([9, 8, 7]);
      Link('${outputDirectory.path}/.01-aim.png.tmp').createSync(external.path);

      await expectLater(
        writer.write('01-aim.png', [1, 2, 3]),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('uses a symbolic link'),
          ),
        ),
      );
      expect(external.readAsBytesSync(), [9, 8, 7]);
      expect(File('${outputDirectory.path}/01-aim.png').existsSync(), isFalse);
    });
  });

  group('replaceManagedDirectory', () {
    test('preserves the current target and removes failed staging output', () async {
      final repository = Directory.systemTemp.createTempSync('store_assets_staging_');
      addTearDown(() => repository.delete(recursive: true));
      final target = Directory('${repository.path}/build/store_assets/final')..createSync(recursive: true);
      File('${target.path}/existing.txt').writeAsStringSync('original');
      final staging = Directory('${repository.path}/build/store_assets/.staging/final');

      await expectLater(
        replaceManagedDirectory(
          repositoryRoot: repository.path,
          stagingDirectory: staging,
          targetDirectory: target,
          build: (directory) async {
            File('${directory.path}/new.txt').writeAsStringSync('new');
          },
          validate: (_) async => throw const StoreAssetException('staged validation failed'),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'staged validation failed',
          ),
        ),
      );
      expect(File('${target.path}/existing.txt').readAsStringSync(), 'original');
      expect(staging.existsSync(), isFalse);
    });

    test('removes stale staging before a later invocation', () async {
      final repository = Directory.systemTemp.createTempSync('store_assets_staging_');
      addTearDown(() => repository.delete(recursive: true));
      final target = Directory('${repository.path}/build/store_assets/raw/iphone-6.9');
      final staging = Directory('${repository.path}/build/store_assets/.staging/raw/iphone-6.9')
        ..createSync(recursive: true);
      File('${staging.path}/stale.txt').writeAsStringSync('stale');

      await replaceManagedDirectory(
        repositoryRoot: repository.path,
        stagingDirectory: staging,
        targetDirectory: target,
        build: (directory) async {
          expect(File('${directory.path}/stale.txt').existsSync(), isFalse);
          File('${directory.path}/fresh.txt').writeAsStringSync('fresh');
        },
        validate: (_) async {},
      );

      expect(File('${target.path}/fresh.txt').readAsStringSync(), 'fresh');
      expect(File('${target.path}/stale.txt').existsSync(), isFalse);
    });

    test('rejects a destructive target outside the managed root', () async {
      final repository = Directory.systemTemp.createTempSync('store_assets_staging_');
      addTearDown(() => repository.delete(recursive: true));
      final outside = Directory('${repository.path}/outside')..createSync();
      final protected = File('${outside.path}/protected.txt')..writeAsStringSync('keep');

      await expectLater(
        replaceManagedDirectory(
          repositoryRoot: repository.path,
          stagingDirectory: Directory('${repository.path}/build/store_assets/.staging/final'),
          targetDirectory: outside,
          build: (_) async {},
          validate: (_) async {},
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('is outside the managed store-asset root'),
          ),
        ),
      );
      expect(protected.readAsStringSync(), 'keep');
    });

    test('rejects a symlinked staging ancestor without touching its external target', () async {
      final repository = Directory.systemTemp.createTempSync('store_assets_staging_');
      final external = Directory.systemTemp.createTempSync('store_assets_external_');
      addTearDown(() => repository.delete(recursive: true));
      addTearDown(() => external.delete(recursive: true));
      final managedRoot = Directory('${repository.path}/build/store_assets')..createSync(recursive: true);
      final externalStaging = Directory('${external.path}/final')..createSync();
      final sentinel = File('${externalStaging.path}/sentinel.txt')..writeAsStringSync('keep');
      Link('${managedRoot.path}/.staging').createSync(external.path);

      await expectLater(
        replaceManagedDirectory(
          repositoryRoot: repository.path,
          stagingDirectory: Directory('${managedRoot.path}/.staging/final'),
          targetDirectory: Directory('${managedRoot.path}/final'),
          build: (_) async {},
          validate: (_) async {},
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('uses a symbolic link'),
          ),
        ),
      );
      expect(sentinel.readAsStringSync(), 'keep');
    });
  });

  group('HeadlineCatalog', () {
    test('wraps malformed JSON in the store-asset error contract', () {
      expect(
        () => HeadlineCatalog.parse('{'),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            startsWith('Invalid headline catalog: FormatException:'),
          ),
        ),
      );
    });

    test('rejects a missing locale', () {
      expect(
        () => HeadlineCatalog.parse('{"en-US": []}'),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Missing headline locale "ko".',
          ),
        ),
      );
    });

    test('rejects a duplicate scene key within one locale', () {
      final source = jsonEncode({
        'en-US': [
          {'key': 'aim', 'value': 'Aim'},
          {'key': 'aim', 'value': 'Aim again'},
          {'key': 'cluster-drop', 'value': 'Drop'},
          {'key': 'pressure', 'value': 'Pressure'},
          {'key': 'high-score', 'value': 'Score'},
        ],
        'ko': [
          {'key': 'aim', 'value': '조준'},
          {'key': 'bank-shot', 'value': '벽'},
          {'key': 'cluster-drop', 'value': '낙하'},
          {'key': 'pressure', 'value': '압박'},
          {'key': 'high-score', 'value': '점수'},
        ],
      });

      expect(
        () => HeadlineCatalog.parse(source),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Duplicate headline key "aim" for locale "en-US".',
          ),
        ),
      );
    });

    test('rejects a locale with fewer than five entries', () {
      final source = jsonEncode({
        'en-US': [
          {'key': 'aim', 'value': 'Aim'},
          {'key': 'cluster-drop', 'value': 'Drop'},
          {'key': 'pressure', 'value': 'Pressure'},
          {'key': 'high-score', 'value': 'Score'},
        ],
        'ko': [
          {'key': 'aim', 'value': '조준'},
          {'key': 'bank-shot', 'value': '벽'},
          {'key': 'cluster-drop', 'value': '낙하'},
          {'key': 'pressure', 'value': '압박'},
          {'key': 'high-score', 'value': '점수'},
        ],
      });

      expect(
        () => HeadlineCatalog.parse(source),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Headline locale "en-US" has 4 entries. Expected 5.',
          ),
        ),
      );
    });

    test('rejects a locale that replaces a required scene key', () {
      final source = jsonEncode({
        'en-US': [
          {'key': 'aim', 'value': 'Aim'},
          {'key': 'settings', 'value': 'Settings'},
          {'key': 'cluster-drop', 'value': 'Drop'},
          {'key': 'pressure', 'value': 'Pressure'},
          {'key': 'high-score', 'value': 'Score'},
        ],
        'ko': [
          {'key': 'aim', 'value': '조준'},
          {'key': 'bank-shot', 'value': '벽'},
          {'key': 'cluster-drop', 'value': '낙하'},
          {'key': 'pressure', 'value': '압박'},
          {'key': 'high-score', 'value': '점수'},
        ],
      });

      expect(
        () => HeadlineCatalog.parse(source),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Headline locale "en-US" is missing key "bank-shot".',
          ),
        ),
      );
    });

    test('rejects an empty headline value', () {
      final source = jsonEncode({
        'en-US': [
          {'key': 'aim', 'value': 'Aim'},
          {'key': 'bank-shot', 'value': 'Bank'},
          {'key': 'cluster-drop', 'value': 'Drop'},
          {'key': 'pressure', 'value': 'Pressure'},
          {'key': 'high-score', 'value': 'Score'},
        ],
        'ko': [
          {'key': 'aim', 'value': '조준'},
          {'key': 'bank-shot', 'value': '벽'},
          {'key': 'cluster-drop', 'value': '낙하'},
          {'key': 'pressure', 'value': '   '},
          {'key': 'high-score', 'value': '점수'},
        ],
      });

      expect(
        () => HeadlineCatalog.parse(source),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Empty headline value for locale "ko" and key "pressure".',
          ),
        ),
      );
    });

    test('loads the approved English and Korean copy', () {
      final catalog = HeadlineCatalog.parse(
        File('tool/store_assets/headlines.json').readAsStringSync(),
      );

      expect(catalog.values[StoreAssetLocale.enUs], {
        'aim': 'Aim with Precision',
        'bank-shot': 'Bank It Off the Wall',
        'cluster-drop': 'Break the Link. Drop Them All.',
        'pressure': 'Stay Ahead of the Ceiling',
        'high-score': 'Chase a New High Score',
      });
      expect(catalog.values[StoreAssetLocale.korean], {
        'aim': '정확한 각도로 한 번에',
        'bank-shot': '벽을 튕겨 빈틈으로',
        'cluster-drop': '연결을 끊어 한꺼번에',
        'pressure': '내려오는 천장보다 빠르게',
        'high-score': '새로운 최고 점수에 도전',
      });
    });
  });

  group('validateCompositionSources', () {
    /// Every path the validator requires, mirrored as an empty file so a test
    /// can remove exactly one and see which name the failure reports.
    const required = [
      'assets/images/background.png',
      'assets/branding/splash_logo.png',
      'assets/images/bubble_red.png',
      'assets/images/bubble_yellow.png',
      'assets/images/bubble_green.png',
      'assets/images/bubble_blue.png',
      'assets/images/bubble_purple.png',
      'assets/images/bubble_orange.png',
      'assets/fonts/store_headline_bold.ttf',
    ];

    Directory fixture({String? without}) {
      final root = Directory.systemTemp.createTempSync('store_assets_sources_');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final path in required) {
        if (path == without) continue;
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(const []);
      }
      // The catalog is parsed, not merely counted, so this one is copied
      // rather than stubbed.
      File('${root.path}/tool/store_assets/headlines.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(File('tool/store_assets/headlines.json').readAsStringSync());
      return root;
    }

    test('accepts the repository as it ships', () {
      // The generator reads the headline face off disk, so this passing is
      // what says it can run at all. It used to assert the opposite — that
      // the font was missing — which made a green suite evidence the
      // generator refused to start.
      expect(validateCompositionSources(Directory.current.absolute.path).values, isNotEmpty);
    });

    test('names the asset that is missing', () {
      final root = fixture(without: 'assets/fonts/store_headline_bold.ttf');

      expect(
        () => validateCompositionSources(root.path),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Missing composition asset "assets/fonts/store_headline_bold.ttf".'),
          ),
        ),
      );
    });
  });

  group('validateRawMatrix', () {
    test('accepts a complete matrix from one clean source revision', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();

      final sourceGitSha = await validateRawMatrix(
        rawDirectory: rawDirectory,
        currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
      );

      expect(sourceGitSha, _fixtureGitSha);
      expect(repository.existsSync(), isTrue);
    });

    test('rejects an incomplete locale and scene matrix', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();
      File('${rawDirectory.path}/iphone-6.9/ko/05-high-score.png').deleteSync();

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Missing raw artifact "iphone-6.9/ko/05-high-score.png".'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects an unexpected raw PNG', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();
      File('${rawDirectory.path}/iphone-6.9/en-US/06-extra.png').writeAsBytesSync([1, 2, 3]);

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Unexpected raw file "iphone-6.9/en-US/06-extra.png".'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects captures from mixed source revisions', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();
      final manifest = File('${rawDirectory.path}/ipad-13/capture.json');
      final data = jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
      data['source_git_sha'] = 'abcdef0123456789abcdef0123456789abcdef01';
      manifest.writeAsStringSync(jsonEncode(data));

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Raw captures use mixed source Git revisions.'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a capture manifest stored under the wrong profile', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();
      File('${rawDirectory.path}/ipad-13/capture.json').writeAsStringSync(
        File('${rawDirectory.path}/iphone-6.9/capture.json').readAsStringSync(),
      );

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Capture manifest under "ipad-13" declares profile "iphone-6.9".',
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a dirty composition checkout', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: true),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'The source worktree is dirty.',
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a composition checkout at a different revision', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(
            sha: 'abcdef0123456789abcdef0123456789abcdef01',
            dirty: false,
          ),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Current Git HEAD does not match raw capture revision'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects raw bytes that do not match the capture hash', () async {
      final (:rawDirectory, :repository) = await _rawMatrixFixture();
      final file = File('${rawDirectory.path}/android-phone/ko/01-aim.png');
      final replaced = Process.runSync('magick', [
        '-size',
        '1080x1920',
        'xc:#654321',
        '-alpha',
        'off',
        'PNG24:${file.path}',
      ]);
      expect(replaced.exitCode, 0, reason: replaced.stderr as String?);

      await expectLater(
        validateRawMatrix(
          rawDirectory: rawDirectory,
          currentSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Raw artifact hash mismatch for "android-phone/ko/01-aim.png".'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });
  });

  group('verifyFinalArtifacts', () {
    test('rejects a dirty source after staged final verification', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      File('${finalDirectory.path}/manifest.json').deleteSync();

      await expectLater(
        validateStagedComposition(
          finalDirectory: finalDirectory,
          sourceGitSha: _fixtureGitSha,
          expectedSnapshot: const GitSnapshot(sha: _fixtureGitSha, dirty: false),
          readCurrentSnapshot: () async => const GitSnapshot(sha: _fixtureGitSha, dirty: true),
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'The source worktree is dirty.',
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('accepts exactly 31 deterministic final PNG entries', () async {
      final (:finalDirectory, :repository) = await _finalFixture();

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        completes,
      );

      final manifest =
          jsonDecode(File('${finalDirectory.path}/manifest.json').readAsStringSync()) as Map<String, Object?>;
      final artifacts = (manifest['artifacts']! as List<Object?>).cast<Map<String, Object?>>();
      final paths = artifacts.map((artifact) => artifact['path']! as String).toList();
      expect(paths, orderedEquals([...paths]..sort()));
      expect(paths, hasLength(31));
      expect(manifest, isNot(contains('timestamp')));
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a final manifest from another source revision', () async {
      final (:finalDirectory, :repository) = await _finalFixture();

      await expectLater(
        verifyFinalArtifacts(
          finalDirectory,
          expectedSourceGitSha: 'abcdef0123456789abcdef0123456789abcdef01',
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Final manifest source Git revision mismatch'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a missing manifest entry', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      final file = File('${finalDirectory.path}/manifest.json');
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      (manifest['artifacts']! as List<Object?>).removeLast();
      file.writeAsStringSync(jsonEncode(manifest));

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Final manifest paths do not match the 31 final PNG files.'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a duplicate manifest entry', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      final file = File('${finalDirectory.path}/manifest.json');
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final artifacts = manifest['artifacts']! as List<Object?>;
      artifacts[1] = artifacts.first;
      file.writeAsStringSync(jsonEncode(manifest));

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Final manifest paths do not match the 31 final PNG files.'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects an unsorted manifest', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      final file = File('${finalDirectory.path}/manifest.json');
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final artifacts = manifest['artifacts']! as List<Object?>;
      final first = artifacts.first;
      artifacts[0] = artifacts[1];
      artifacts[1] = first;
      file.writeAsStringSync(jsonEncode(manifest));

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'Final manifest artifacts must be sorted lexicographically by path.',
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects a stale manifest hash', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      final file = File('${finalDirectory.path}/manifest.json');
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final artifacts = manifest['artifacts']! as List<Object?>;
      (artifacts.first! as Map<String, Object?>)['sha256'] = '0' * 64;
      file.writeAsStringSync(jsonEncode(manifest));

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Final artifact hash mismatch for'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });

    test('rejects an unmatched final PNG', () async {
      final (:finalDirectory, :repository) = await _finalFixture();
      File('${finalDirectory.path}/extra.png').writeAsBytesSync(
        File('${finalDirectory.path}/feature-graphic.png').readAsBytesSync(),
      );

      await expectLater(
        verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: _fixtureGitSha),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            contains('Unexpected final file "extra.png".'),
          ),
        ),
      );
      expect(repository.existsSync(), isTrue);
    });
  });

  group('parsePngInfoOutput', () {
    test('rejects an ImageMagick response with the wrong field count', () {
      expect(
        () => parsePngInfoOutput(
          output: 'PNG|1320|2868|8|sRGB',
          filePath: '/tmp/01-aim.png',
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'ImageMagick returned 5 fields for "/tmp/01-aim.png". Expected 6.',
          ),
        ),
      );
    });

    test('rejects a non-integer ImageMagick dimension', () {
      expect(
        () => parsePngInfoOutput(
          output: 'PNG|wide|2868|8|sRGB|srgb',
          filePath: '/tmp/01-aim.png',
        ),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'ImageMagick returned width "wide" for "/tmp/01-aim.png". Expected an integer.',
          ),
        ),
      );
    });
  });

  group('parseMeasuredTextWidth', () {
    test('rejects an empty ImageMagick response', () {
      expect(
        () => parseMeasuredTextWidth(output: '  ', text: 'Aim with precision'),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'ImageMagick returned an empty width for "Aim with precision".',
          ),
        ),
      );
    });

    test('rejects a non-integer ImageMagick response', () {
      expect(
        () => parseMeasuredTextWidth(output: 'wide', text: 'Aim with precision'),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            'ImageMagick returned width "wide" for "Aim with precision". Expected integer pixels.',
          ),
        ),
      );
    });
  });

  group('validateRawPng', () {
    test('rejects the required intentionally incorrect 1x1 fixture', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/01-aim.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:#FF0000',
        '-alpha',
        'off',
        'PNG24:${file.path}',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validateRawPng(file: file, profile: StoreAssetProfile.iphone69),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            allOf(contains(file.path), contains('expected 1320x2868, actual 1x1')),
          ),
        ),
      );
    });

    test('rejects non-PNG bytes saved with a PNG extension', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/not-a-png.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:#FF0000',
        '-alpha',
        'off',
        'JPEG:${file.path}',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validatePng(file: file, expectedWidth: 1, expectedHeight: 1),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            allOf(contains(file.path), contains('expected PNG, actual JPEG')),
          ),
        ),
      );
    });

    test('rejects a PNG with an alpha channel', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/alpha.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:none',
        'PNG32:${file.path}',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validatePng(file: file, expectedWidth: 1, expectedHeight: 1),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            allOf(contains(file.path), contains('expected no alpha channel, actual srgba')),
          ),
        ),
      );
    });

    test('rejects a PNG with a non-8-bit depth', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/depth.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:#FF0000',
        'PNG48:${file.path}',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validatePng(file: file, expectedWidth: 1, expectedHeight: 1),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            allOf(contains(file.path), contains('expected 8, actual 16')),
          ),
        ),
      );
    });

    test('rejects a PNG outside the sRGB color space', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/gray.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:#808080',
        '-colorspace',
        'Gray',
        '-type',
        'Grayscale',
        file.path,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validatePng(file: file, expectedWidth: 1, expectedHeight: 1),
        throwsA(
          isA<StoreAssetException>().having(
            (error) => error.message,
            'message',
            allOf(contains(file.path), contains('expected sRGB, actual Gray')),
          ),
        ),
      );
    });

    test('accepts an 8-bit sRGB PNG without alpha', () async {
      final directory = Directory.systemTemp.createTempSync('store_assets_png_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/valid.png');
      final generated = Process.runSync('magick', [
        '-size',
        '1x1',
        'xc:#FF0000',
        '-alpha',
        'off',
        'PNG24:${file.path}',
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr as String?);

      await expectLater(
        validatePng(file: file, expectedWidth: 1, expectedHeight: 1),
        completes,
      );
    });
  });
}
