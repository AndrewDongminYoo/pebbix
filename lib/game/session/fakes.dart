// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/ads_gateway.dart';
import 'package:bubble_shooter/game/session/consent_gateway.dart';
import 'package:bubble_shooter/game/session/entitlement_repository.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';

/// In-repo fakes: the dev app runs on these until the real adapters
/// land, and controller tests drive them directly.
class FakeAdsGateway implements AdsGateway {
  new({
    this.rewardedReady = true,
    this.interstitialReady = true,
    this.rewardedOutcome = RewardedOutcome.earned,
  });

  @override
  bool rewardedReady;

  @override
  bool interstitialReady;

  RewardedOutcome rewardedOutcome;

  int interstitialShownCount = 0;
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<RewardedOutcome> showRewarded() async => rewardedOutcome;

  @override
  Future<void> showInterstitial() async {
    interstitialShownCount++;
  }
}

class FakeConsentGateway implements ConsentGateway {
  new({
    bool privacyOptionsRequired = false,
    this.gatherFails = false,
  }) : privacyOptionsRequired = ValueNotifier(privacyOptionsRequired);

  /// Starts fail-closed, as the contract requires — this fake is what all
  /// three entrypoints run on until the UMP adapter lands, so a default of
  /// true would mean the shipped app believed it could request ads before
  /// any consent state existed.
  @override
  bool canRequestAds = false;

  @override
  final ValueNotifier<bool> privacyOptionsRequired;

  /// Makes [gather] behave as a consent failure: it still completes — the
  /// real one never throws either — and leaves ads unavailable.
  bool gatherFails;

  /// What the player chooses in the privacy form, applied when it closes.
  /// The real gateway re-reads consent there, so a withdrawal has to be
  /// expressible; null leaves the current state alone.
  bool? privacyChoice;

  int gatherCount = 0;
  int privacyOptionsShownCount = 0;

  @override
  Future<void> gather() async {
    gatherCount++;
    canRequestAds = !gatherFails;
  }

  @override
  Future<void> showPrivacyOptions() async {
    privacyOptionsShownCount++;
    if (privacyChoice case final choice?) canRequestAds = choice;
  }
}

class FakeEntitlementRepository implements EntitlementRepository {
  new({this.adsRemoved = false});

  @override
  bool adsRemoved;
}

/// In-memory store. The dev app runs on this wherever `in_app_purchase`
/// registers no platform — web and macOS — so the purchase UI is still
/// exercisable there, and the settings tests drive it directly.
class FakePurchaseGateway implements PurchaseGateway {
  new({bool adsRemoved = false, String? price, bool awaitingStore = false})
    : _offer = ValueNotifier(
        PurchaseOffer(adsRemoved: adsRemoved, price: price, awaitingStore: awaitingStore),
      );

  final ValueNotifier<PurchaseOffer> _offer;
  final StreamController<PurchaseOutcome> _outcomes = StreamController<PurchaseOutcome>.broadcast();

  /// What the next [buy] settles as. Only `purchased` and `restored` grant
  /// the entitlement, matching the real adapter.
  PurchaseOutcome buyOutcome = PurchaseOutcome.purchased;

  /// What the next [restore] answers with. Defaults to the empty answer,
  /// because a fresh install has nothing to restore.
  PurchaseOutcome restoreOutcome = PurchaseOutcome.nothingRestored;

  int startCount = 0;
  final List<String> viewedPlacements = [];

  /// Publishes a price the way a store answering after the screen has opened
  /// would.
  void publishPrice(String? price) => _offer.value = PurchaseOffer(
    adsRemoved: _offer.value.adsRemoved,
    price: price,
    awaitingStore: _offer.value.awaitingStore,
  );

  @override
  bool get adsRemoved => _offer.value.adsRemoved;

  @override
  ValueListenable<PurchaseOffer> get offer => _offer;

  @override
  Stream<PurchaseOutcome> get outcomes => _outcomes.stream;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> buy() async => _settle(buyOutcome, fromRestore: false);

  @override
  Future<void> restore() async => _settle(restoreOutcome, fromRestore: true);

  @override
  void recordOfferViewed(String placement) => viewedPlacements.add(placement);

  /// [fromRestore] is what tells the two facts the real adapter separates
  /// apart here: a buy's ending answers the request it made, while a
  /// restore's ending answers about the account and mostly says nothing about
  /// a transaction the store is holding.
  void _settle(PurchaseOutcome outcome, {required bool fromRestore}) {
    final awaiting = switch (outcome) {
      // Pending leaves the attempt outstanding, exactly as the real adapter
      // does: the store is still holding it.
      PurchaseOutcome.pending => true,
      // The store named this product as settled, so it is not holding one.
      PurchaseOutcome.purchased || PurchaseOutcome.restored => false,
      // Nothing else a restore ends with denies a held transaction: an empty
      // answer is about the account, and a failure or a timeout is not an
      // answer at all.
      _ when fromRestore => _offer.value.awaitingStore,
      // A buy that ended any other way is the request the store was handed,
      // answered.
      _ => false,
    };
    // The empty answer revokes, as the contract says it must: the store is
    // the authority and it did not name the product.
    final entitling = switch (outcome) {
      PurchaseOutcome.purchased || PurchaseOutcome.restored => true,
      PurchaseOutcome.nothingRestored => false,
      _ => _offer.value.adsRemoved,
    };
    _offer.value = PurchaseOffer(
      adsRemoved: entitling,
      price: _offer.value.price,
      awaitingStore: awaiting,
    );
    _outcomes.add(outcome);
  }
}

/// In-memory settings store: the dev app and tests run on this until
/// the shared_preferences implementation lands.
class InMemorySettingsRepository implements SettingsRepository {
  new({
    this._settings = const GameSettings(),
    this._highScore = 0,
    this._tutorialSeen = false,
    this._tutorialBegun = false,
    this._cachedAdsRemoved = false,
  });

  GameSettings _settings;
  int _highScore;
  bool _tutorialSeen;
  bool _tutorialBegun;
  bool _cachedAdsRemoved;

  @override
  GameSettings get settings => _settings;

  @override
  Future<void> saveSettings(GameSettings settings) async {
    _settings = settings;
  }

  @override
  int get highScore => _highScore;

  @override
  Future<void> saveHighScore(int score) async {
    _highScore = score;
  }

  @override
  bool get tutorialSeen => _tutorialSeen;

  @override
  Future<void> markTutorialSeen() async {
    _tutorialSeen = true;
  }

  @override
  bool get tutorialBegun => _tutorialBegun;

  @override
  Future<void> markTutorialBegun() async {
    _tutorialBegun = true;
  }

  @override
  bool get cachedAdsRemoved => _cachedAdsRemoved;

  @override
  Future<void> cacheAdsRemoved({required bool removed}) async {
    _cachedAdsRemoved = removed;
  }
}
