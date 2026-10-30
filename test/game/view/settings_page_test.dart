// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/fakes.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/game/view/settings_page.dart';

import '../../helpers/helpers.dart';

void main() {
  group('SettingsPage', () {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('keeps Korean controls reachable at 200 percent in $size', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final changes = <GameSettings>[];
        var policyOpened = false;
        await tester.pumpApp(
          SettingsPage(
            initialSettings: const GameSettings(),
            onChanged: changes.add,
            analyticsAvailable: true,
            onPrivacyPolicy: () => policyOpened = true,
          ),
          locale: const Locale('ko'),
          textScaler: const TextScaler.linear(2),
        );

        for (final label in ['음악', '효과음', '진동']) {
          await tester.scrollUntilVisible(find.text(label), 100);
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(_switch(tester, label).value, isFalse);
          expect(tester.getSemantics(find.text(label)).label, contains(label));
        }
        expect(changes.last, const GameSettings(musicEnabled: false, sfxEnabled: false, hapticsEnabled: false));
        await tester.scrollUntilVisible(find.text('개인정보처리방침'), 100);
        await tester.tap(find.text('개인정보처리방침'));
        expect(policyOpened, isTrue);
        await tester.scrollUntilVisible(find.text('게임 플레이 분석에 참여'), 100);
        await tester.tap(find.text('게임 플레이 분석에 참여'));
        await tester.pumpAndSettle();
        expect(changes.last.analyticsEnabled, isTrue);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('shows the initial settings after route navigation', (
      tester,
    ) async {
      await _pushSettingsPage(
        tester,
        initialSettings: const GameSettings(
          musicEnabled: false,
          hapticsEnabled: false,
        ),
      );

      expect(_switch(tester, 'Music').value, isFalse);
      expect(_switch(tester, 'Sound effects').value, isTrue);
      expect(_switch(tester, 'Haptics').value, isFalse);
      expect(_switch(tester, 'Share gameplay analytics').value, isFalse);
    });

    testWidgets('analytics collection requires an explicit opt-in', (tester) async {
      final changes = <GameSettings>[];
      await _pushSettingsPage(tester, onChanged: changes.add);

      await tester.ensureVisible(find.text('Share gameplay analytics'));
      await tester.tap(find.text('Share gameplay analytics'));
      await tester.pump();

      expect(_switch(tester, 'Share gameplay analytics').value, isTrue);
      expect(changes.single.analyticsEnabled, isTrue);
    });

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('analytics choice stays reachable at $size', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final changes = <GameSettings>[];
        await _pushSettingsPage(tester, onChanged: changes.add);

        await tester.scrollUntilVisible(find.text('Share gameplay analytics'), 100);
        await tester.pump();
        await tester.tap(find.text('Share gameplay analytics'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(_switch(tester, 'Share gameplay analytics').value, isTrue);
        expect(changes.single.analyticsEnabled, isTrue);
      });
    }

    testWidgets('updates each switch locally and reports all changes', (
      tester,
    ) async {
      final changes = <GameSettings>[];
      await _pushSettingsPage(
        tester,
        initialSettings: const GameSettings(
          musicEnabled: false,
          hapticsEnabled: false,
        ),
        onChanged: changes.add,
      );

      await tester.tap(find.text('Music'));
      await tester.pump();
      expect(_switch(tester, 'Music').value, isTrue);
      expect(
        changes.last,
        const GameSettings(
          hapticsEnabled: false,
        ),
      );

      await tester.tap(find.text('Sound effects'));
      await tester.pump();
      expect(_switch(tester, 'Sound effects').value, isFalse);
      expect(
        changes.last,
        const GameSettings(
          sfxEnabled: false,
          hapticsEnabled: false,
        ),
      );

      await tester.tap(find.text('Haptics'));
      await tester.pump();
      expect(_switch(tester, 'Haptics').value, isTrue);
      expect(
        changes.last,
        const GameSettings(
          sfxEnabled: false,
        ),
      );
      expect(changes, hasLength(3));
    });

    testWidgets('invokes both available settings entries once', (
      tester,
    ) async {
      var privacyCount = 0;
      final purchases = FakePurchaseGateway();
      await _pushSettingsPage(
        tester,
        purchases: purchases,
        onPrivacyOptions: () => privacyCount += 1,
        // A callback alone no longer enables the row — UMP has to say the
        // region needs the entry point.
        privacyOptionsRequired: ValueNotifier(true),
      );

      await tester.tap(find.text('Restore Purchases'));
      await tester.scrollUntilVisible(find.text('Privacy options'), 100);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();

      // A restore that found nothing still has to say so (spec §10: the
      // no-history case completes safely rather than silently).
      expect(find.text('There is no purchase to restore.'), findsOneWidget);
      expect(privacyCount, 1);
    });

    testWidgets('hides unavailable purchases and consent while keeping settings and policy', (tester) async {
      await _pushSettingsPage(tester);

      expect(find.text('Remove Ads'), findsNothing);
      expect(find.text('Restore Purchases'), findsNothing);
      expect(find.text('Privacy options'), findsNothing);
      expect(find.text('Privacy Policy'), findsOneWidget);
      await tester.tap(find.text('Music'));
      await tester.pump();
      expect(_switch(tester, 'Music').value, isFalse);
    });

    testWidgets('does not open a consent form without a requirement signal', (tester) async {
      var opened = false;
      await _pushSettingsPage(tester, onPrivacyOptions: () => opened = true);

      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Privacy options'));
      expect(tile.enabled, isFalse);
      await tester.tap(find.text('Privacy options'));
      await tester.pumpAndSettle();
      expect(opened, isFalse);
    });

    testWidgets('offers the purchase at the store price and settles it', (
      tester,
    ) async {
      final purchases = FakePurchaseGateway(price: '\u20a91,200');
      await _pushSettingsPage(tester, purchases: purchases);

      expect(find.text('\u20a91,200'), findsOneWidget);
      // Spec §10: the purchase UI says the optional Continue ad survives it.
      expect(
        find.text(
          'Removes the interstitials shown between runs. '
          'The optional Continue ad stays available.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Remove Ads'));
      await tester.pumpAndSettle();

      expect(purchases.adsRemoved, isTrue);
      expect(find.text('Ads removed. Thank you!'), findsOneWidget);
      // The row that offered it repaints without leaving the page.
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Remove Ads'),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(find.text('Purchased'), findsOneWidget);
      expect(find.text('\u20a91,200'), findsNothing);
    });

    testWidgets('keeps the offer closed until the store names a price', (
      tester,
    ) async {
      // A store that has not answered yet, or does not carry the product in
      // this storefront. Enabling the row here would answer the tap with a
      // failure the player did nothing to cause.
      final purchases = FakePurchaseGateway();
      await _pushSettingsPage(tester, purchases: purchases);

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Remove Ads'),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      // Restore stays open: a past purchase is recoverable with no product
      // lookup at all.
      final restore = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Restore Purchases'),
      );
      expect(restore.enabled, isTrue);
    });

    testWidgets('asks the store again when the launch got no price', (
      tester,
    ) async {
      final purchases = FakePurchaseGateway();
      await _pushSettingsPage(tester, purchases: purchases);

      expect(purchases.startCount, 1);
    });

    testWidgets('asks again even with a price already in hand', (tester) async {
      // A launch can fail at the product lookup or at the ownership check
      // independently, and a price says nothing about the second one — so a
      // reconcile that never finished still gets its retry here.
      final purchases = FakePurchaseGateway(price: r'\u20a91,200');
      await _pushSettingsPage(tester, purchases: purchases);

      expect(purchases.startCount, 1);
    });

    testWidgets('closes the offer while the store is still holding one', (
      tester,
    ) async {
      final purchases = FakePurchaseGateway(price: r'\u20a91,200')..buyOutcome = PurchaseOutcome.pending;
      await _pushSettingsPage(tester, purchases: purchases);

      await tester.tap(find.text('Remove Ads'));
      await tester.pumpAndSettle();

      // Play can hold a purchase for days, and a row that still reads as
      // actionable would answer every tap by discarding it.
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Remove Ads'),
      );
      expect(tile.enabled, isFalse);
      expect(find.text('Waiting for the store'), findsOneWidget);
      expect(find.text('\u20a91,200'), findsNothing);
      expect(find.text('Your purchase is waiting for approval.'), findsOneWidget);
    });

    testWidgets('a restore that finds nothing leaves that hold alone', (
      tester,
    ) async {
      final purchases = FakePurchaseGateway(price: '\u20a91,200')..buyOutcome = PurchaseOutcome.pending;
      await _pushSettingsPage(tester, purchases: purchases);

      await tester.tap(find.text('Remove Ads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Purchases'));
      await tester.pumpAndSettle();

      // The empty answer is about the account, not about the transaction the
      // store is holding. Reopening the row on it would put a second billing
      // flow on top of a purchase still waiting for approval.
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Remove Ads'),
      );
      expect(tile.enabled, isFalse);
      expect(find.text('There is no purchase to restore.'), findsOneWidget);

      // A restore that fails says even less than an empty one does, so it
      // cannot release the hold either.
      purchases.restoreOutcome = PurchaseOutcome.failed;
      await tester.tap(find.text('Restore Purchases'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Remove Ads')).enabled,
        isFalse,
      );
    });

    testWidgets('reports every way an attempt can end', (tester) async {
      final purchases = FakePurchaseGateway(price: '\u20a91,200');
      await _pushSettingsPage(tester, purchases: purchases);

      // Pending is not in this loop: it leaves the attempt outstanding, which
      // closes the row on purpose. Its own test asserts both.
      const expected = {
        PurchaseOutcome.canceled: 'Purchase canceled.',
        PurchaseOutcome.failed: 'The purchase could not be completed. Please try again later.',
        PurchaseOutcome.timedOut: 'The store has not answered yet. Your purchases are unchanged.',
      };
      for (final entry in expected.entries) {
        purchases.buyOutcome = entry.key;
        await tester.tap(find.text('Remove Ads'));
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
        // None of these grants the entitlement, so the row stays on offer.
        expect(purchases.adsRemoved, isFalse);
      }

      purchases.restoreOutcome = PurchaseOutcome.restored;
      await tester.tap(find.text('Restore Purchases'));
      await tester.pumpAndSettle();
      expect(find.text('Your purchase has been restored.'), findsOneWidget);
      expect(purchases.adsRemoved, isTrue);
    });

    testWidgets('counts the offer as viewed once it can be taken', (
      tester,
    ) async {
      final purchases = FakePurchaseGateway();
      await _pushSettingsPage(tester, purchases: purchases);
      // Nothing to view yet: the store has not named a price, so the row is
      // disabled and counting it would inflate the funnel's top.
      expect(purchases.viewedPlacements, isEmpty);

      purchases.publishPrice(r'\u20a91,200');
      await tester.pump();
      purchases.publishPrice(r'\u20a91,300');
      await tester.pump();

      expect(purchases.viewedPlacements, [settingsPlacement]);
    });

    testWidgets('counts no view while the store is holding an attempt', (
      tester,
    ) async {
      // Play can hold a purchase for days, and the row is disabled for all of
      // them — counting each visit would inflate the funnel with an offer the
      // player cannot take.
      final purchases = FakePurchaseGateway(price: r'\u20a91,200', awaitingStore: true);
      await _pushSettingsPage(tester, purchases: purchases);

      expect(purchases.viewedPlacements, isEmpty);
    });

    testWidgets('counts no view where there is no offer left to see', (
      tester,
    ) async {
      // `remove_ads_viewed` measures the offer, not the screen, so an owner
      // reopening Settings must not inflate the funnel's top.
      final purchases = FakePurchaseGateway(adsRemoved: true);
      await _pushSettingsPage(tester, purchases: purchases);

      expect(purchases.viewedPlacements, isEmpty);
      expect(find.text('Purchased'), findsOneWidget);
    });
  });
}

SwitchListTile _switch(WidgetTester tester, String label) {
  return tester.widget<SwitchListTile>(
    find.widgetWithText(SwitchListTile, label),
  );
}

Future<void> _pushSettingsPage(
  WidgetTester tester, {
  GameSettings initialSettings = const GameSettings(),
  ValueChanged<GameSettings>? onChanged,
  PurchaseGateway? purchases,
  VoidCallback? onPrivacyOptions,
  ValueListenable<bool>? privacyOptionsRequired,
}) async {
  await tester.pumpApp(
    Builder(
      builder: (context) => Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            SettingsPage.route(
              initialSettings: initialSettings,
              onChanged: onChanged ?? (_) {},
              analyticsAvailable: true,
              purchases: purchases,
              onPrivacyOptions: onPrivacyOptions,
              privacyOptionsRequired: privacyOptionsRequired,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsPage), findsOneWidget);
}
