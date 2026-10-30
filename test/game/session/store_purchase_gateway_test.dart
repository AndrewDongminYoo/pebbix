// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/fakes.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/store_purchase_gateway.dart';

/// Only the nine members of `InAppPurchase` this adapter calls are written
/// out; `Mock` answers the rest, so a plugin method the adapter never touches
/// cannot be reached by accident.
class _FakeInAppPurchase extends Mock implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> updates = StreamController<List<PurchaseDetails>>.broadcast();

  bool available = true;
  Exception? availableThrows;
  List<ProductDetails> products = [];
  List<String> notFoundIDs = [];
  bool buyAccepted = true;
  Exception? buyThrows;
  Exception? restoreThrows;
  Exception? completeThrows;

  /// Stands in for a slow preferences write plus a slow `completePurchase`
  /// channel call, which is what settling a delivered purchase really costs.
  Duration completeDelay = Duration.zero;

  /// What the store answers the next [restorePurchases] with, delivered on
  /// the stream the way both real stores deliver it.
  List<PurchaseDetails> restoreDelivers = [];

  /// Delivers [restoreDelivers] only after `restorePurchases` has already
  /// returned, which is StoreKit 1's real ordering: its completer fires from
  /// `paymentQueueRestoreCompletedTransactionsFinished` while the
  /// transactions are still waiting on a receipt fetch.
  bool restoreDeliversLate = false;

  /// Answers a restore with nothing at all — no delivery, empty or
  /// otherwise. No shipping store does this; it stands in for one that
  /// stopped responding mid-restore.
  bool restoreSilent = false;

  int restoreCount = 0;
  int buyCount = 0;
  final List<PurchaseDetails> completed = [];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async {
    if (availableThrows case final error?) throw error;
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    return ProductDetailsResponse(productDetails: products, notFoundIDs: notFoundIDs);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCount++;
    if (buyThrows case final error?) throw error;
    return buyAccepted;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCount++;
    if (restoreThrows case final error?) throw error;
    if (restoreSilent) return;
    // Every store pushes the restored set, empty included, onto the stream.
    final answer = restoreDelivers;
    if (!restoreDeliversLate) {
      updates.add(answer);
      return;
    }
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () => updates.add(answer)),
    );
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (completeDelay > Duration.zero) await Future<void>.delayed(completeDelay);
    if (completeThrows case final error?) throw error;
    completed.add(purchase);
  }
}

/// Counts the entitlement writes, so "no cache write" is assertable rather
/// than inferred from the value happening to be unchanged.
class _RecordingSettings extends InMemorySettingsRepository {
  new({super.cachedAdsRemoved});

  int adsRemovedWrites = 0;
  Exception? writeThrows;

  /// Holds the next write open until the test releases it, so a second grant
  /// can land while the first one is still in flight. Completing it with an
  /// error fails that one write and leaves the ones behind it alone, which is
  /// what a transient disk failure looks like.
  Completer<void>? writeGate;

  @override
  Future<void> cacheAdsRemoved({required bool removed}) async {
    adsRemovedWrites++;
    if (writeGate case final gate?) {
      // Only the write that took the gate waits on it.
      writeGate = null;
      await gate.future;
    }
    if (writeThrows case final error?) throw error;
    await super.cacheAdsRemoved(removed: removed);
  }
}

class _RecordingAnalyticsSink extends AnalyticsSink {
  final List<(String, Map<String, Object?>)> events = [];

  @override
  void track(String event, [Map<String, Object?> parameters = const {}]) {
    events.add((event, parameters));
  }
}

/// Records hold maps, and record equality is `==` on each field — which for
/// a map is identity. So the two halves are asserted separately, where the
/// matcher compares maps by value.
void _expectEvent(
  (String, Map<String, Object?>) event,
  String name,
  Map<String, Object?> parameters,
) {
  expect(event.$1, name);
  expect(event.$2, parameters);
}

ProductDetails _product({String id = removeAdsProductId, String price = r'$1.99'}) {
  return ProductDetails(
    id: id,
    title: 'Remove Ads',
    description: 'Removes the interstitials',
    price: price,
    rawPrice: 1.99,
    currencyCode: 'USD',
  );
}

PurchaseDetails _purchase(
  PurchaseStatus status, {
  String productID = removeAdsProductId,
  bool pendingComplete = true,
  String receipt = 'receipt-data',
}) {
  return PurchaseDetails(
    productID: productID,
    verificationData: PurchaseVerificationData(
      localVerificationData: receipt,
      serverVerificationData: receipt,
      source: 'test',
    ),
    transactionDate: null,
    status: status,
  )..pendingCompletePurchase = pendingComplete;
}

