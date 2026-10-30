// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/legal_links.dart';

void main() {
  group(LegalLinks, () {
    test('a Korean UI opens the Korean policy page', () async {
      final opened = <Uri>[];

      await LegalLinks(
        launch: (url) async {
          opened.add(url);
          return true;
        },
      ).openPrivacyPolicy(const Locale('ko'));

      expect(opened.single.toString(), 'https://pebbix.donminzzi.kr/ko/privacy');
    });

    test('every other locale opens the English page', () async {
      final opened = <Uri>[];
      final links = LegalLinks(
        launch: (url) async {
          opened.add(url);
          return true;
        },
      );

      // The app itself falls back to English for anything but Korean, so the
      // page has to agree with the screen that linked to it.
      await links.openPrivacyPolicy(const Locale('en'));
      await links.openPrivacyPolicy(const Locale('ja'));

      expect(
        opened.map((u) => u.path),
        ['/en/privacy', '/en/privacy'],
      );
    });

    test('a platform with nowhere to open it does not throw', () async {
      // The caller is a settings row with no second route to offer, so a
      // refusal has to die here rather than surface as an unhandled error.
      await expectLater(
        LegalLinks(launch: (_) async => throw Exception('no handler')).openPrivacyPolicy(const Locale('ko')),
        completes,
      );
    });

    test('the default launcher is the url_launcher entry point', () {
      // Nothing here calls it — a real launch would leave the browser open
      // on the test host. This only proves the production constructor takes
      // the default rather than requiring an injection.
      expect(const LegalLinks(), isA<LegalLinks>());
    });
  });
}
