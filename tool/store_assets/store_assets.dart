import 'dart:convert';
import 'dart:io';

const sceneKeys = [
  'aim',
  'bank-shot',
  'cluster-drop',
  'pressure',
  'high-score',
];

const sceneFileNames = [
  '01-aim.png',
  '02-bank-shot.png',
  '03-cluster-drop.png',
  '04-pressure.png',
  '05-high-score.png',
];

final class StoreAssetException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

final class FlutterTarget {
  const new({required this.id, required this.targetPlatform});

  final String id;
  final String targetPlatform;
}

final class CaptureInvocation {
  const new({required this.executable, required this.arguments, required this.environment});

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

CaptureInvocation buildCaptureInvocation({
  required String repositoryRoot,
  required String deviceId,
  required StoreAssetProfile profile,
  required StoreAssetLocale locale,
}) => CaptureInvocation(
  executable: 'flutter',
  arguments: [
    'drive',
    '--debug',
    '--flavor',
    'production',
    '--device-id',
    deviceId,
    '--driver',
    'integration_test/store_assets_driver.dart',
    '--target',
    'integration_test/store_assets_test.dart',
    '--dart-define',
    'STORE_ASSET_PROFILE=${profile.id}',
    '--dart-define',
    'STORE_ASSET_LOCALE=${locale.id}',
  ],
  environment: {
    DriverOutputConfig.outputDirectoryVariable: _normalizePath(
      '$repositoryRoot/build/store_assets/.staging/raw/${profile.id}/${locale.id}',
    ),
    DriverOutputConfig.profileVariable: profile.id,
    DriverOutputConfig.localeVariable: locale.id,
  },
);

final class PngInfo {
  const new({
    required this.format,
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorSpace,
    required this.channels,
  });

  final String format;
  final int width;
  final int height;
  final int bitDepth;
  final String colorSpace;
  final String channels;
}

final class GitSnapshot {
  const new({required this.sha, required this.dirty});

  final String sha;
  final bool dirty;
}

final class RawArtifact {
  const new({
    required this.path,
    required this.width,
    required this.height,
    required this.sha256,
  });

  factory fromJson(Object? source) {
    final fields = Map<String, Object?>.from(source! as Map<Object?, Object?>);
    _requireKeys(fields, const {'path', 'width', 'height', 'sha256'}, 'raw artifact');
    return RawArtifact(
      path: fields['path']! as String,
      width: fields['width']! as int,
      height: fields['height']! as int,
      sha256: fields['sha256']! as String,
    );
  }

  final String path;
  final int width;
  final int height;
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': path,
    'width': width,
    'height': height,
    'sha256': sha256,
  };
}

final class CaptureManifest {
  const new({
    required this.sourceGitSha,
    required this.deviceId,
    required this.targetPlatform,
    required this.profile,
    required this.physicalWidth,
    required this.physicalHeight,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.capturedLocales,
    required this.artifacts,
  });

  factory parse(String source) {
    try {
      final fields = Map<String, Object?>.from(jsonDecode(source) as Map<Object?, Object?>);
      _requireKeys(fields, const {
        'schema_version',
        'source_git_sha',
        'source_dirty',
        'device_id',
        'target_platform',
        'profile',
        'physical_width',
        'physical_height',
        'logical_width',
        'logical_height',
        'device_pixel_ratio',
        'captured_locales',
        'artifacts',
      }, 'capture manifest');
      if (fields['schema_version'] != 1) {
        throw const StoreAssetException('Capture manifest schema_version must be 1.');
      }
      if (fields['source_dirty'] != false) {
        throw const StoreAssetException('Capture manifest source_dirty must be false.');
      }
      return CaptureManifest(
        sourceGitSha: fields['source_git_sha']! as String,
        deviceId: fields['device_id']! as String,
        targetPlatform: fields['target_platform']! as String,
        profile: StoreAssetProfile.parse(fields['profile']! as String),
        physicalWidth: fields['physical_width']! as int,
        physicalHeight: fields['physical_height']! as int,
        logicalWidth: fields['logical_width']! as int,
        logicalHeight: fields['logical_height']! as int,
        devicePixelRatio: (fields['device_pixel_ratio']! as num).toDouble(),
        capturedLocales: (fields['captured_locales']! as List<Object?>).cast<String>(),
        artifacts: (fields['artifacts']! as List<Object?>).map(RawArtifact.fromJson).toList(),
      );
    } on StoreAssetException {
      rethrow;
    } on Object catch (error) {
      throw StoreAssetException('Invalid capture manifest: $error');
    }
  }

  final String sourceGitSha;
  final String deviceId;
  final String targetPlatform;
  final StoreAssetProfile profile;
  final int physicalWidth;
  final int physicalHeight;
  final int logicalWidth;
  final int logicalHeight;
  final double devicePixelRatio;
  final List<String> capturedLocales;
  final List<RawArtifact> artifacts;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'source_git_sha': sourceGitSha,
    'source_dirty': false,
    'device_id': deviceId,
    'target_platform': targetPlatform,
    'profile': profile.id,
    'physical_width': physicalWidth,
    'physical_height': physicalHeight,
    'logical_width': logicalWidth,
    'logical_height': logicalHeight,
    'device_pixel_ratio': devicePixelRatio,
    'captured_locales': capturedLocales,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };
}

void _requireKeys(Map<String, Object?> fields, Set<String> expected, String subject) {
  final actual = fields.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw StoreAssetException('Invalid $subject fields. Expected ${expected.toList()..sort()}.');
  }
}

