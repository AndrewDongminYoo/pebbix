// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/l10n/l10n.dart';

void main() {
  /// Renders one localized string under [locale] using the app's own
  /// delegates and supported list, so this exercises the real resolution.
  Future<String> resolve(
    WidgetTester tester,
    Locale? locale,
    String Function(AppLocalizations) valueFor,
  ) async {
    late String value;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            value = valueFor(context.l10n);
            return const SizedBox();
          },
        ),
      ),
    );
    return value;
  }

  group('locale resolution', () {
    testWidgets('Korean devices get Korean', (tester) async {
      expect(
        await resolve(tester, const Locale('ko'), (l10n) => l10n.titleButtonStart),
        '시작',
      );
      expect(
        await resolve(tester, const Locale('ko', 'KR'), (l10n) => l10n.titleButtonStart),
        '시작',
      );
    });

    testWidgets('every other locale falls back to English', (tester) async {
      expect(
        await resolve(tester, const Locale('en'), (l10n) => l10n.titleButtonStart),
        'Start',
      );
      // Unsupported locales resolve to supportedLocales.first, so this fails
      // if a locale sorting before `en` is ever added without an explicit
      // localeResolutionCallback.
      expect(
        await resolve(tester, const Locale('es'), (l10n) => l10n.titleButtonStart),
        'Start',
      );
      expect(
        await resolve(tester, const Locale('ja'), (l10n) => l10n.titleButtonStart),
        'Start',
      );
    });

    testWidgets('release name uses the selected display name per locale', (tester) async {
      expect(
        await resolve(tester, const Locale('en'), (l10n) => l10n.titleAppBarTitle),
        'Pebbix',
      );
      expect(
        await resolve(tester, const Locale('ko'), (l10n) => l10n.titleAppBarTitle),
        '페빅스',
      );
    });
  });
}
