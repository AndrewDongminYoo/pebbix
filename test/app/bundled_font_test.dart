// 🎯 Dart imports:
import 'dart:convert';
import 'dart:io';

// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

// 🌎 Project imports:
import '../helpers/font_coverage.dart';

/// Every character the app can render from its own strings, in both locales.
///
/// Read from the ARBs rather than listed here, so a string added later is
/// covered without anyone remembering to extend a literal.
Set<int> _stringCodePoints() {
  final points = <int>{};
  for (final name in ['app_en.arb', 'app_ko.arb']) {
    (jsonDecode(File('lib/l10n/arb/$name').readAsStringSync()) as Map<String, dynamic>).forEach((key, value) {
      // Keys starting with @ are metadata about the entry above them, and
      // their descriptions are never rendered.
      if (key.startsWith('@') || value is! String) return;
      points.addAll(value.runes);
    });
  }
  return points;
}

void main() {
  group('the bundled font', () {
    late Set<int> covered;

    setUpAll(() {
      covered = supportedCodePoints(File('assets/fonts/PretendardVariable.ttf').readAsBytesSync());
    });

    test('carries every character both locales can render', () {
      final missing = _stringCodePoints().difference(covered);

      expect(
        missing.map((c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')} (${String.fromCharCode(c)})'),
        isEmpty,
      );
    });

    test('carries Hangul, Latin and the digits a score needs', () {
      // The ARB sweep above only proves the strings that exist today. These
      // are the ranges the game composes at runtime — a score, a Korean
      // syllable the l10n files happen not to use yet.
      const samples = {
        0xAC00: '가 — first Hangul syllable',
        0xD7A3: '힣 — last Hangul syllable',
        0xC810: '점',
        0x0041: 'A',
        0x007A: 'z',
        0x0030: '0',
        0x0039: '9',
        0x00D7: '× — used between numbers',
      };

      expect(samples.keys.where((c) => !covered.contains(c)).map((c) => samples[c]), isEmpty);
    });

    testWidgets('the weights the UI asks for reach the variable axis', (tester) async {
      final loader = FontLoader('Pretendard')
        ..addFont(
          Future.value(File('assets/fonts/PretendardVariable.ttf').readAsBytesSync().buffer.asByteData()),
        );
      await loader.load();

      double widthAt(FontWeight weight) => (TextPainter(
        text: TextSpan(
          text: '점수 Score 1234',
          style: TextStyle(fontFamily: 'Pretendard', fontSize: 40, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).width;

      // One file has to serve regular, the bold on most panels, and the
      // black on the loading screen. Flutter maps FontWeight onto the wght
      // axis without a FontVariation, but only for a variable face — swap
      // in a single static and every weight silently renders the same.
      final regular = widthAt(FontWeight.w400);
      expect(widthAt(FontWeight.w700), greaterThan(regular));
      expect(widthAt(FontWeight.w900), greaterThan(widthAt(FontWeight.w700)));
    });

    test('the font is registered and no font package remains', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('assets/fonts/PretendardVariable.ttf'));
      // A bundled face is only half of it: leaving google_fonts installed
      // leaves the runtime download one call away, and the whole point is
      // that production makes no network request to render text.
      expect(pubspec, isNot(contains('google_fonts')));
    });

    test('the store headline face ships in the app too', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      // Spec 0003 §"After issue #41 lands" requires proving the configured
      // font is bundled in the application, and lines 76 and 968 name this
      // path specifically as an application-bundled face. Shipping it only
      // in the working tree would satisfy the compositor and fail the spec,
      // which is what this assertion used to lock in.
      expect(File('assets/fonts/store_headline_bold.ttf').existsSync(), isTrue);
      expect(pubspec, contains('assets/fonts/store_headline_bold.ttf'));
    });

    test('nothing else joins the family the UI renders through', () {
      // The weight test above loads one file by hand, so it cannot see the
      // production family at all. This reads the manifest instead: a second
      // face under `Pretendard` is what would break it. A static declared at
      // w700 sits closer to a w900 request than the variable file's
      // undeclared w400 default, so Flutter would hand the loading screen's
      // black to the static and render it bold, with every test still green.
      final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      final families = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;
      final pretendard = families.firstWhere((f) => (f as YamlMap)['family'] == 'Pretendard') as YamlMap;

      expect(
        (pretendard['fonts'] as YamlList).map((f) => (f as YamlMap)['asset']),
        ['assets/fonts/PretendardVariable.ttf'],
      );
    });
  });
}