final _gitShaPattern = RegExp(r'^[0-9a-f]{40}$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

Future<String> sha256File(File file) async {
  final result = await Process.run('/usr/bin/shasum', ['-a', '256', file.path]);
  if (result.exitCode != 0) {
    throw StoreAssetException('Failed to hash "${file.path}": ${(result.stderr as String).trim()}');
  }
  final hash = (result.stdout as String).trim().split(RegExp(r'\s+')).first;
  if (!_sha256Pattern.hasMatch(hash)) {
    throw StoreAssetException('Invalid SHA-256 output for "${file.path}".');
  }
  return hash;
}

Future<GitSnapshot> readGitSnapshot(String repositoryRoot) async {
  final head = await Process.run('git', ['-C', repositoryRoot, 'rev-parse', 'HEAD']);
  if (head.exitCode != 0) {
    throw StoreAssetException('Failed to read Git HEAD: ${(head.stderr as String).trim()}');
  }
  final sha = (head.stdout as String).trim();
  if (!_gitShaPattern.hasMatch(sha)) {
    throw StoreAssetException('Invalid Git HEAD "$sha".');
  }
  final status = await Process.run('git', [
    '-C',
    repositoryRoot,
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (status.exitCode != 0) {
    throw StoreAssetException('Failed to read Git worktree status: ${(status.stderr as String).trim()}');
  }
  return GitSnapshot(sha: sha, dirty: (status.stdout as String).trim().isNotEmpty);
}

void requireCleanSnapshot(GitSnapshot snapshot) {
  if (snapshot.dirty) throw const StoreAssetException('The source worktree is dirty.');
}

void requireUnchangedSnapshot({required GitSnapshot expected, required GitSnapshot actual}) {
  requireCleanSnapshot(actual);
  if (actual.sha != expected.sha) {
    throw StoreAssetException('Git HEAD changed during capture: expected ${expected.sha}, actual ${actual.sha}.');
  }
}

Future<String> validateRawMatrix({
  required Directory rawDirectory,
  required GitSnapshot currentSnapshot,
}) async {
  final expectedFiles = <String>{};
  for (final profile in StoreAssetProfile.values) {
    expectedFiles.add('${profile.id}/capture.json');
    for (final locale in StoreAssetLocale.values) {
      for (final fileName in sceneFileNames) {
        expectedFiles.add('${profile.id}/${locale.id}/$fileName');
      }
    }
  }
  final actualFiles = rawDirectory.existsSync()
      ? rawDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => _relativePath(rawDirectory, file))
            .toSet()
      : <String>{};
  for (final path in expectedFiles) {
    if (!actualFiles.contains(path)) {
      throw StoreAssetException('Missing raw artifact "$path".');
    }
  }
  for (final path in actualFiles) {
    if (!expectedFiles.contains(path)) {
      throw StoreAssetException('Unexpected raw file "$path".');
    }
  }

  final captures = <({StoreAssetProfile expectedProfile, CaptureManifest manifest})>[];
  for (final profile in StoreAssetProfile.values) {
    final manifest = CaptureManifest.parse(
      File('${rawDirectory.path}/${profile.id}/capture.json').readAsStringSync(),
    );
    if (manifest.profile != profile) {
      throw StoreAssetException(
        'Capture manifest under "${profile.id}" declares profile "${manifest.profile.id}".',
      );
    }
    captures.add((expectedProfile: profile, manifest: manifest));
  }
  final sourceGitShas = captures.map((capture) => capture.manifest.sourceGitSha).toSet();
  if (sourceGitShas.length != 1) {
    throw const StoreAssetException('Raw captures use mixed source Git revisions.');
  }
  final sourceGitSha = sourceGitShas.single;
  if (!_gitShaPattern.hasMatch(sourceGitSha)) {
    throw const StoreAssetException('Capture source_git_sha must be a 40-character lowercase hexadecimal value.');
  }
  if (currentSnapshot.dirty) {
    throw const StoreAssetException('The source worktree is dirty.');
  }
  if (currentSnapshot.sha != sourceGitSha) {
    throw StoreAssetException(
      'Current Git HEAD does not match raw capture revision: expected $sourceGitSha, actual ${currentSnapshot.sha}.',
    );
  }
  for (final capture in captures) {
    await _validateCaptureManifest(
      manifest: capture.manifest,
      profileDirectory: Directory('${rawDirectory.path}/${capture.expectedProfile.id}'),
    );
  }
  return sourceGitSha;
}

Future<void> _validateCaptureManifest({
  required CaptureManifest manifest,
  required Directory profileDirectory,
}) async {
  final profile = manifest.profile;
  if (manifest.deviceId.isEmpty) {
    throw StoreAssetException('Capture manifest for "${profile.id}" has an empty device_id.');
  }
  if (!profile.platform.accepts(manifest.targetPlatform)) {
    throw StoreAssetException(
      'Capture target "${manifest.targetPlatform}" does not match profile "${profile.id}".',
    );
  }
  if (manifest.physicalWidth != profile.physicalWidth ||
      manifest.physicalHeight != profile.physicalHeight ||
      manifest.logicalWidth != profile.logicalWidth ||
      manifest.logicalHeight != profile.logicalHeight ||
      manifest.devicePixelRatio != profile.devicePixelRatio) {
    throw StoreAssetException('Capture metadata does not match profile "${profile.id}".');
  }
  final expectedLocales = StoreAssetLocale.values.map((locale) => locale.id).toList();
  if (!_sameList(manifest.capturedLocales, expectedLocales)) {
    throw StoreAssetException('Capture locales do not match profile "${profile.id}".');
  }
  final expectedPaths = [
    for (final locale in StoreAssetLocale.values)
      for (final fileName in sceneFileNames) '${locale.id}/$fileName',
  ]..sort();
  final artifactPaths = manifest.artifacts.map((artifact) => artifact.path).toList();
  if (!_sameList(artifactPaths, expectedPaths)) {
    throw StoreAssetException('Capture artifacts are incomplete, duplicated, or unsorted for profile "${profile.id}".');
  }
  for (final artifact in manifest.artifacts) {
    if (artifact.width != profile.physicalWidth || artifact.height != profile.physicalHeight) {
      throw StoreAssetException(
        'Capture artifact dimensions do not match profile "${profile.id}" for "${artifact.path}".',
      );
    }
    if (!_sha256Pattern.hasMatch(artifact.sha256)) {
      throw StoreAssetException('Invalid raw artifact hash for "${profile.id}/${artifact.path}".');
    }
    final file = File('${profileDirectory.path}/${artifact.path}');
    await validateRawPng(file: file, profile: profile);
    if (await sha256File(file) != artifact.sha256) {
      throw StoreAssetException('Raw artifact hash mismatch for "${profile.id}/${artifact.path}".');
    }
  }
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _relativePath(Directory root, File file) => file.path.substring(root.path.length + 1).replaceAll(r'\', '/');

Future<PngInfo> inspectPng(File file) async {
  final result = await Process.run('magick', [
    'identify',
    '-format',
    '%m|%w|%h|%z|%[colorspace]|%[channels]',
    file.path,
  ]);
  if (result.exitCode != 0) {
    throw StoreAssetException(
      'ImageMagick failed to inspect "${file.path}": ${(result.stderr as String).trim()}',
    );
  }
  return parsePngInfoOutput(
    output: result.stdout as String,
    filePath: file.path,
  );
}

PngInfo parsePngInfoOutput({required String output, required String filePath}) {
  final fields = output.trim().split('|');
  if (fields.length != 6) {
    throw StoreAssetException(
      'ImageMagick returned ${fields.length} fields for "$filePath". Expected 6.',
    );
  }
  int parseInteger(int index, String fieldName) {
    final value = fields[index];
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw StoreAssetException('ImageMagick returned $fieldName "$value" for "$filePath". Expected an integer.');
    }
    return parsed;
  }

  return PngInfo(
    format: fields[0],
    width: parseInteger(1, 'width'),
    height: parseInteger(2, 'height'),
    bitDepth: parseInteger(3, 'bit depth'),
    colorSpace: fields[4],
    channels: fields[5],
  );
}

Future<void> validateRawPng({
  required File file,
  required StoreAssetProfile profile,
}) async {
  final info = await inspectPng(file);
  _validatePngFormatAndDimensions(
    file: file,
    info: info,
    expectedWidth: profile.physicalWidth,
    expectedHeight: profile.physicalHeight,
  );
}

Future<PngInfo> validatePng({
  required File file,
  required int expectedWidth,
  required int expectedHeight,
}) async {
  final info = await inspectPng(file);
  _validatePngFormatAndDimensions(
    file: file,
    info: info,
    expectedWidth: expectedWidth,
    expectedHeight: expectedHeight,
  );
  if (info.bitDepth != 8) {
    throw StoreAssetException(
      'Invalid PNG bit depth for "${file.path}": expected 8, actual ${info.bitDepth}.',
    );
  }
  if (info.colorSpace != 'sRGB') {
    throw StoreAssetException(
      'Invalid PNG color space for "${file.path}": expected sRGB, actual ${info.colorSpace}.',
    );
  }
  final channelName = info.channels.toLowerCase().split(' ').first;
  if (channelName.endsWith('a')) {
    throw StoreAssetException(
      'Invalid PNG alpha for "${file.path}": expected no alpha channel, actual ${info.channels}.',
    );
  }
  return info;
}

void _validatePngFormatAndDimensions({
  required File file,
  required PngInfo info,
  required int expectedWidth,
  required int expectedHeight,
}) {
  if (info.format != 'PNG') {
    throw StoreAssetException(
      'Invalid image format for "${file.path}": expected PNG, actual ${info.format}.',
    );
  }
  if (info.width != expectedWidth || info.height != expectedHeight) {
    throw StoreAssetException(
      'Invalid PNG dimensions for "${file.path}": expected ${expectedWidth}x$expectedHeight, '
      'actual ${info.width}x${info.height}.',
    );
  }
}

final class FinalArtifact {
  const new({
    required this.path,
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorSpace,
    required this.hasAlpha,
    required this.sha256,
  });

  factory fromJson(Object? source) {
    final fields = Map<String, Object?>.from(source! as Map<Object?, Object?>);
    _requireKeys(fields, const {
      'path',
      'width',
      'height',
      'bit_depth',
      'color_space',
      'has_alpha',
      'sha256',
    }, 'final artifact');
    return FinalArtifact(
      path: fields['path']! as String,
      width: fields['width']! as int,
      height: fields['height']! as int,
      bitDepth: fields['bit_depth']! as int,
      colorSpace: fields['color_space']! as String,
      hasAlpha: fields['has_alpha']! as bool,
      sha256: fields['sha256']! as String,
    );
  }

  final String path;
  final int width;
  final int height;
  final int bitDepth;
  final String colorSpace;
  final bool hasAlpha;
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': path,
    'width': width,
    'height': height,
    'bit_depth': bitDepth,
    'color_space': colorSpace,
    'has_alpha': hasAlpha,
    'sha256': sha256,
  };
}

final class FinalManifest {
  const new({required this.sourceGitSha, required this.artifacts});

  factory parse(String source) {
    try {
      final fields = Map<String, Object?>.from(jsonDecode(source) as Map<Object?, Object?>);
      _requireKeys(fields, const {'schema_version', 'source_git_sha', 'source_dirty', 'artifacts'}, 'final manifest');
      if (fields['schema_version'] != 1) {
        throw const StoreAssetException('Final manifest schema_version must be 1.');
      }
      if (fields['source_dirty'] != false) {
        throw const StoreAssetException('Final manifest source_dirty must be false.');
      }
      return FinalManifest(
        sourceGitSha: fields['source_git_sha']! as String,
        artifacts: (fields['artifacts']! as List<Object?>).map(FinalArtifact.fromJson).toList(),
      );
    } on StoreAssetException {
      rethrow;
    } on Object catch (error) {
      throw StoreAssetException('Invalid final manifest: $error');
    }
  }

  final String sourceGitSha;
  final List<FinalArtifact> artifacts;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'source_git_sha': sourceGitSha,
    'source_dirty': false,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };
}

List<String> _expectedFinalPngPaths() => [
  'feature-graphic.png',
  for (final profile in StoreAssetProfile.values)
    for (final locale in StoreAssetLocale.values)
      for (final fileName in sceneFileNames) 'screenshots/${profile.id}/${locale.id}/$fileName',
]..sort();

({int width, int height}) _finalDimensions(String path) {
  if (path == 'feature-graphic.png') return (width: 1024, height: 500);
  final segments = path.split('/');
  if (segments.length != 4 || segments.first != 'screenshots') {
    throw StoreAssetException('Unexpected final PNG path "$path".');
  }
  final profile = StoreAssetProfile.parse(segments[1]);
  StoreAssetLocale.parse(segments[2]);
  if (!sceneFileNames.contains(segments[3])) {
    throw StoreAssetException('Unexpected final PNG path "$path".');
  }
  return (width: profile.physicalWidth, height: profile.physicalHeight);
}

Future<void> writeFinalManifest({
  required Directory finalDirectory,
  required String sourceGitSha,
}) async {
  if (!_gitShaPattern.hasMatch(sourceGitSha)) {
    throw const StoreAssetException('Final source_git_sha must be a 40-character lowercase hexadecimal value.');
  }
  final expectedPaths = _expectedFinalPngPaths();
  _validateFinalFileSet(finalDirectory: finalDirectory, expectedPngPaths: expectedPaths, requireManifest: false);
  final artifacts = <FinalArtifact>[];
  for (final path in expectedPaths) {
    final dimensions = _finalDimensions(path);
    final file = File('${finalDirectory.path}/$path');
    final info = await validatePng(
      file: file,
      expectedWidth: dimensions.width,
      expectedHeight: dimensions.height,
    );
    artifacts.add(
      FinalArtifact(
        path: path,
        width: info.width,
        height: info.height,
        bitDepth: info.bitDepth,
        colorSpace: info.colorSpace,
        hasAlpha: false,
        sha256: await sha256File(file),
      ),
    );
  }
  final manifest = FinalManifest(sourceGitSha: sourceGitSha, artifacts: artifacts);
  await File('${finalDirectory.path}/manifest.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    flush: true,
  );
}

Future<void> verifyFinalArtifacts(
  Directory finalDirectory, {
  required String expectedSourceGitSha,
}) async {
  final expectedPaths = _expectedFinalPngPaths();
  _validateFinalFileSet(finalDirectory: finalDirectory, expectedPngPaths: expectedPaths, requireManifest: true);
  final manifest = FinalManifest.parse(File('${finalDirectory.path}/manifest.json').readAsStringSync());
  if (!_gitShaPattern.hasMatch(manifest.sourceGitSha)) {
    throw const StoreAssetException('Final source_git_sha must be a 40-character lowercase hexadecimal value.');
  }
  if (manifest.sourceGitSha != expectedSourceGitSha) {
    throw StoreAssetException(
      'Final manifest source Git revision mismatch: expected $expectedSourceGitSha, '
      'actual ${manifest.sourceGitSha}.',
    );
  }
  final manifestPaths = manifest.artifacts.map((artifact) => artifact.path).toList();
  if (!_sameList(manifestPaths, [...manifestPaths]..sort())) {
    throw const StoreAssetException('Final manifest artifacts must be sorted lexicographically by path.');
  }
  if (!_sameList(manifestPaths, expectedPaths)) {
    throw const StoreAssetException('Final manifest paths do not match the 31 final PNG files.');
  }
  for (final artifact in manifest.artifacts) {
    final dimensions = _finalDimensions(artifact.path);
    if (artifact.width != dimensions.width ||
        artifact.height != dimensions.height ||
        artifact.bitDepth != 8 ||
        artifact.colorSpace != 'sRGB' ||
        artifact.hasAlpha) {
      throw StoreAssetException('Final manifest metadata is invalid for "${artifact.path}".');
    }
    if (!_sha256Pattern.hasMatch(artifact.sha256)) {
      throw StoreAssetException('Invalid final artifact hash for "${artifact.path}".');
    }
    final file = File('${finalDirectory.path}/${artifact.path}');
    await validatePng(
      file: file,
      expectedWidth: dimensions.width,
      expectedHeight: dimensions.height,
    );
    if (await sha256File(file) != artifact.sha256) {
      throw StoreAssetException('Final artifact hash mismatch for "${artifact.path}".');
    }
  }
}

Future<void> validateStagedComposition({
  required Directory finalDirectory,
  required String sourceGitSha,
  required GitSnapshot expectedSnapshot,
  required Future<GitSnapshot> Function() readCurrentSnapshot,
}) async {
  await writeFinalManifest(finalDirectory: finalDirectory, sourceGitSha: sourceGitSha);
  await verifyFinalArtifacts(finalDirectory, expectedSourceGitSha: sourceGitSha);
  requireUnchangedSnapshot(expected: expectedSnapshot, actual: await readCurrentSnapshot());
}

void _validateFinalFileSet({
  required Directory finalDirectory,
  required List<String> expectedPngPaths,
  required bool requireManifest,
}) {
  final expectedFiles = {...expectedPngPaths, if (requireManifest) 'manifest.json'};
  final actualFiles = finalDirectory.existsSync()
      ? finalDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => _relativePath(finalDirectory, file))
            .toSet()
      : <String>{};
  for (final path in expectedFiles) {
    if (!actualFiles.contains(path)) {
      throw StoreAssetException('Missing final file "$path".');
    }
  }
  for (final path in actualFiles) {
    if (!expectedFiles.contains(path)) {
      throw StoreAssetException('Unexpected final file "$path".');
    }
  }
}

