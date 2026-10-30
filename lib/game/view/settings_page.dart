// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';
import 'package:bubble_shooter/game/widgets/game_menu_page.dart';
import 'package:bubble_shooter/l10n/l10n.dart';

/// Settings screen of spec §6: player toggles, Analytics opt-in, purchases,
/// ad privacy options and the published privacy policy.
///
/// It reads no providers on purpose. `AudioCubit` is provided inside
/// `GamePage`, below the root `Navigator`, so a pushed route cannot see it;
/// the caller passes the current values in and receives every change.
class SettingsPage extends StatefulWidget {
  const new({
    required this.initialSettings,
    required this.onChanged,
    required this.analyticsAvailable,
    this.purchases,
    this.onPrivacyOptions,
    this.privacyOptionsRequired,
    this.onPrivacyPolicy,
    super.key,
  });

  static Route<void> route({
    required GameSettings initialSettings,
    required ValueChanged<GameSettings> onChanged,
    required bool analyticsAvailable,
    PurchaseGateway? purchases,
    VoidCallback? onPrivacyOptions,
    ValueListenable<bool>? privacyOptionsRequired,
    VoidCallback? onPrivacyPolicy,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        initialSettings: initialSettings,
        onChanged: onChanged,
        analyticsAvailable: analyticsAvailable,
        purchases: purchases,
        onPrivacyOptions: onPrivacyOptions,
        privacyOptionsRequired: privacyOptionsRequired,
        onPrivacyPolicy: onPrivacyPolicy,
      ),
    );
  }

  final GameSettings initialSettings;
  final ValueChanged<GameSettings> onChanged;
  final bool analyticsAvailable;

  /// The store, or null to hide both purchase rows.
  /// The rows share the gateway so the entitlement, price, and purchase outcome agree.
  final PurchaseGateway? purchases;

  /// Null when consent is unavailable; the row is hidden.
  final VoidCallback? onPrivacyOptions;

  /// Whether UMP requires the entry point in this region. Observed rather
  /// than read once: consent resolves off the critical path, so it can land
  /// while this page is already open.
  final ValueListenable<bool>? privacyOptionsRequired;

  /// Opens the published policy. Distinct from [onPrivacyOptions], which
  /// reopens UMP's consent form: one states what the app collects, the other
  /// changes an ad-consent choice, and a player who wants the first must not
  /// land on the second. They render as separate rows with separate labels
  /// and icons, and this one is always enabled — the policy is readable in
  /// every region, consent form or not.
  final VoidCallback? onPrivacyPolicy;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// A stable fallback for consent providers that do not expose a requirement.
final _alwaysFalse = ValueNotifier<bool>(false);

class _SettingsPageState extends State<SettingsPage> {
  late GameSettings _settings = widget.initialSettings;
  StreamSubscription<PurchaseOutcome>? _outcomes;
  VoidCallback? _offerListener;
  bool _offerViewed = false;

  @override
  void initState() {
    super.initState();
    final purchases = widget.purchases;
    if (purchases == null) return;
    _outcomes = purchases.outcomes.listen(_reportOutcome);
    // The launch asks the store once, and either half of that can fail on
    // its own: a device that started offline has no product and so no offer,
    // and a launch whose ownership check timed out is still trusting a cache
    // it never confirmed. This screen is where the player comes looking for
    // both, so it asks again unconditionally — `start()` is idempotent, and
    // a price already in hand says nothing about the half that failed.
    unawaited(purchases.start());
    // `remove_ads_viewed` counts an offer the player could take, which is
    // why it waits on the offer rather than firing with the screen: a row
    // with no price yet is disabled, and one they already own is not an
    // offer at all (spec §7).
    _offerListener = () => _recordOffer(purchases);
    purchases.offer.addListener(_offerListener!);
    _recordOffer(purchases);
  }

  @override
  void dispose() {
    unawaited(_outcomes?.cancel());
    if (_offerListener case final listener?) widget.purchases?.offer.removeListener(listener);
    super.dispose();
  }

  /// Sends `remove_ads_viewed` the first time this screen actually has an
  /// offer to show, and once per visit however often the offer changes.
  void _recordOffer(PurchaseGateway purchases) {
    if (_offerViewed) return;
    final offer = purchases.offer.value;
    // Everything the row needs to be takeable: a price, no entitlement
    // already, and nothing outstanding with the store — Play can hold a
    // purchase for days, and counting each visit through that would inflate
    // the funnel with an offer the player cannot take.
    if (offer.adsRemoved || offer.price == null || offer.awaitingStore) return;
    _offerViewed = true;
    purchases.recordOfferViewed(settingsPlacement);
  }