/// A Play purchase as the restore path delivers it: the status has been
/// rewritten to `restored`, and only the wrapper still says what Play holds.
GooglePlayPurchaseDetails _playRestore(PurchaseStateWrapper state) {
  final wrapper = PurchaseWrapper(
    orderId: 'order-1',
    packageName: 'kr.donminzzi.pebbix',
    purchaseTime: 0,
    purchaseToken: 'token',
    signature: 'signature',
    products: const [removeAdsProductId],
    isAutoRenewing: false,
    originalJson: '{}',
    isAcknowledged: false,
    purchaseState: state,
  );
  return GooglePlayPurchaseDetails.fromPurchase(wrapper).single..status = PurchaseStatus.restored;
}

void main() {
  late _FakeInAppPurchase iap;
  late _RecordingSettings settings;
  late _RecordingAnalyticsSink analytics;

  StorePurchaseGateway build({
    _RecordingSettings? withSettings,
    String store = appStore,
    Duration restoreSettleWindow = const Duration(milliseconds: 50),
  }) {
    settings = withSettings ?? _RecordingSettings();
    final gateway = StorePurchaseGateway(
      settings: settings,
      analytics: analytics,
      store: store,
      injectedIap: iap,
      restoreSettleWindow: restoreSettleWindow,
    );
    addTearDown(gateway.dispose);
    return gateway;
  }

  setUp(() {
    iap = _FakeInAppPurchase()..products = [_product()];
    analytics = _RecordingAnalyticsSink();
  });

  tearDown(() => iap.updates.close());

  group('StorePurchaseGateway start', () {
    test('seeds the entitlement from the cache before the store answers', () {
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));

      // Spec §4: a previously verified entitlement is honored offline, so it
      // has to be readable before anything is asked of the store.
      expect(gateway.adsRemoved, isTrue);
      expect(gateway.offer.value.price, isNull);
    });

    test('resolves the product and keeps one subscription across calls', () async {
      final gateway = build();

      await gateway.start();
      await gateway.start();

      expect(gateway.offer.value.price, r'$1.99');
      expect(iap.updates.hasListener, isTrue);

      // A second start must not double-deliver: two subscriptions would run
      // every purchase through the entitlement write twice.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      expect(settings.adsRemovedWrites, 1);
    });

    test('leaves the product unknown when the store is unavailable', () async {
      iap.available = false;
      final gateway = build();

      await gateway.start();

      expect(gateway.offer.value.price, isNull);
      // The app still runs: the launch is not allowed to depend on this.
      expect(gateway.adsRemoved, isFalse);
    });

    test('a store that turns unavailable takes its price with it', () async {
      final gateway = build();
      await gateway.start();
      expect(gateway.offer.value.price, r'$1.99');

      iap.available = false;
      await gateway.start();

      // The account or the storefront may have changed under it, so an offer
      // still showing the old price could start a purchase on stale product
      // data.
      expect(gateway.offer.value.price, isNull);
    });

    test('leaves the product unknown when the store does not offer it', () async {
      iap
        ..products = []
        ..notFoundIDs = [removeAdsProductId];
      final gateway = build();

      await gateway.start();

      expect(gateway.offer.value.price, isNull);
    });

    test('re-reads Play ownership once, silently', () async {
      final gateway = build(
        withSettings: _RecordingSettings(cachedAdsRemoved: true),
        store: playStore,
      );
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.start();
      await gateway.start();

      // Play does not replay ownership onto the purchase stream, so an
      // account whose purchase was refunded reaches the app no other way.
      expect(iap.restoreCount, 1);
      expect(gateway.adsRemoved, isFalse);
      // Nothing is on screen at launch, and the player asked for nothing.
      expect(outcomes, isEmpty);
    });

    test('a reconciled entitlement is not a restore the player made', () async {
      iap.restoreDelivers = [_purchase(PurchaseStatus.restored)];
      final gateway = build(store: playStore);
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.start();
      await pumpEventQueue();

      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
      // Spec §7's `remove_ads_restored` counts restores the player asked
      // for. Recording one per launch would make every entitled Android
      // player look like a daily restorer.
      expect(analytics.events, isEmpty);
      expect(outcomes, isEmpty);
    });

    test('an inconclusive reconcile is retried, not marked done', () async {
      iap.restoreSilent = true;
      final gateway = build(store: playStore, restoreSettleWindow: const Duration(milliseconds: 20));

      await gateway.start();
      expect(iap.restoreCount, 1);

      // The product lookup succeeded, so Settings would find a price — but
      // ownership was never actually checked, and a reconcile that checked
      // nothing must not suppress the next attempt.
      iap.restoreSilent = false;
      await gateway.start();

      expect(iap.restoreCount, 2);
    });

    test('a reconcile answered ambiguously stays retryable', () async {
      // First attempt times out, so the second's empty answer may be its
      // snapshot rather than a fresh one — refused, and therefore proof of
      // nothing that could close the retry path.
      iap.restoreSilent = true;
      final gateway = build(store: playStore, restoreSettleWindow: const Duration(milliseconds: 20));
      await gateway.start();
      iap.restoreSilent = false;
      await gateway.start();
      expect(iap.restoreCount, 2);

      await gateway.start();

      expect(iap.restoreCount, 3);
    });

    test('a held purchase keeps ownership checks open', () async {
      final gateway = build(store: playStore);
      await gateway.start();
      expect(iap.restoreCount, 1);

      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      await gateway.start();

      // Play can settle a pending purchase while the app is suspended, and
      // nothing guarantees a stream event reaches this process afterwards —
      // so a finished reconcile stops being final while one is outstanding.
      expect(iap.restoreCount, 2);
    });

    test('leaves App Store ownership to the player', () async {
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));

      await gateway.start();

      // StoreKit 1's restore can put an Apple Account sign-in in front of the
      // player, so Apple asks for it to be user-initiated.
      expect(iap.restoreCount, 0);
      expect(gateway.adsRemoved, isTrue);
    });

    test('swallows a store that throws', () async {
      iap.availableThrows = Exception('billing unavailable');
      final gateway = build();

      await expectLater(gateway.start(), completes);

      expect(gateway.offer.value.price, isNull);
      // The stream is still subscribed: the failure came after it, and a
      // transaction the store settles later still has to land.
      expect(iap.updates.hasListener, isTrue);
    });
  });

  group('StorePurchaseGateway buy', () {
    test('refuses and reports when no product was resolved', () async {
      iap.products = [];
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await gateway.buy();

      expect(await outcomes, [PurchaseOutcome.failed]);
      expect(iap.buyCount, 0);
      // Nothing was started, so the funnel must not record a start.
      expect(analytics.events, isEmpty);
    });

    test('sends the request and records the start', () async {
      final gateway = build();
      await gateway.start();

      await gateway.buy();

      expect(iap.buyCount, 1);
      _expectEvent(analytics.events.single, 'remove_ads_purchase_started', {
        'product_id': removeAdsProductId,
      });
    });

    test('a second tap cannot open a second billing flow', () async {
      final gateway = build();
      await gateway.start();

      await gateway.buy();
      await gateway.buy();

      expect(iap.buyCount, 1);
      expect(analytics.events, hasLength(1));
    });

    test('a settled attempt releases the row for the next one', () async {
      final gateway = build();
      await gateway.start();

      await gateway.buy();
      iap.updates.add([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();
      await gateway.buy();

      // Backing out of the sheet settles the attempt, so the player can try
      // again without relaunching.
      expect(iap.buyCount, 2);
    });

    test('a pending purchase keeps the attempt outstanding', () async {
      final gateway = build();
      await gateway.start();

      await gateway.buy();
      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      await gateway.buy();

      // Play can hold a pending purchase for days; a second flow while one
      // is outstanding is the duplicate this guards against.
      expect(iap.buyCount, 1);
    });

    test('reports a request the store never accepted', () async {
      iap.buyAccepted = false;
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await gateway.buy();

      expect(await outcomes, [PurchaseOutcome.failed]);
    });

    test('reports a request that threw', () async {
      iap.buyThrows = Exception('no connection');
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await expectLater(gateway.buy(), completes);

      expect(await outcomes, [PurchaseOutcome.failed]);
    });
  });

  group('StorePurchaseGateway purchase updates', () {
    test('a settled purchase grants, caches, records and completes', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();
      final purchase = _purchase(PurchaseStatus.purchased);

      iap.updates.add([purchase]);
      await pumpEventQueue();

      expect(await outcomes, [PurchaseOutcome.purchased]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
      _expectEvent(analytics.events.single, 'remove_ads_purchase_completed', {
        'product_id': removeAdsProductId,
        'store': appStore,
      });
      expect(iap.completed, [purchase]);
    });

    test('a pending purchase grants nothing and is not completed', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();

      expect(await outcomes, [PurchaseOutcome.pending]);
      // Spec §4: pending and deferred purchases do not unlock the
      // entitlement. Completing one throws, so it must not be attempted.
      expect(gateway.adsRemoved, isFalse);
      expect(settings.adsRemovedWrites, 0);
      expect(iap.completed, isEmpty);
    });

    test('a canceled purchase grants nothing', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();

      expect(await outcomes, [PurchaseOutcome.canceled]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.adsRemovedWrites, 0);
    });

    test('a failed purchase grants nothing', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_purchase(PurchaseStatus.error)]);
      await pumpEventQueue();

      expect(await outcomes, [PurchaseOutcome.failed]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.adsRemovedWrites, 0);
    });

    test('a restored purchase grants and records the restore', () async {
      final gateway = build(store: playStore);
      // Started first, so the launch reconcile answers empty and the
      // delivery below belongs to the restore the player asks for — the
      // funnel counts those, and a delivery alone is not one.
      await gateway.start();
      iap.restoreDelivers = [_purchase(PurchaseStatus.restored)];
      final outcomes = gateway.outcomes.take(1).toList();

      await gateway.restore();
      await pumpEventQueue();

      expect(await outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
      _expectEvent(analytics.events.single, 'remove_ads_restored', {'store': playStore});
    });

    test('a transaction re-delivered at launch is not a restore', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      iap.updates.add([_purchase(PurchaseStatus.restored)]);
      await pumpEventQueue();

      // The store re-delivers an unfinished transaction on its own. Granting
      // is right; calling it a restore is not, and if the acknowledgement
      // keeps failing it would repeat on every launch.
      expect(gateway.adsRemoved, isTrue);
      expect(iap.completed, hasLength(1));
      expect(analytics.events, isEmpty);
      expect(outcomes, isEmpty);
    });

    test('a purchase Play still holds is not restored into an entitlement', () async {
      final gateway = build(store: playStore);
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_playRestore(PurchaseStateWrapper.pending)]);
      await pumpEventQueue();

      // restorePurchases maps every queried purchase to `restored` after the
      // real state was read, so this arrives looking settled. Spec §4 says a
      // pending purchase grants nothing.
      expect(await outcomes, [PurchaseOutcome.pending]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.adsRemovedWrites, 0);
      expect(iap.completed, isEmpty);
      expect(gateway.offer.value.awaitingStore, isTrue);
    });

    test('a Play state that says nothing does not grant', () async {
      final gateway = build(store: playStore);
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_playRestore(PurchaseStateWrapper.unspecified_state)]);
      await pumpEventQueue();

      // Play's own state has to say the purchase happened. Refusing a list of
      // bad states instead would trust whatever the list forgot.
      expect(await outcomes, [PurchaseOutcome.pending]);
      expect(gateway.adsRemoved, isFalse);
      expect(iap.completed, isEmpty);
    });

    test('a purchase Play has settled still restores', () async {
      final gateway = build(store: playStore);
      await gateway.start();

      iap.updates.add([_playRestore(PurchaseStateWrapper.purchased)]);
      await pumpEventQueue();

      // The wrapper check only withholds what Play is still holding; a
      // settled one grants exactly as before.
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
      expect(gateway.offer.value.awaitingStore, isFalse);
    });

    test('another product on the same stream is ignored', () async {
      final gateway = build();
      await gateway.start();

      iap.updates.add([_purchase(PurchaseStatus.purchased, productID: 'coins_100')]);
      await pumpEventQueue();

      expect(gateway.adsRemoved, isFalse);
      expect(analytics.events, isEmpty);
      expect(iap.completed, isEmpty);
    });

    test('a purchase the store already finished is not completed again', () async {
      final gateway = build();
      await gateway.start();

      iap.updates.add([_purchase(PurchaseStatus.purchased, pendingComplete: false)]);
      await pumpEventQueue();

      expect(gateway.adsRemoved, isTrue);
      expect(iap.completed, isEmpty);
    });

    test('the entitlement is observable while a page is open', () async {
      final gateway = build();
      await gateway.start();
      final seen = <bool>[];
      gateway.offer.addListener(() => seen.add(gateway.adsRemoved));

      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      // Settings observes this: a purchase that settles while the page is up
      // has to repaint the row that offered it.
      expect(seen, [true]);
    });

    test('an error on the store stream is survivable', () async {
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();

      iap.updates.addError(Exception('billing disconnected'));
      await pumpEventQueue();

      // A stream that faults must not take the launch down or drop an
      // entitlement the player already paid for.
      expect(gateway.adsRemoved, isTrue);
      expect(settings.adsRemovedWrites, 0);
    });

    test('a purchase with no receipt is neither granted nor completed', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      iap.updates.add([_purchase(PurchaseStatus.purchased, receipt: '')]);
      await pumpEventQueue();

      // StoreKit's receipt fetch returns an empty string when it fails, so
      // this is the transient shape, not a tampered one. Completing it would
      // burn a purchase the player paid for; the store re-delivers it.
      expect(await outcomes, [PurchaseOutcome.failed]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.adsRemovedWrites, 0);
      expect(iap.completed, isEmpty);
      // The store is still holding a transaction the player paid for, so the
      // row stays closed: reopening it would answer the next tap with an
      // already-owned failure.
      expect(gateway.offer.value.awaitingStore, isTrue);
      await gateway.buy();
      expect(iap.buyCount, 0);
    });

    test('the price reaches the offer once the store answers', () async {
      final gateway = build();
      final seen = <String?>[];
      gateway.offer.addListener(() => seen.add(gateway.offer.value.price));

      await gateway.start();

      // Settings can open before this lands, and the row it renders has to
      // stop being a priceless placeholder when it does.
      expect(seen, [r'$1.99']);
    });

    test('a cache write that throws still finishes the transaction', () async {
      final gateway = build(withSettings: _RecordingSettings()..writeThrows = Exception('disk full'));
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();
      final purchase = _purchase(PurchaseStatus.purchased);

      iap.updates.add([purchase]);
      await pumpEventQueue();

      // Play auto-refunds a purchase left unacknowledged, so a failed cache
      // write must not be able to abort the completion. The cache is the
      // offline seed; losing it costs an offline launch, not the purchase.
      expect(iap.completed, [purchase]);
      expect(await outcomes, [PurchaseOutcome.purchased]);
      expect(gateway.adsRemoved, isTrue);
    });

    test('a purchase Play is still holding blocks a second flow', () async {
      final gateway = build();
      await gateway.start();

      // Re-delivered at launch, where no tap set the flag. A second
      // buyNonConsumable would go out on top of the one already pending.
      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      await gateway.buy();

      expect(iap.buyCount, 0);
    });

    test('a re-delivered sale is counted once', () async {
      iap.completeThrows = Exception('finish failed');
      final gateway = build();
      await gateway.start();

      // The completion keeps failing, so the store re-delivers on every
      // launch. Counting each of those would report the same sale daily.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(analytics.events, hasLength(1));
      _expectEvent(analytics.events.single, 'remove_ads_purchase_completed', {
        'product_id': removeAdsProductId,
        'store': appStore,
      });
    });

    test('a purchase the store is holding closes the offer', () async {
      final gateway = build();
      await gateway.start();

      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();

      // Play can hold one for days, and a row that still reads as actionable
      // would answer every tap by discarding it.
      expect(gateway.offer.value.awaitingStore, isTrue);

      iap.updates.add([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();

      expect(gateway.offer.value.awaitingStore, isFalse);
    });

    test('a cache write left behind is landed by the next delivery', () async {
      final recording = _RecordingSettings()..writeThrows = Exception('disk full');
      final gateway = build(withSettings: recording);
      await gateway.start();

      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      // In memory only: an offline relaunch would still read false and show
      // forced ads to a player who paid.
      expect(gateway.adsRemoved, isTrue);
      expect(recording.cachedAdsRemoved, isFalse);

      recording.writeThrows = null;
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(recording.cachedAdsRemoved, isTrue);
      // Still one sale: the retry changed nothing in memory.
      expect(analytics.events, hasLength(1));
    });

    test('a stream error settles the attempt it interrupted', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.buy();
      expect(gateway.offer.value.awaitingStore, isTrue);
      iap.updates.addError(Exception('billing disconnected'));
      await pumpEventQueue();

      // The stream's failure is the only answer an accepted request gets.
      // Dropped, the row stays closed for the rest of the process.
      expect(outcomes, [PurchaseOutcome.failed]);
      expect(gateway.offer.value.awaitingStore, isFalse);
    });

    test('a completion that throws leaves the entitlement standing', () async {
      iap.completeThrows = Exception('finish failed');
      final gateway = build();
      await gateway.start();

      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      // The store re-delivers the transaction next launch; the player keeps
      // what they paid for in the meantime.
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
    });

    test('a stream error leaves a purchase the store is holding outstanding', () async {
      final gateway = build();
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(gateway.offer.value.awaitingStore, isTrue);

      iap.updates.addError(Exception('billing disconnected'));
      await pumpEventQueue();

      // A faulted stream says nothing about whether the payment the store is
      // holding was canceled. Releasing the row on it would put a second
      // billing flow on top of a transaction that has not settled, and
      // reporting a failure would claim an answer nobody gave.
      expect(gateway.offer.value.awaitingStore, isTrue);
      expect(outcomes, [PurchaseOutcome.pending]);
      await gateway.buy();
      expect(iap.buyCount, 0);
    });

    test('a cache write that fails under a second grant is still retried', () async {
      final gate = Completer<void>();
      final recording = _RecordingSettings()..writeGate = gate;
      final gateway = build(withSettings: recording);
      await gateway.start();

      // The first grant takes the gate and stays in flight.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      expect(gateway.adsRemoved, isTrue);
      expect(recording.cachedAdsRemoved, isFalse);

      // A second grant lands before the first write has reported anything, so
      // nothing it can read yet says the cache is behind.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      // Only now does the held write fail. No later delivery is guaranteed,
      // so the retry has to have been queued behind it already.
      gate.completeError(Exception('disk full'));
      await pumpEventQueue();

      expect(recording.cachedAdsRemoved, isTrue);
      // Still one sale: the retry changed nothing in memory.
      expect(analytics.events, hasLength(1));
    });
  });

  group('StorePurchaseGateway restore', () {
    test('a restore that returns the purchase reports only the restore', () async {
      iap.restoreDelivers = [_purchase(PurchaseStatus.restored)];
      final gateway = build();
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.restore();
      await pumpEventQueue();

      expect(outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
    });

    test('a restore delivered after the call still counts as a restore', () async {
      iap
        ..restoreDelivers = [_purchase(PurchaseStatus.restored)]
        ..restoreDeliversLate = true;
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.restore();
      await pumpEventQueue();

      // StoreKit resolves `restorePurchases()` before the restored
      // transactions reach the stream. Reading that gap as an empty restore
      // would clear an entitlement the player paid for.
      expect(outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
    });

    test('a tap during the launch reconcile takes it over', () async {
      iap
        ..restoreDelivers = [_purchase(PurchaseStatus.restored)]
        ..restoreDeliversLate = true;
      final gateway = build(store: playStore, restoreSettleWindow: const Duration(milliseconds: 200));
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      final launch = gateway.start();
      await gateway.restore();
      await launch;
      await pumpEventQueue();

      // The reconcile is silent, so a tap turned away by it would produce no
      // message at all and read as broken. One store call answers both.
      expect(iap.restoreCount, 1);
      expect(outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
    });

    test('a second tap during a restore cannot revoke its result', () async {
      iap
        ..restoreDelivers = [_purchase(PurchaseStatus.restored)]
        ..restoreDeliversLate = true;
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await Future.wait([gateway.restore(), gateway.restore()]);
      await pumpEventQueue();

      // The second attempt must not start its own settle window: the first
      // would then time out against a completer nothing completes and clear
      // the entitlement the store had just restored.
      expect(outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
      expect(iap.restoreCount, 1);
    });

    test('a slow settlement cannot turn a restore into a failure', () async {
      iap
        ..restoreDelivers = [_purchase(PurchaseStatus.restored)]
        ..completeDelay = const Duration(milliseconds: 150);
      final gateway = build(restoreSettleWindow: const Duration(milliseconds: 20));
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.restore();
      await pumpEventQueue();

      // The delivery is the answer, so it settles the restore before the
      // preferences write and the completion call it also triggers. Waiting
      // on those would report a failure over the success they are granting.
      expect(outcomes, [PurchaseOutcome.restored]);
      expect(gateway.adsRemoved, isTrue);
    });

    test('an unrelated delivery does not answer the restore', () async {
      // An unfinished transaction re-delivered at launch, landing while a
      // restore is out. It says the account owns the product; reading it as
      // the restore's answer would revoke on the strength of it.
      iap
        ..restoreDelivers = [_purchase(PurchaseStatus.purchased)]
        ..restoreDeliversLate = true;
      final gateway = build(
        withSettings: _RecordingSettings(cachedAdsRemoved: true),
        restoreSettleWindow: const Duration(milliseconds: 120),
      );
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.restore();
      await pumpEventQueue();

      expect(outcomes, [PurchaseOutcome.purchased, PurchaseOutcome.timedOut]);
      expect(gateway.adsRemoved, isTrue);
    });

    test('a purchase that settles during a restore survives its answer', () async {
      // The store's empty answer is delivered after the payment lands.
      iap.restoreDeliversLate = true;
      final gateway = build(restoreSettleWindow: const Duration(milliseconds: 300));
      await gateway.start();
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      final restoring = gateway.restore();
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      await restoring;

      // "You own nothing" was true when it was asked and false by the time
      // it arrived. Revoking on it would take away a payment just made.
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
      expect(outcomes, [PurchaseOutcome.purchased]);
    });

    test('a stream error answers a restore that is still waiting', () async {
      iap.restoreSilent = true;
      final gateway = build(restoreSettleWindow: const Duration(seconds: 5));
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      final restoring = gateway.restore();
      await pumpEventQueue();
      iap.updates.addError(Exception('billing disconnected'));
      await restoring;

      // Reported as the refusal the store actually gave, rather than left to
      // run out a five-second window and be called a silence it never made.
      expect(await outcomes, [PurchaseOutcome.failed]);
      expect(gateway.adsRemoved, isFalse);
    });

    test('an answer that may belong to a timed-out attempt cannot revoke', () async {
      // A: times out with its native call still out.
      iap.restoreSilent = true;
      final gateway = build(restoreSettleWindow: const Duration(milliseconds: 20));
      await gateway.start();
      await gateway.restore();

      // The payment lands between the two attempts.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      expect(gateway.adsRemoved, isTrue);

      // B: answered by A's empty snapshot, taken before the payment. The
      // grant counter cannot see that ordering, because B's baseline was
      // taken after the purchase.
      iap.restoreSilent = false;
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);
      await gateway.restore();
      await pumpEventQueue();

      expect(outcomes, [PurchaseOutcome.nothingRestored]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
    });

    test('a restore that finds only a held purchase is not ownership', () async {
      // App Store harness so no launch reconcile consumes the delivery; the
      // details being Play's is what this is about, not which store field.
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      iap.restoreDelivers = [_playRestore(PurchaseStateWrapper.pending)];
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);

      await gateway.restore();
      await pumpEventQueue();

      // Play rewrote the status to `restored`, so reading the answer off it
      // would leave the stale cache standing on a transaction that has not
      // settled. Spec §4 says a pending purchase grants nothing.
      expect(outcomes, [PurchaseOutcome.pending, PurchaseOutcome.nothingRestored]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.cachedAdsRemoved, isFalse);
    });

    test('an empty Play answer releases an attempt the store is not holding', () async {
      final gateway = build(store: playStore);
      await gateway.start();
      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(gateway.offer.value.awaitingStore, isTrue);

      await gateway.restore();
      await pumpEventQueue();

      // `queryPurchases` returns everything Play holds, pending transactions
      // included, so a list without this product is Play denying it holds
      // one — and an empty delivery reaches no _apply, which is the only
      // other place the marker is released.
      expect(gateway.offer.value.awaitingStore, isFalse);
    });

    test('a restore that finds it pending keeps the attempt outstanding', () async {
      final gateway = build();
      await gateway.start();
      iap.restoreDelivers = [_playRestore(PurchaseStateWrapper.pending)];

      await gateway.restore();
      await pumpEventQueue();

      // "Not owned yet" alongside a pending transaction describes one that
      // has not settled, not the absence of one — reopening the row here
      // would put a second billing flow on top of it.
      expect(gateway.adsRemoved, isFalse);
      expect(gateway.offer.value.awaitingStore, isTrue);
    });

    test('an empty restore clears the cached entitlement', () async {
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await gateway.restore();

      // Spec §4 makes the store authoritative over the cache: an account the
      // store no longer reports this product for stops being entitled, which
      // is how a revoked or refunded purchase is reflected.
      expect(await outcomes, [PurchaseOutcome.nothingRestored]);
      expect(gateway.adsRemoved, isFalse);
      expect(settings.cachedAdsRemoved, isFalse);
    });

    test('a store that never answers reports a timeout and keeps the cache', () async {
      iap.restoreSilent = true;
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await gateway.restore();

      // Running the window out is not the store saying the account owns
      // nothing, so it must not revoke what the account paid for — and it is
      // not a refusal either, so it does not claim one.
      expect(await outcomes, [PurchaseOutcome.timedOut]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.adsRemovedWrites, 0);
    });

    test('a restore that threw reports a failure and keeps the cache', () async {
      iap.restoreThrows = Exception('store unreachable');
      final gateway = build(withSettings: _RecordingSettings(cachedAdsRemoved: true));
      await gateway.start();
      final outcomes = gateway.outcomes.take(1).toList();

      await expectLater(gateway.restore(), completes);

      // Only an answer from the store overrides the cache. A store that never
      // answered is not an answer, so the entitlement survives.
      expect(await outcomes, [PurchaseOutcome.failed]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.adsRemovedWrites, 0);
    });

    test('a late answer to a faulted restore frees the next one to revoke', () async {
      iap.restoreSilent = true;
      final gateway = build(
        withSettings: _RecordingSettings(cachedAdsRemoved: true),
        restoreSettleWindow: const Duration(milliseconds: 200),
      );
      await gateway.start();

      // A: ended by a stream error, which says nothing about what its call
      // will eventually answer, so the call stays counted.
      final a = gateway.restore();
      await pumpEventQueue();
      iap.updates.addError(Exception('billing disconnected'));
      await a;

      // A's answer lands afterwards with nobody waiting on it. That is the
      // store resolving the ambiguity, and it is what brings the count back
      // down — an error path that discounted the call itself would instead
      // hand the next attempt a stale answer to revoke on.
      iap.updates.add(<PurchaseDetails>[]);
      await pumpEventQueue();

      // B: no call is out but its own, so the store's word stands.
      final b = gateway.restore();
      await pumpEventQueue();
      iap.updates.add(<PurchaseDetails>[]);
      await b;
      await pumpEventQueue();

      expect(gateway.adsRemoved, isFalse);
      expect(settings.cachedAdsRemoved, isFalse);
    });

    test('an empty App Store answer leaves a deferred transaction alone', () async {
      final gateway = build();
      await gateway.start();
      iap.updates.add([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(gateway.offer.value.awaitingStore, isTrue);

      await gateway.restore();
      await pumpEventQueue();

      // StoreKit's restore reports completed restorable purchases only, so a
      // transaction awaiting approval is not in the answer to begin with. The
      // empty list is not the store denying it holds one, and reopening the
      // row on it would put a second billing flow on top.
      expect(gateway.offer.value.awaitingStore, isTrue);
      await gateway.buy();
      expect(iap.buyCount, 0);
    });

    test('a Play answer that names it held keeps the hold', () async {
      final gateway = build(store: playStore);
      await gateway.start();
      iap.restoreDelivers = [_playRestore(PurchaseStateWrapper.pending)];

      await gateway.restore();
      await pumpEventQueue();

      // Play denies holding this product by leaving it out of the list, and
      // this list names it. The status arrived rewritten to `restored`, so
      // only the wrapper still says Play has not settled it — reading the
      // denial off the status would release a transaction Play is holding.
      expect(gateway.offer.value.awaitingStore, isTrue);
      expect(gateway.adsRemoved, isFalse);
    });

    test('a stale answer stays stale while its own call is still out', () async {
      // A: times out with its native call still out.
      iap.restoreSilent = true;
      final gateway = build(
        withSettings: _RecordingSettings(cachedAdsRemoved: true),
        restoreSettleWindow: const Duration(milliseconds: 200),
      );
      await gateway.start();
      await gateway.restore();

      // B: consumes A's late empty answer, and leaves its own call out in
      // turn. Its refusal to revoke is already covered; what this is about is
      // what B leaves behind.
      final b = gateway.restore();
      await pumpEventQueue();
      iap.updates.add(<PurchaseDetails>[]);
      await b;

      // The payment settles after B has already been answered.
      iap.updates.add([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();
      expect(gateway.adsRemoved, isTrue);

      // C: handed B's late empty snapshot, which was taken before the
      // payment. C's own grant baseline already includes it, so the counter
      // cannot see the ordering — only B's outstanding call can.
      final outcomes = <PurchaseOutcome>[];
      gateway.outcomes.listen(outcomes.add);
      final c = gateway.restore();
      await pumpEventQueue();
      iap.updates.add(<PurchaseDetails>[]);
      await c;
      await pumpEventQueue();

      expect(outcomes, [PurchaseOutcome.nothingRestored]);
      expect(gateway.adsRemoved, isTrue);
      expect(settings.cachedAdsRemoved, isTrue);
    });
  });

  test('records where the offer was viewed', () {
    build().recordOfferViewed(settingsPlacement);

    _expectEvent(analytics.events.single, 'remove_ads_viewed', {'placement': settingsPlacement});
  });

  test('dispose releases the store stream', () async {
    final gateway = StorePurchaseGateway(
      settings: _RecordingSettings(),
      analytics: analytics,
      store: playStore,
      injectedIap: iap,
    );
    await gateway.start();
    expect(iap.updates.hasListener, isTrue);

    await gateway.dispose();

    expect(iap.updates.hasListener, isFalse);
  });
}