final class HeadlineCatalog {
  const new _(this.values);

  factory parse(String source) {
    try {
      final root = Map<String, Object?>.from(jsonDecode(source) as Map<Object?, Object?>);
      for (final locale in StoreAssetLocale.values) {
        if (!root.containsKey(locale.id)) {
          throw StoreAssetException('Missing headline locale "${locale.id}".');
        }
      }
      final values = <StoreAssetLocale, Map<String, String>>{};
      for (final locale in StoreAssetLocale.values) {
        final entries = root[locale.id]! as List<Object?>;
        if (entries.length != sceneKeys.length) {
          throw StoreAssetException(
            'Headline locale "${locale.id}" has ${entries.length} entries. Expected ${sceneKeys.length}.',
          );
        }
        final byKey = <String, String>{};
        for (final entry in entries) {
          final fields = Map<String, Object?>.from(entry! as Map<Object?, Object?>);
          final key = fields['key']! as String;
          if (byKey.containsKey(key)) {
            throw StoreAssetException('Duplicate headline key "$key" for locale "${locale.id}".');
          }
          final value = fields['value']! as String;
          if (value.trim().isEmpty) {
            throw StoreAssetException('Empty headline value for locale "${locale.id}" and key "$key".');
          }
          byKey[key] = value;
        }
        for (final key in sceneKeys) {
          if (!byKey.containsKey(key)) {
            throw StoreAssetException('Headline locale "${locale.id}" is missing key "$key".');
          }
        }
        values[locale] = byKey;
      }
      return HeadlineCatalog._(values);
    } on StoreAssetException {
      rethrow;
    } on Object catch (error) {
      throw StoreAssetException('Invalid headline catalog: $error');
    }
  }

