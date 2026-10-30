// 🐦 Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/fakes.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/game/view/how_to_play_page.dart';
import 'package:bubble_shooter/game/view/settings_page.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Pretendard')..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'));
    await loader.load();
  });

  for (final locale in [const Locale('en'), const Locale('ko')]) {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('shows the full pushed heading at 200 percent in $locale $size', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Pretendard'),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: Text('Home')),
          ),
        );
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        final closed = navigator.push(HowToPlayPage.route(Images(prefix: '')));
        await tester.pumpAndSettle();

        expect(find.byType(BackButton), findsOneWidget);
        final heading = tester.renderObject<RenderParagraph>(
          find.text(locale.languageCode == 'en' ? 'How to play' : '게임 방법'),
        );
        expect(heading.didExceedMaxLines, isFalse, reason: 'The route title must remain fully readable.');
        expect(tester.takeException(), isNull);
        navigator.pop();
        await tester.pumpAndSettle();
        await closed;
      });
    }
  }

  testWidgets('keeps disabled purchase and privacy labels readable on the panel', (tester) async {
    final purchases = FakePurchaseGateway();
    final privacyRequired = ValueNotifier(false);
    addTearDown(privacyRequired.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          initialSettings: const GameSettings(),
          onChanged: (_) {},
          analyticsAvailable: false,
          purchases: purchases,
          onPrivacyOptions: () {},
          privacyOptionsRequired: privacyRequired,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['Remove Ads', 'Privacy options']) {
      final finder = find.text(label);
      await tester.scrollUntilVisible(finder, 100);
      final tile = tester.widget<ListTile>(find.ancestor(of: finder, matching: find.byType(ListTile)).first);
      expect(tile.enabled, isFalse);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final material = tester.widget<Material>(find.ancestor(of: finder, matching: find.byType(Material)).first);
      final background = material.color!;
      final foreground = Color.alphaBlend(paragraph.text.style!.color!, background);
      final foregroundLuminance = foreground.computeLuminance() + .05;
      final backgroundLuminance = background.computeLuminance() + .05;
      final contrast = foregroundLuminance > backgroundLuminance
          ? foregroundLuminance / backgroundLuminance
          : backgroundLuminance / foregroundLuminance;
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$label must remain readable while unavailable.');
    }
  });
}
