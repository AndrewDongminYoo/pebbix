// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:equatable/equatable.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/entitlement_repository.dart';

/// The single non-consumable of spec §4, by the id both stores are
/// configured with.
const removeAdsProductId = 'remove_ads';

/// The price the in-memory fake publishes where no store exists, so the dev
/// builds on web and macOS can still open the purchase flow. Not a currency
/// amount, because it is not one — nothing gated behind `_hasNativeStores`
/// ever reaches a store build.
const devFakePrice = 'DEV';

/// Where the player was shown the offer, sent as `remove_ads_viewed`'s
/// `placement` (spec §7). Settings is the only surface that offers it.
const settingsPlacement = 'settings';

/// How one purchase or restore attempt ended.
///
/// Spec §10 requires the available, pending, canceled, failed and completed
/// states to all be visible to the player, so each value here carries its own
/// message rather than collapsing into a success flag.
enum PurchaseOutcome {
  /// The store settled a fresh purchase, and the entitlement is granted.
  purchased,

  /// A past purchase came back from the store, and the entitlement is
  /// granted.
  restored,

  /// The store accepted the request but has not settled it — Play's pending
  /// transactions, StoreKit's deferred ones. No entitlement follows: spec §4
  /// says a pending purchase does not grant one.
  pending,

  /// The player backed out of the store's sheet.
  canceled,

  /// The store rejected the request, or could not be reached at all. An
  /// unavailable store reports this too, because the player's next move is
  /// the same either way.
  failed,

  /// A restore the store answered without this product. Not a failure — an
  /// account that never bought it is the ordinary case, and spec §10 asks
  /// for exactly that to complete safely.
  nothingRestored,

  /// The store took longer than the wait allows. Distinct from [failed]
  /// because nothing was refused: the request may still be settling, and
  /// telling the player it failed would be a claim about an answer nobody
  /// has.
  timedOut,
}

/// Everything the Remove Ads row renders from.
///
/// One object rather than two observables because its two halves arrive at
/// different times — the cache seeds the entitlement before the app is up,
/// the price only once the store answers — and the row has to repaint for
/// either. Reading the price separately is what left it rendering an
/// enabled, priceless offer whenever Settings opened first.
class PurchaseOffer extends Equatable {
  const new({this.adsRemoved = false, this.price, this.awaitingStore = false});

  /// Whether the forced interstitials are suppressed (spec §4).
  final bool adsRemoved;

  /// The store's own localized price, or null while the product is unknown —
  /// the store has not answered yet, or does not offer it in this storefront.
  /// The row stays disabled until it is known, because a purchase cannot be
  /// started without the product the price came with.
  final String? price;

  /// Whether an attempt is outstanding with the store — the sheet is up, or
  /// the store is holding the purchase, which Play can do for days. The row
  /// stops offering while it is: a second attempt is refused anyway, and a
  /// tap that silently does nothing reads as broken.
  ///
  /// One boolean rather than two, because those are separate facts inside the
  /// gateway — they are released by different things — but the row's question
  /// is only whether a purchase can be started right now, and neither of them
  /// allows it. This is their union.
  final bool awaitingStore;

  @override
  List<Object?> get props => [adsRemoved, price, awaitingStore];
}

/// Purchase surface for `remove_ads`, plugin-agnostic in the same way the
/// ads gateway is: spec §4 keeps ads, IAP and analytics outside the game and
/// the domain.
///
/// It is also the app's `EntitlementRepository`. The entitlement and the
/// purchase that grants it have one owner, so there is no window in which the
/// two disagree.
abstract interface class PurchaseGateway implements EntitlementRepository {
  /// Subscribes to the store's purchase updates and looks the product up.
  ///
  /// Never throws. An unreachable store costs the purchase UI, not the
  /// launch: the cached entitlement stands and the game stays playable
  /// (spec §4).
  Future<void> start();

  /// One event per finished purchase or restore attempt, for the message the
  /// player is shown. Broadcast, because Settings subscribes and unsubscribes
  /// with its route while this object outlives both.
  Stream<PurchaseOutcome> get outcomes;

  /// Changes whenever the entitlement or the price does, so a purchase that
  /// settles — or a price that lands — while Settings is open repaints the
  /// row rather than waiting for the next visit.
  ValueListenable<PurchaseOffer> get offer;

  /// Opens the store's purchase sheet for `remove_ads`.
  ///
  /// Never throws; the attempt reports itself through [outcomes].
  Future<void> buy();

  /// Asks the store for this account's past purchases.
  ///
  /// The store's answer wins over the cache — spec §4 makes store state the
  /// source of truth — so a restore that comes back without `remove_ads`
  /// clears a cached entitlement rather than leaving it standing.
  ///
  /// Never throws, for the same reason [buy] does not.
  Future<void> restore();

  /// Records that the player saw the offer at [placement]
  /// (`remove_ads_viewed`, spec §7).
  void recordOfferViewed(String placement);
}