  final Map<StoreAssetLocale, Map<String, String>> values;
}

HeadlineCatalog validateCompositionSources(String repositoryRoot) {
  const requiredAssets = [
    'assets/images/background.png',
    'assets/branding/splash_logo.png',
    'assets/images/bubble_red.png',
    'assets/images/bubble_yellow.png',
    'assets/images/bubble_green.png',
    'assets/images/bubble_blue.png',
    'assets/images/bubble_purple.png',
    'assets/images/bubble_orange.png',
    'tool/store_assets/headlines.json',
    'assets/fonts/store_headline_bold.ttf',
  ];
  for (final path in requiredAssets) {
    if (!File('$repositoryRoot/$path').existsSync()) {
      throw StoreAssetException('Missing composition asset "$path".');
    }
  }
  return HeadlineCatalog.parse(File('$repositoryRoot/tool/store_assets/headlines.json').readAsStringSync());
}

final class DriverOutputConfig {
  const new({
    required this.outputDirectory,
    required this.profile,
    required this.locale,
  });

  factory fromEnvironment({
    required Map<String, String> environment,
    required String repositoryRoot,
  }) {
    String requiredValue(String variable) {
      final value = environment[variable];
      if (value == null || value.isEmpty) {
        throw StoreAssetException('Missing host environment variable $variable.');
      }
      return value;
    }

    final outputDirectory = requiredValue(outputDirectoryVariable);
    final profile = StoreAssetProfile.parse(requiredValue(profileVariable));
    final locale = StoreAssetLocale.parse(requiredValue(localeVariable));
    final normalizedOutput = _normalizePath(outputDirectory);
    final expectedOutput = _normalizePath(
      '$repositoryRoot/build/store_assets/.staging/raw/${profile.id}/${locale.id}',
    );
    if (normalizedOutput != expectedOutput) {
      throw StoreAssetException(
        'Invalid driver output directory "$normalizedOutput". Expected "$expectedOutput".',
      );
    }
    _requireNoSymbolicLinkComponents(
      repositoryRoot,
      normalizedOutput,
      subject: 'Driver output directory',
    );
    return DriverOutputConfig(
      outputDirectory: normalizedOutput,
      profile: profile,
      locale: locale,
    );
  }

