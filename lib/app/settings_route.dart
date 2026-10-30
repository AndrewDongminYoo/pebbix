// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/app/legal_links.dart';
import 'package:bubble_shooter/game/session/session.dart';
import 'package:bubble_shooter/game/view/settings_page.dart';

/// Opens Settings with everything both entry points owe the player.
///
/// There are two ways in — the title screen and the pause panel — and the
/// obligations do not differ between them: `ConsentGateway`'s contract says
/// Settings offers the privacy-options row whenever the region requires it,
/// and the policy has to be readable from either. Routing both through here
/// is what stops one entry point from quietly offering less than the other,
/// which is exactly what a hand-copied route did on the first attempt.
///
/// The store is the same object for both, too: `PurchaseGateway` is app-scoped
/// so a purchase made from one entry point is already in force at the other.
///
/// [onAlsoChanged] is the only difference: the in-game route pushes the new
/// settings into its `AudioCubit`, which does not exist above `GamePage`.
/// The repository write happens either way, and the next `AudioCubit` seeds
/// itself from it.
Future<void> openSettings(
  BuildContext context, {
  ValueChanged<GameSettings>? onAlsoChanged,
}) async {
  final repository = context.read<SettingsRepository>();
  final consent = context.read<ConsentGateway>();
  final ads = context.read<AdsGateway>();
  // The ad-free release supplies a plain entitlement without a store connection.
  // Only a purchase gateway exposes the purchase and restore entries.
  final entitlements = context.read<EntitlementRepository>();
  final analytics = context.read<AnalyticsSink>();
  final purchases = entitlements is PurchaseGateway ? entitlements : null;
  final locale = Localizations.localeOf(context);

  await Navigator.of(context).push(
    SettingsPage.route(
      initialSettings: repository.settings,
      analyticsAvailable: analytics is AnalyticsCollectionControl,
      onChanged: (settings) {
        final analyticsChanged = settings.analyticsEnabled != repository.settings.analyticsEnabled;
        unawaited(repository.saveSettings(settings));
        if (analyticsChanged && analytics is AnalyticsCollectionControl) {
          unawaited((analytics as AnalyticsCollectionControl).setAnalyticsEnabled(enabled: settings.analyticsEnabled));
        }
        onAlsoChanged?.call(settings);
      },
      // UMP only requires a reopenable entry point in some regions, and
      // consent can resolve while this page is open — so hand over the
      // requirement itself rather than a snapshot of it (spec §Privacy).
      privacyOptionsRequired: consent.privacyOptionsRequired,
      purchases: purchases,
      onPrivacyOptions: consent is NoConsentGateway ? null : () => unawaited(applyPrivacyChoice(consent, ads)),
      onPrivacyPolicy: () => unawaited(const LegalLinks().openPrivacyPolicy(locale)),
    ),
  );
}

/// Applies whatever the player answered in the UMP form.
///
/// This form is where a player withdraws a consent the ads are already
/// running on, so its answer has to reach them: whatever is loaded is
/// dropped and nothing further is requested. A player who grants here
/// instead gets ads this session rather than at the next launch.
Future<void> applyPrivacyChoice(ConsentGateway consent, AdsGateway ads) async {
  await consent.showPrivacyOptions();
  await (consent.canRequestAds ? ads.start() : ads.stop());
}