  void _update(GameSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  /// Every attempt says how it ended, which is what spec §10 asks for: the
  /// pending, canceled and failed states are as visible as the completed one.
  void _reportOutcome(PurchaseOutcome outcome) {
    if (!mounted) return;
    final l10n = context.l10n;
    final message = switch (outcome) {
      PurchaseOutcome.purchased => l10n.purchaseCompleted,
      PurchaseOutcome.restored => l10n.purchaseRestored,
      PurchaseOutcome.pending => l10n.purchasePending,
      PurchaseOutcome.canceled => l10n.purchaseCanceled,
      PurchaseOutcome.failed => l10n.purchaseFailed,
      PurchaseOutcome.nothingRestored => l10n.purchaseNothingToRestore,
      PurchaseOutcome.timedOut => l10n.purchaseTimedOut,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final purchases = widget.purchases;
    return GameMenuPage(
      title: l10n.settingsTitle,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.music_note_rounded),
          title: Text(l10n.settingsMusic),
          value: _settings.musicEnabled,
          onChanged: (value) => _update(_settings.copyWith(musicEnabled: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up_rounded),
          title: Text(l10n.settingsSfx),
          value: _settings.sfxEnabled,
          onChanged: (value) => _update(_settings.copyWith(sfxEnabled: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.vibration_rounded),
          title: Text(l10n.settingsHaptics),
          value: _settings.hapticsEnabled,
          onChanged: (value) => _update(_settings.copyWith(hapticsEnabled: value)),
        ),
        const Divider(),
        if (purchases != null) ...[
          ValueListenableBuilder<PurchaseOffer>(
            // Both halves are observed, not read once at build: a purchase
            // that settles while this page is open has to reach the row that
            // offered it, and a price that lands after the page opened has to
            // replace the disabled placeholder it opened with.
            valueListenable: purchases.offer,
            builder: (context, offer, _) {
              // No price means no product, and a purchase cannot be started
              // without one — an enabled row there would answer the tap with
              // a failure the player did nothing to cause. Neither can a
              // second attempt while the store is still holding the first,
              // which Play can do for days.
              final canBuy = !offer.adsRemoved && offer.price != null && !offer.awaitingStore;
              return ListTile(
                leading: const Icon(Icons.block_outlined),
                title: Text(l10n.settingsRemoveAds),
                // Spec §10 requires the purchase UI to say that the optional
                // Continue ad survives the purchase.
                subtitle: Text(l10n.settingsRemoveAdsBody),
                trailing: switch (offer) {
                  PurchaseOffer(adsRemoved: true) => Text(l10n.settingsRemoveAdsOwned),
                  PurchaseOffer(awaitingStore: true) => Text(l10n.settingsRemoveAdsAwaiting),
                  PurchaseOffer(:final price?) => Text(price),
                  _ => null,
                },
                enabled: canBuy,
                onTap: canBuy ? () => unawaited(purchases.buy()) : null,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(l10n.settingsRestorePurchases),
            onTap: () => unawaited(purchases.restore()),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.settingsPrivacyPolicy),
          trailing: const Icon(Icons.open_in_new, size: 18),
          enabled: widget.onPrivacyPolicy != null,
          onTap: widget.onPrivacyPolicy,
        ),
        if (widget.analyticsAvailable)
          SwitchListTile(
            title: Text(l10n.settingsAnalytics),
            subtitle: Text(l10n.settingsAnalyticsBody),
            value: _settings.analyticsEnabled,
            inactiveTrackColor: const Color(0xFF818A99),
            onChanged: (value) => _update(_settings.copyWith(analyticsEnabled: value)),
          ),
        if (widget.onPrivacyOptions != null)
          ValueListenableBuilder<bool>(
            valueListenable: widget.privacyOptionsRequired ?? _alwaysFalse,
            builder: (context, isRequired, _) {
              final onTap = isRequired ? widget.onPrivacyOptions : null;
              return ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(l10n.settingsPrivacyOptions),
                enabled: onTap != null,
                onTap: onTap,
              );
            },
          ),
      ],
    );
  }
}