  static const outputDirectoryVariable = 'STORE_ASSET_DRIVER_OUTPUT_DIR';
  static const profileVariable = 'STORE_ASSET_DRIVER_PROFILE';
  static const localeVariable = 'STORE_ASSET_DRIVER_LOCALE';

  final String outputDirectory;
  final StoreAssetProfile profile;
  final StoreAssetLocale locale;
}

final class ScreenshotWriter {
  new(this.config);

  final DriverOutputConfig config;
  final _writtenNames = <String>{};

  Future<void> write(String name, List<int> bytes) async {
    if (name.contains('/') || name.contains(r'\')) {
      throw StoreAssetException('Unsafe screenshot name "$name".');
    }
    if (!sceneFileNames.contains(name)) {
      throw StoreAssetException('Unknown screenshot name "$name".');
    }
    if (_writtenNames.contains(name)) {
      throw StoreAssetException('Duplicate screenshot name "$name".');
    }
    final temporary = File('${config.outputDirectory}/.$name.tmp');
    final output = File('${config.outputDirectory}/$name');
    for (final file in [temporary, output]) {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) == FileSystemEntityType.link) {
        throw StoreAssetException('Screenshot path "${file.path}" uses a symbolic link.');
      }
    }
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(output.path);
    _writtenNames.add(name);
  }
}

String _normalizePath(String path) => File(path).absolute.uri.normalizePath().toFilePath();

Future<void> replaceManagedDirectory({
  required String repositoryRoot,
  required Directory stagingDirectory,
  required Directory targetDirectory,
  required Future<void> Function(Directory directory) build,
  required Future<void> Function(Directory directory) validate,
}) async {
  final managedRoot = _normalizePath('$repositoryRoot/build/store_assets');
  _requireManagedDirectory(repositoryRoot, managedRoot, stagingDirectory);
  _requireManagedDirectory(repositoryRoot, managedRoot, targetDirectory);
  if (_normalizePath(stagingDirectory.path) == _normalizePath(targetDirectory.path)) {
    throw const StoreAssetException('The staging and target directories must differ.');
  }
  if (stagingDirectory.existsSync()) {
    await stagingDirectory.delete(recursive: true);
  }
  await stagingDirectory.create(recursive: true);
  var replaced = false;
  try {
    await build(stagingDirectory);
    await validate(stagingDirectory);
    await _replaceDirectory(
      repositoryRoot: repositoryRoot,
      managedRoot: managedRoot,
      stagingDirectory: stagingDirectory,
      targetDirectory: targetDirectory,
    );
    replaced = true;
  } finally {
    if (!replaced && stagingDirectory.existsSync()) {
      await stagingDirectory.delete(recursive: true);
    }
  }
}

void _requireManagedDirectory(String repositoryRoot, String managedRoot, Directory directory) {
  final resolved = _normalizePath(directory.path);
  final prefix = managedRoot.endsWith(Platform.pathSeparator) ? managedRoot : '$managedRoot${Platform.pathSeparator}';
  if (resolved == managedRoot || !resolved.startsWith(prefix)) {
    throw StoreAssetException('Managed directory "$resolved" is outside the managed store-asset root "$managedRoot".');
  }
  _requireNoSymbolicLinkComponents(repositoryRoot, resolved, subject: 'Managed directory');
}

void _requireNoSymbolicLinkComponents(String repositoryRoot, String resolved, {required String subject}) {
  final repository = _normalizePath(repositoryRoot);
  var component = resolved;
  while (component != repository) {
    if (FileSystemEntity.typeSync(component, followLinks: false) == FileSystemEntityType.link) {
      throw StoreAssetException('$subject "$resolved" uses a symbolic link at "$component".');
    }
    final parent = Directory(component).parent.path;
    if (parent == component) break;
    component = parent;
  }
}

Future<void> _replaceDirectory({
  required String repositoryRoot,
  required String managedRoot,
  required Directory stagingDirectory,
  required Directory targetDirectory,
}) async {
  await targetDirectory.parent.create(recursive: true);
  final targetName = targetDirectory.path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;
  final backup = Directory('$managedRoot/.staging/.replacement-$targetName');
  _requireManagedDirectory(repositoryRoot, managedRoot, backup);
  if (backup.existsSync()) await backup.delete(recursive: true);
  final hadTarget = targetDirectory.existsSync();
  if (hadTarget) await targetDirectory.rename(backup.path);
  try {
    await stagingDirectory.rename(targetDirectory.path);
  } on Object {
    if (hadTarget && backup.existsSync()) await backup.rename(targetDirectory.path);
    rethrow;
  }
  if (backup.existsSync()) {
    try {
      await backup.delete(recursive: true);
    } on FileSystemException catch (error) {
      stderr.writeln('Store-asset replacement succeeded, but backup cleanup failed: ${error.message}');
    }
  }
}

enum StoreAssetLocale {
  enUs('en-US'),
  korean('ko');

  new(this.id);

  final String id;

  static StoreAssetLocale parse(String value) {
    for (final locale in values) {
      if (locale.id == value) return locale;
    }
    throw StoreAssetException('Unknown store-asset locale "$value". Expected en-US or ko.');
  }
}

enum StoreAssetPlatform {
  ios('iOS'),
  android('Android');

  new(this.label);

  final String label;

  bool accepts(String targetPlatform) => switch (this) {
    StoreAssetPlatform.ios => targetPlatform == 'ios',
    StoreAssetPlatform.android => targetPlatform.startsWith('android-'),
  };
}

FlutterTarget selectFlutterTarget({
  required String devicesJson,
  required String deviceId,
  required StoreAssetProfile profile,
}) {
  final devices = jsonDecode(devicesJson) as List<Object?>;
  for (final device in devices) {
    final fields = Map<String, Object?>.from(device! as Map<Object?, Object?>);
    if (fields['id'] == deviceId) {
      if (fields['isSupported'] != true) {
        throw StoreAssetException('Flutter device "$deviceId" is listed but unsupported.');
      }
      if (fields['emulator'] != true) {
        throw StoreAssetException('Flutter device "$deviceId" is not a Simulator or Emulator.');
      }
      final targetPlatform = fields['targetPlatform']! as String;
      if (!profile.platform.accepts(targetPlatform)) {
        throw StoreAssetException(
          'Flutter device "$deviceId" targets "$targetPlatform", but profile "${profile.id}" requires '
          '${profile.platform.label}.',
        );
      }
      return FlutterTarget(
        id: fields['id']! as String,
        targetPlatform: targetPlatform,
      );
    }
  }
  throw StoreAssetException('Flutter device "$deviceId" is not available.');
}

enum StoreAssetProfile {
  iphone69('iphone-6.9', StoreAssetPlatform.ios, 1320, 2868, 440, 956, 3),
  ipad13('ipad-13', StoreAssetPlatform.ios, 2064, 2752, 1032, 1376, 2),
  androidPhone('android-phone', StoreAssetPlatform.android, 1080, 1920, 360, 640, 3);

  new(
    this.id,
    this.platform,
    this.physicalWidth,
    this.physicalHeight,
    this.logicalWidth,
    this.logicalHeight,
    this.devicePixelRatio,
  );

  final String id;
  final StoreAssetPlatform platform;
  final int physicalWidth;
  final int physicalHeight;
  final int logicalWidth;
  final int logicalHeight;
  final double devicePixelRatio;

  static StoreAssetProfile parse(String value) {
    for (final profile in values) {
      if (profile.id == value) return profile;
    }
    throw StoreAssetException(
      'Unknown store-asset profile "$value". Expected iphone-6.9, ipad-13, or android-phone.',
    );
  }
}

Future<void> captureStoreAssets({
  required String repositoryRoot,
  required String deviceId,
  required String profileId,
}) async {
  final profile = StoreAssetProfile.parse(profileId);
  final initialSnapshot = await readGitSnapshot(repositoryRoot);
  requireCleanSnapshot(initialSnapshot);
  final devices = await Process.run('flutter', ['devices', '--machine'], workingDirectory: repositoryRoot);
  if (devices.exitCode != 0) {
    throw StoreAssetException('Failed to query Flutter devices: ${(devices.stderr as String).trim()}');
  }
  final target = selectFlutterTarget(
    devicesJson: devices.stdout as String,
    deviceId: deviceId,
    profile: profile,
  );
  final stagingDirectory = Directory('$repositoryRoot/build/store_assets/.staging/raw/${profile.id}');
  final targetDirectory = Directory('$repositoryRoot/build/store_assets/raw/${profile.id}');
  await replaceManagedDirectory(
    repositoryRoot: repositoryRoot,
    stagingDirectory: stagingDirectory,
    targetDirectory: targetDirectory,
    build: (directory) async {
      for (final locale in StoreAssetLocale.values) {
        await Directory('${directory.path}/${locale.id}').create(recursive: true);
        final invocation = buildCaptureInvocation(
          repositoryRoot: repositoryRoot,
          deviceId: deviceId,
          profile: profile,
          locale: locale,
        );
        final result = await Process.run(
          invocation.executable,
          invocation.arguments,
          workingDirectory: repositoryRoot,
          environment: invocation.environment,
        );
        if (result.exitCode != 0) {
          throw StoreAssetException(
            'Flutter capture failed for "${profile.id}/${locale.id}": ${(result.stderr as String).trim()}',
          );
        }
        requireUnchangedSnapshot(expected: initialSnapshot, actual: await readGitSnapshot(repositoryRoot));
      }
      await _writeCaptureManifest(
        profileDirectory: directory,
        sourceGitSha: initialSnapshot.sha,
        deviceId: target.id,
        targetPlatform: target.targetPlatform,
        profile: profile,
      );
    },
    validate: (directory) => validateCapturedProfileDirectory(
      profileDirectory: directory,
      expectedSnapshot: initialSnapshot,
    ),
  );
}

Future<void> _writeCaptureManifest({
  required Directory profileDirectory,
  required String sourceGitSha,
  required String deviceId,
  required String targetPlatform,
  required StoreAssetProfile profile,
}) async {
  final artifacts = <RawArtifact>[];
  for (final locale in StoreAssetLocale.values) {
    for (final fileName in sceneFileNames) {
      final file = File('${profileDirectory.path}/${locale.id}/$fileName');
      if (!file.existsSync()) {
        throw StoreAssetException('Missing raw artifact "${profile.id}/${locale.id}/$fileName".');
      }
      await validateRawPng(file: file, profile: profile);
      artifacts.add(
        RawArtifact(
          path: '${locale.id}/$fileName',
          width: profile.physicalWidth,
          height: profile.physicalHeight,
          sha256: await sha256File(file),
        ),
      );
    }
  }
  artifacts.sort((left, right) => left.path.compareTo(right.path));
  final manifest = CaptureManifest(
    sourceGitSha: sourceGitSha,
    deviceId: deviceId,
    targetPlatform: targetPlatform,
    profile: profile,
    physicalWidth: profile.physicalWidth,
    physicalHeight: profile.physicalHeight,
    logicalWidth: profile.logicalWidth,
    logicalHeight: profile.logicalHeight,
    devicePixelRatio: profile.devicePixelRatio,
    capturedLocales: StoreAssetLocale.values.map((locale) => locale.id).toList(),
    artifacts: artifacts,
  );
  await File('${profileDirectory.path}/capture.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    flush: true,
  );
}

Future<void> validateCapturedProfileDirectory({
  required Directory profileDirectory,
  required GitSnapshot expectedSnapshot,
}) async {
  final manifestFile = File('${profileDirectory.path}/capture.json');
  final manifest = CaptureManifest.parse(manifestFile.readAsStringSync());
  if (manifest.sourceGitSha != expectedSnapshot.sha) {
    throw StoreAssetException(
      'Capture revision changed for profile "${manifest.profile.id}": expected ${expectedSnapshot.sha}, '
      'actual ${manifest.sourceGitSha}.',
    );
  }
  final expectedFiles = {
    'capture.json',
    for (final locale in StoreAssetLocale.values)
      for (final fileName in sceneFileNames) '${locale.id}/$fileName',
  };
  final actualFiles = profileDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => _relativePath(profileDirectory, file))
      .toSet();
  for (final path in expectedFiles) {
    if (!actualFiles.contains(path)) throw StoreAssetException('Missing staged capture file "$path".');
  }
  for (final path in actualFiles) {
    if (!expectedFiles.contains(path)) throw StoreAssetException('Unexpected staged capture file "$path".');
  }
  await _validateCaptureManifest(manifest: manifest, profileDirectory: profileDirectory);
}

Future<void> composeStoreAssets(String repositoryRoot) async {
  final snapshot = await readGitSnapshot(repositoryRoot);
  final rawDirectory = Directory('$repositoryRoot/build/store_assets/raw');
  final sourceGitSha = await validateRawMatrix(rawDirectory: rawDirectory, currentSnapshot: snapshot);
  final headlines = validateCompositionSources(repositoryRoot);
  final stagingDirectory = Directory('$repositoryRoot/build/store_assets/.staging/final');
  final targetDirectory = Directory('$repositoryRoot/build/store_assets/final');
  await replaceManagedDirectory(
    repositoryRoot: repositoryRoot,
    stagingDirectory: stagingDirectory,
    targetDirectory: targetDirectory,
    build: (directory) async {
      for (final profile in StoreAssetProfile.values) {
        for (final locale in StoreAssetLocale.values) {
          final outputDirectory = Directory('${directory.path}/screenshots/${profile.id}/${locale.id}');
          await outputDirectory.create(recursive: true);
          for (var index = 0; index < sceneFileNames.length; index++) {
            await _composeScreenshot(
              repositoryRoot: repositoryRoot,
              rawFile: File('${rawDirectory.path}/${profile.id}/${locale.id}/${sceneFileNames[index]}'),
              outputFile: File('${outputDirectory.path}/${sceneFileNames[index]}'),
              profile: profile,
              headline: headlines.values[locale]![sceneKeys[index]]!,
            );
          }
        }
      }
      await _composeFeatureGraphic(
        repositoryRoot: repositoryRoot,
        outputFile: File('${directory.path}/feature-graphic.png'),
      );
    },
    validate: (directory) => validateStagedComposition(
      finalDirectory: directory,
      sourceGitSha: sourceGitSha,
      expectedSnapshot: snapshot,
      readCurrentSnapshot: () => readGitSnapshot(repositoryRoot),
    ),
  );
}

List<String> deterministicPngOutputArguments(File outputFile) => [
  '-colorspace',
  'sRGB',
  '-depth',
  '8',
  '-alpha',
  'off',
  '-strip',
  'PNG24:${outputFile.path}',
];

Future<void> _composeScreenshot({
  required String repositoryRoot,
  required File rawFile,
  required File outputFile,
  required StoreAssetProfile profile,
  required String headline,
}) async {
  final width = profile.physicalWidth;
  final height = profile.physicalHeight;
  final topBandHeight = (height * 0.14).round();
  final lowerHeight = height - topBandHeight;
  final font = '$repositoryRoot/assets/fonts/store_headline_bold.ttf';
  final fontSize = (height * 0.026).round();
  final headlineWidth = (width * 0.62).round();
  final wrappedHeadline = await _wrapHeadline(
    text: headline,
    font: font,
    pointSize: fontSize,
    maximumWidth: headlineWidth,
  );
  final arguments = <String>[
    '-size',
    '${width}x$height',
    'xc:#0B1226',
  ];
  _appendCoverLayer(
    arguments,
    source: '$repositoryRoot/assets/images/background.png',
    width: width,
    height: height,
  );
  _appendContainedLayer(
    arguments,
    source: rawFile.path,
    x: 0,
    y: topBandHeight,
    width: width,
    height: lowerHeight,
    gravity: 'South',
  );
  arguments.addAll([
    '-fill',
    'rgba(11,18,38,0.42)',
    '-draw',
    'rectangle 0,0 ${width - 1},${topBandHeight - 1}',
  ]);
  _appendContainedLayer(
    arguments,
    source: '$repositoryRoot/assets/branding/splash_logo.png',
    x: (width * 0.04).round(),
    y: (height * 0.02).round(),
    width: (width * 0.28).round(),
    height: (height * 0.10).round(),
  );
  _appendTextLayer(
    arguments,
    text: wrappedHeadline,
    font: font,
    pointSize: fontSize,
    lineHeight: 1.10,
    x: (width * 0.34).round(),
    y: (height * 0.015).round(),
    width: headlineWidth,
    height: (height * 0.11).round(),
    gravity: 'West',
  );
  arguments.addAll(deterministicPngOutputArguments(outputFile));
  await _runMagick(arguments, outputFile);
}

Future<void> _composeFeatureGraphic({required String repositoryRoot, required File outputFile}) async {
  const width = 1024;
  const height = 500;
  final font = '$repositoryRoot/assets/fonts/store_headline_bold.ttf';
  final arguments = <String>['-size', '${width}x$height', 'xc:#0B1226'];
  _appendCoverLayer(
    arguments,
    source: '$repositoryRoot/assets/images/background.png',
    width: width,
    height: height,
  );
  arguments.addAll([
    '-fill',
    'rgba(11,18,38,0.20)',
    '-draw',
    'rectangle 0,0 ${width - 1},${height - 1}',
  ]);
  _appendContainedLayer(
    arguments,
    source: '$repositoryRoot/assets/branding/splash_logo.png',
    x: (width * 0.04).round(),
    y: (height * 0.17).round(),
    width: (width * 0.52).round(),
    height: (height * 0.66).round(),
  );
  final productNameWidth = (width * 0.36).round();
  final productNameSize = (height * 0.13).round();
  if (await _measureText(text: 'Pebbix', font: font, pointSize: productNameSize) > productNameWidth) {
    throw const StoreAssetException('The feature graphic product name exceeds its approved maximum width.');
  }
  _appendTextLayer(
    arguments,
    text: 'Pebbix',
    font: font,
    pointSize: productNameSize,
    lineHeight: 1,
    x: (width * 0.58).round(),
    y: (height * 0.12).round(),
    width: productNameWidth,
    height: (height * 0.20).round(),
    gravity: 'Center',
  );
  const bubbles = [
    ('bubble_red.png', 0.60, 0.42),
    ('bubble_yellow.png', 0.71, 0.36),
    ('bubble_green.png', 0.82, 0.42),
    ('bubble_blue.png', 0.60, 0.66),
    ('bubble_purple.png', 0.71, 0.72),
    ('bubble_orange.png', 0.82, 0.66),
  ];
  for (final (fileName, x, y) in bubbles) {
    _appendContainedLayer(
      arguments,
      source: '$repositoryRoot/assets/images/$fileName',
      x: (width * x).round(),
      y: (height * y).round(),
      width: (width * 0.10).round(),
      height: (height * 0.205).round(),
    );
  }
  arguments.addAll(deterministicPngOutputArguments(outputFile));
  await _runMagick(arguments, outputFile);
}

void _appendCoverLayer(
  List<String> arguments, {
  required String source,
  required int width,
  required int height,
}) {
  arguments.addAll([
    '(',
    source,
    '-resize',
    '${width}x$height^',
    '-gravity',
    'Center',
    '-extent',
    '${width}x$height',
    ')',
    '-gravity',
    'NorthWest',
    '-geometry',
    '+0+0',
    '-composite',
  ]);
}

void _appendContainedLayer(
  List<String> arguments, {
  required String source,
  required int x,
  required int y,
  required int width,
  required int height,
  String gravity = 'Center',
}) {
  arguments.addAll([
    '(',
    source,
    '-resize',
    '${width}x$height',
    '-background',
    'none',
    '-gravity',
    gravity,
    '-extent',
    '${width}x$height',
    ')',
    '-gravity',
    'NorthWest',
    '-geometry',
    '+$x+$y',
    '-composite',
  ]);
}

void _appendTextLayer(
  List<String> arguments, {
  required String text,
  required String font,
  required int pointSize,
  required double lineHeight,
  required int x,
  required int y,
  required int width,
  required int height,
  required String gravity,
}) {
  arguments.addAll(
    storeAssetTextLayerArguments(
      text: text,
      font: font,
      pointSize: pointSize,
      lineHeight: lineHeight,
      x: x,
      y: y,
      width: width,
      height: height,
      gravity: gravity,
    ),
  );
}

List<String> storeAssetTextLayerArguments({
  required String text,
  required String font,
  required int pointSize,
  required double lineHeight,
  required int x,
  required int y,
  required int width,
  required int height,
  required String gravity,
}) => [
  '(',
  '-size',
  '${width}x$height',
  'xc:none',
  '-fill',
  '#FFFFFFFF',
  '-font',
  font,
  '-weight',
  '700',
  '-pointsize',
  '$pointSize',
  '-interline-spacing',
  '${(pointSize * (lineHeight - 1)).round()}',
  '-gravity',
  gravity,
  '-annotate',
  '+0+0',
  text,
  ')',
  '-gravity',
  'NorthWest',
  '-geometry',
  '+$x+$y',
  '-composite',
];

Future<String> _wrapHeadline({
  required String text,
  required String font,
  required int pointSize,
  required int maximumWidth,
}) async {
  if (await _measureText(text: text, font: font, pointSize: pointSize) <= maximumWidth) return text;
  final words = text.split(' ');
  ({String text, int widest})? best;
  for (var index = 1; index < words.length; index++) {
    final first = words.take(index).join(' ');
    final second = words.skip(index).join(' ');
    final firstWidth = await _measureText(text: first, font: font, pointSize: pointSize);
    final secondWidth = await _measureText(text: second, font: font, pointSize: pointSize);
    final widest = firstWidth > secondWidth ? firstWidth : secondWidth;
    if (widest <= maximumWidth && (best == null || widest < best.widest)) {
      best = (text: '$first\n$second', widest: widest);
    }
  }
  if (best == null) {
    throw StoreAssetException('Headline "$text" exceeds two lines at the approved maximum width.');
  }
  return best.text;
}

Future<int> _measureText({required String text, required String font, required int pointSize}) async {
  final result = await Process.run('magick', [
    '-font',
    font,
    '-weight',
    '700',
    '-pointsize',
    '$pointSize',
    'label:$text',
    '-format',
    '%w',
    'info:',
  ]);
  if (result.exitCode != 0) {
    throw StoreAssetException('ImageMagick failed to measure "$text": ${(result.stderr as String).trim()}');
  }
  return parseMeasuredTextWidth(
    output: result.stdout as String,
    text: text,
  );
}

int parseMeasuredTextWidth({required String output, required String text}) {
  final width = output.trim();
  if (width.isEmpty) {
    throw StoreAssetException('ImageMagick returned an empty width for "$text".');
  }
  final parsed = int.tryParse(width);
  if (parsed == null) {
    throw StoreAssetException('ImageMagick returned width "$width" for "$text". Expected integer pixels.');
  }
  return parsed;
}

Future<void> _runMagick(List<String> arguments, File outputFile) async {
  await outputFile.parent.create(recursive: true);
  final result = await Process.run('magick', arguments);
  if (result.exitCode != 0) {
    throw StoreAssetException(
      'ImageMagick failed to compose "${outputFile.path}": ${(result.stderr as String).trim()}',
    );
  }
}

Future<void> runStoreAssetsCommand({required List<String> arguments, required String repositoryRoot}) async {
  if (arguments.isEmpty) {
    throw const StoreAssetException('Expected store-assets command: capture, compose, or verify.');
  }
  switch (arguments.first) {
    case 'capture':
      if (arguments.length != 3) {
        throw const StoreAssetException('Usage: store-assets capture <device-id> <profile>.');
      }
      await captureStoreAssets(
        repositoryRoot: repositoryRoot,
        deviceId: arguments[1],
        profileId: arguments[2],
      );
    case 'compose':
      if (arguments.length != 1) throw const StoreAssetException('Usage: store-assets compose.');
      await composeStoreAssets(repositoryRoot);
    case 'verify':
      if (arguments.length != 1) throw const StoreAssetException('Usage: store-assets verify.');
      final snapshot = await readGitSnapshot(repositoryRoot);
      final sourceGitSha = await validateRawMatrix(
        rawDirectory: Directory('$repositoryRoot/build/store_assets/raw'),
        currentSnapshot: snapshot,
      );
      await verifyFinalArtifacts(
        Directory('$repositoryRoot/build/store_assets/final'),
        expectedSourceGitSha: sourceGitSha,
      );
    default:
      throw StoreAssetException('Unknown store-assets command "${arguments.first}".');
  }
}
