// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/game/session/analytics_sink.dart';
import 'package:bubble_shooter/game/session/purchase_gateway.dart';
import 'package:bubble_shooter/game/session/settings_repository.dart';

/// `store` parameter values for the purchase events of spec §7. The
/// dictionary names the parameter but not its vocabulary, so these two are
/// the whole set the funnel will ever see.
const playStore = 'play_store';
const appStore = 'app_store';

/// The real adapter, on the `in_app_purchase` plugin.
class StorePurchaseGateway implements PurchaseGateway {
  new({
    required this.settings,
    required this.analytics,
    required this.store,
    this._injectedIap,
    this.restoreSettleWindow = const Duration(seconds: 5),
  }) : // Seeded from the cache synchronously, which is what lets an offline
       // launch start entitled (spec §4).
       _offer = ValueNotifier(PurchaseOffer(adsRemoved: settings.cachedAdsRemoved));

  /// Where the last verified entitlement is cached (spec §2 package D).
  final SettingsRepository settings;

  final AnalyticsSink analytics;

  /// `play_store` or `app_store`, the `store` parameter of spec §7's
  /// purchase events.
  final String store;

  /// Left null outside tests rather than defaulted in the initializer list:
  /// reading `InAppPurchase.instance` registers a store platform, and Play's
  /// registration opens a billing connection over a channel from its own
  /// constructor — so merely constructing this would reach the platform. The
  /// same seam the AdMob adapter uses for `MobileAds.instance`.
  ///
  /// Named `injectedIap` at the call site: an initializing formal drops the
  /// underscore for the parameter name, which is the same shape
  /// `GameSessionController`'s `this._ads` uses. Four separate review rounds
  /// have read this as a compile error, so it is written down here.
  final InAppPurchase? _injectedIap;

  /// Resolved on first use, never at construction.
  late final InAppPurchase _iap = _injectedIap ?? InAppPurchase.instance;

  /// How long a restore waits for the store's answer to reach the purchase
  /// stream after `restorePurchases()` has already returned.
  ///
  /// Every store pushes the restored set — empty when the account owns
  /// nothing — onto that stream, so the answer is a delivery rather than the
  /// future: Play adds it before its future returns, StoreKit 2 sends it
  /// immediately before completing, and StoreKit 1 sends restored
  /// transactions only after awaiting a receipt fetch over a second channel,
  /// which is why the future routinely arrives first.
  ///
  /// This is the ceiling on a store that answers with nothing at all. Running
  /// it out is not an answer, so it never revokes anything.
  final Duration restoreSettleWindow;

  final ValueNotifier<PurchaseOffer> _offer;
  final StreamController<PurchaseOutcome> _outcomes = StreamController<PurchaseOutcome>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _product;

  /// Set from the tap that opened the store sheet until the store says
  /// anything at all about it. A second [buy] before then would send a second
  /// billing flow and a second `remove_ads_purchase_started`, and the
  /// rejection the store answers the duplicate with would overwrite the
  /// outcome of the real one.
  ///
  /// This is a fact about a request nobody has answered, which is why nothing
  /// about ownership may release it: a restore's answer describes the
  /// account, not the sheet the player is looking at, and Play's
  /// `queryPurchases` has no record of a billing flow the player has not paid
  /// for yet. Every path out of [buy] ends in one of exactly four things that
  /// do release it — a delivery reaching [_apply], a request the store
  /// refused to send, a throw from that call, or the stream faulting — so it
  /// needs no other escape hatch.
  bool _requestOutstanding = false;

  /// Set when the store has told us it is holding a transaction it has not
  /// settled: Play's pending purchases, StoreKit's deferred ones, and a
  /// granting delivery the plugin produced no receipt for.
  ///
  /// The store is the only thing that can take this back, and only about that
  /// transaction — by settling it, by canceling it, or by listing what it
  /// holds and leaving this product out of it. A stream error and a timeout
  /// are silences, not statements, and neither touches this.
  bool _storeHolding = false;

  /// What the offer publishes, because the row's question is only whether the
  /// player can start a purchase right now, and neither fact allows it.
  bool get _awaitingStore => _requestOutstanding || _storeHolding;

  /// Set by the one launch reconcile, so the [start] that Settings fires to
  /// re-ask for a price does not also re-query ownership.
  bool _reconciled = false;

  /// Whether the running restore is the player's. False only for the launch
  /// reconcile, whose deliveries grant and cache like any other but must add
  /// no restore to spec §7's funnel and show the player nothing.
  bool _restoreIsPlayers = true;

  /// The restore currently running, so a second caller joins it instead of
  /// starting a rival attempt.
  Future<void>? _restoreInFlight;

  /// Counts entitlement grants, so a restore can tell whether one landed
  /// while it was out. A store's answer is authoritative as of the moment it
  /// was asked, and an empty one is older than any purchase that settled
  /// after the question went out.
  int _grantCount = 0;

  /// How many restore calls have gone out to the store without a delivery
  /// coming back for them. An attempt that finds this above zero when it
  /// starts may be handed an older question's answer instead of its own, and
  /// an empty answer read off the wrong question would revoke on a payment it
  /// never saw.
  ///
  /// A counter rather than a flag, because the ambiguity outlives the attempt
  /// that created it: an attempt answered by its predecessor's late delivery
  /// leaves its own call out in turn, and passing that on is the whole point.
  /// The consequence is deliberate — while calls keep going out faster than
  /// answers come back, no restore in this process can revoke. The store
  /// answering one of them brings it back down, and the launch reconcile runs
  /// again next process.
  ///
  /// Only a delivery brings it down, which is why neither a timeout nor a
  /// stream error does. Both end an attempt; neither ends the call it made or
  /// says what that call will answer, and discounting it on either would hand
  /// the next attempt exactly the stale answer this exists to catch. A stream
  /// error does not close the stream, so the answer that resolves it can
  /// still arrive afterwards with nobody waiting.
  int _unansweredRestoreCalls = 0;

  /// Whether the last restore got a definitive answer, which is what tells a
  /// completed ownership check from one that checked nothing.
  bool _lastRestoreAnswered = false;

  /// Whether the delivery that answered the last restore carried this product
  /// in a state the store is still holding. An answer of "not owned" that
  /// arrived alongside a pending transaction is not a statement that nothing
  /// is outstanding.
  bool _answerHeldProduct = false;

  /// What the cache is known to hold, seeded from the cache itself. The offer
  /// can be ahead of it — a write that failed leaves it behind — and a later
  /// grant that changes nothing in memory still has this to land.
  late bool _cachedAdsRemoved = settings.cachedAdsRemoved;

  /// Serializes the entitlement writes. Two grants that overlap would
  /// otherwise both read a cache neither has written yet, and the second
  /// would decide there was nothing to do while the first was still on its
  /// way to failing.
  Future<void> _cacheWrites = Future<void>.value();

  /// Completed by the store's answer to the running [restore]: true when the
  /// delivery restored this product, false when it did not carry it. Null
  /// outside a restore, which is also how a second tap is turned away.
  Completer<bool>? _restoreAnswer;

  @override
  bool get adsRemoved => _offer.value.adsRemoved;

  @override
  ValueListenable<PurchaseOffer> get offer => _offer;

  @override
  Stream<PurchaseOutcome> get outcomes => _outcomes.stream;

  @override
  Future<void> start() async {
    try {
      // Subscribed before anything is asked of the store, because a purchase
      // left unfinished by a previous launch is re-delivered here as soon as
      // someone listens.
      _subscription ??= _iap.purchaseStream.listen(
        _onPurchases,
        // A dead stream leaves the cached entitlement standing rather than
        // taking the launch down with it — but it is also the only signal an
        // accepted request will ever get, and dropping it leaves a purchase
        // outstanding for the process and a restore waiting out a window it
        // would then report as a silence the store never made.
        onError: (Object error) {
          if (_restoreAnswer case final answer? when !answer.isCompleted) {
            answer.completeError(error);
          }
          // Only the unanswered request ends here. A stream that faulted says
          // nothing about whether a payment the store is holding was
          // canceled, so releasing that one would put a second billing flow
          // on top of it and reporting a failure would claim an answer
          // nobody gave.
          if (!_requestOutstanding) return;
          _requestOutstanding = false;
          _publishOffer();
          _outcomes.add(PurchaseOutcome.failed);
        },
      );
      if (!await _iap.isAvailable()) {
        // A store that says it is unavailable is not one this build can buy
        // from, so a price resolved earlier in the session stops being on
        // offer — the account or the storefront may have changed under it. A
        // call that merely threw is left alone: that is not the store saying
        // the product is gone.
        _product = null;
        _publishOffer();
        return;
      }
      final response = await _iap.queryProductDetails({removeAdsProductId});
      // A store that answered with an error, or listed the id under
      // `notFoundIDs` because it is not configured yet, leaves this null —
      // which is the same state as "not asked yet" and the state [buy]
      // refuses on.
      final matches = response.productDetails.where((details) => details.id == removeAdsProductId);
      _product = matches.isEmpty ? null : matches.first;
      _publishOffer();
      await _reconcileOwnership();
    } on Object {
      // Never rethrown: the launch does not depend on the store.
    }
  }

  @override
  Future<void> buy() async {
    final product = _product;
    if (product == null) {
      _outcomes.add(PurchaseOutcome.failed);
      return;
    }
    if (_awaitingStore) return;
    _requestOutstanding = true;
    _publishOffer();
    analytics.track('remove_ads_purchase_started', {'product_id': removeAdsProductId});
    try {
      final sent = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
      // A request the store never accepted produces no stream event, so this
      // is the only place it can be reported — and the only place that has to
      // release the attempt itself.
      if (sent) return;
      _requestOutstanding = false;
      _publishOffer();
      _outcomes.add(PurchaseOutcome.failed);
    } on Object {
      _requestOutstanding = false;
      _publishOffer();
      _outcomes.add(PurchaseOutcome.failed);
    }
  }

  /// Re-reads ownership from Play once per launch.
  ///
  /// Play does not replay ownership onto the purchase stream — that stream
  /// carries new billing flows — so without this a refund or a revocation
  /// would never reach a player who does not tap Restore, and the cache would
  /// outlive the entitlement it stands for. Querying purchases at every
  /// launch is Google's own guidance, for exactly that reason.
  ///
  /// Not done on the App Store: StoreKit 1's restore can put an Apple Account
  /// sign-in in front of the player, which is why Apple asks for restore to be
  /// user-initiated behind the Settings row. So on iOS a revocation is
  /// reflected when the player restores, and not before.
  ///
  /// Silent — nothing is on screen at launch to show an outcome to, and the
  /// player did not ask for a restore.
  Future<void> _reconcileOwnership() async {
    if (store != playStore) return;
    // A finished reconcile settles nothing while the store is still holding a
    // purchase: Play can settle a pending one while the app is suspended, and
    // no stream event is guaranteed to reach this process afterwards. An
    // unanswered request is not that — the store has not said it holds
    // anything — and asking again on its account would only race the sheet.
    if (_reconciled && !_storeHolding) return;
    await _restore(report: false);
    // Marked done only on a definitive answer. A reconcile that threw or ran
    // its wait out has checked nothing, and treating it as done would leave a
    // refunded player entitled for the rest of the process — the retry then
    // rides on Settings re-asking, which is why that no longer looks at the
    // price alone. Re-entry during the await is already refused by the
    // in-flight join above.
    _reconciled = _lastRestoreAnswered;
  }

  @override
  Future<void> restore() => _restore(report: true);

  Future<void> _restore({required bool report}) {
    if (_restoreInFlight case final live?) {
      // The same question is already out, and the store's one answer serves
      // both callers — a rival attempt would only give the running one a
      // second delivery to mistake for its own. A tap landing on the silent
      // launch reconcile takes it over on the way past, because a tap that
      // produced no message at all would read as broken.
      if (report) _restoreIsPlayers = true;
      return live;
    }
    _restoreIsPlayers = report;
    final attempt = _runRestore();
    _restoreInFlight = attempt;
    return attempt.whenComplete(() {
      _restoreInFlight = null;
      _restoreIsPlayers = true;
    });
  }

  /// Reads [_restoreIsPlayers] at the moment it speaks rather than capturing
  /// it, so a tap that took this attempt over gets the answer reported to it.
  Future<void> _runRestore() async {
    _answerHeldProduct = false;
    final grantsAtStart = _grantCount;
    // Every call still out belongs to an attempt that never got its own
    // answer, so this one may be handed one of theirs instead.
    final couldBeStale = _unansweredRestoreCalls > 0;
    final answer = _restoreAnswer = Completer<bool>();
    bool? restored;
    try {
      // Counted before the call, not after: Play adds its answer to the
      // stream before `restorePurchases` returns, so incrementing afterwards
      // would race a delivery that has already decremented.
      _unansweredRestoreCalls++;
      try {
        await _iap.restorePurchases();
      } on Object {
        // Nothing went out, so nothing is owed back.
        _unansweredRestoreCalls--;
        rethrow;
      }
      // The answer is a delivery on the purchase stream, not this future.
      restored = await answer.future.timeout(restoreSettleWindow);
    } on TimeoutException {
      // Never an answer, so never a revocation: the store said nothing, and
      // the cached entitlement is exactly as trustworthy as it was. Reported
      // as a timeout rather than a failure, because a restore that lands
      // afterwards still grants — calling that a failure would have been a
      // claim about an answer nobody had yet. The call stays counted: it is
      // still out, and whatever it eventually answers is not the next
      // attempt's.
      if (_restoreIsPlayers) _outcomes.add(PurchaseOutcome.timedOut);
    } on Object {
      if (_restoreIsPlayers) _outcomes.add(PurchaseOutcome.failed);
    } finally {
      _restoreAnswer = null;
      // What closes the reconcile is an answer it could act on. A positive
      // one is evidence whoever asked for it; a negative one rejected as
      // possibly stale is evidence of nothing, and closing on it would spend
      // the retry that exists to resolve exactly that ambiguity.
      _lastRestoreAnswered = switch (restored) {
        true => true,
        false => !couldBeStale,
        null => false,
      };
    }
    // A restored purchase has already reported and granted itself.
    if (restored ?? true) return;
    // A purchase that settled while this restore was out is newer than its
    // answer. Revoking on it would take away a payment the player just made
    // — the one thing this class must never do.
    if (_grantCount != grantsAtStart) return;
    // And an answer that may have been asked for by an earlier, timed-out
    // attempt says nothing about the purchases made since that one started,
    // so the counter above cannot see them. The store said nothing was
    // restored and the player is told so; only the cache is left alone.
    if (couldBeStale) {
      if (_restoreIsPlayers) _outcomes.add(PurchaseOutcome.nothingRestored);
      return;
    }
    // The store answered without this product, so the account does not own
    // it. Spec §4 makes that answer authoritative over the cache, which is
    // how a refund or a revoked purchase stops granting the entitlement.
    await _setAdsRemoved(removed: false);
    // Whether this also means the store is holding nothing depends on which
    // store answered, because the two restores do not report the same set.
    //
    // Play's `queryPurchases` returns everything it holds for the account,
    // pending transactions included, so a list without this product is Play
    // denying it holds one — and an attempt left marked would keep the row
    // shut for the rest of the process, since an empty delivery reaches no
    // [_apply]. Unless the same delivery carried this product in a held
    // state: "not owned yet" alongside a pending transaction describes one
    // that has not settled, not the absence of one.
    //
    // StoreKit reports completed restorable purchases only, so a transaction
    // awaiting approval is not in its answer to begin with. Its empty list
    // denies nothing, and releasing on it would put a second billing flow on
    // top of a deferred purchase the player is still waiting on.
    if (store == playStore && !_answerHeldProduct) {
      _storeHolding = false;
      _publishOffer();
    }
    if (_restoreIsPlayers) _outcomes.add(PurchaseOutcome.nothingRestored);
  }

  @override
  void recordOfferViewed(String placement) {
    analytics.track('remove_ads_viewed', {'placement': placement});
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    // Read before the answer clears the flag it depends on. A delivery only
    // counts as a restore when a player-initiated one is out to claim it: a
    // transaction the store re-delivers at launch, or one the silent
    // reconcile asked for, is not something the player did.
    final byPlayer = _restoreAnswer != null && _restoreIsPlayers;
    // Answered before anything is applied. Applying awaits a preferences
    // write and a `completePurchase` channel call, and a restore whose
    // settle window expired during those would report a failure over the
    // success the same delivery had already granted.
    _answerRestore(purchases);
    for (final purchase in purchases) {
      if (purchase.productID != removeAdsProductId) continue;
      await _apply(purchase, byPlayer: byPlayer);
    }
  }

  /// Settles a running [restore] from the delivery alone.
  ///
  /// A restore is answered by an empty delivery or by one carrying restored
  /// transactions, which is every shape the three stores send. Anything else
  /// — an unfinished purchase re-delivered at launch, an update for another
  /// product — is unrelated traffic, and letting it answer would revoke on a
  /// delivery that said nothing about a restore.
  void _answerRestore(List<PurchaseDetails> purchases) {
    final carriesRestored = purchases.any((p) => p.status == PurchaseStatus.restored);
    if (purchases.isNotEmpty && !carriesRestored) return;
    // One call out has been answered, whether or not anyone is still waiting
    // on it — a delivery that lands after its attempt gave up is exactly the
    // one this counts. Decremented here rather than where the attempt ends,
    // because it is the store answering that resolves the ambiguity, not the
    // asker walking away.
    if (_unansweredRestoreCalls > 0) _unansweredRestoreCalls--;
    if (_restoreAnswer case final answer? when !answer.isCompleted) {
      // Read from the same state the grant is, not from the status alone: a
      // purchase Play is still holding comes back rewritten to `restored`,
      // and reading that as ownership would leave a stale cache standing on
      // a transaction that has not settled.
      _answerHeldProduct = purchases.any((p) => p.productID == removeAdsProductId && _isHeldByStore(p));
      // Otherwise read off the status alone: a restored purchase whose
      // receipt is unreadable is still the store saying the account owns
      // this, and revoking on it would be the opposite of what it said.
      answer.complete(
        purchases.any(
          (p) => p.productID == removeAdsProductId && p.status == PurchaseStatus.restored && !_isHeldByStore(p),
        ),
      );
    }
  }

  Future<void> _apply(PurchaseDetails purchase, {required bool byPlayer}) async {
    final status = _isHeldByStore(purchase) ? PurchaseStatus.pending : purchase.status;
    if (_grants(status) && !_hasReceipt(purchase)) {
      // Neither granted nor completed. The store re-delivers an unfinished
      // transaction on the next launch, when the receipt may be readable,
      // and completing it now would burn a purchase the player paid for.
      //
      // Both facts move: the store answered the request, and what it
      // answered with is a transaction it is still holding — one the player
      // paid for — so reopening the row would answer the next tap with an
      // already-owned failure.
      _requestOutstanding = false;
      _storeHolding = true;
      _publishOffer();
      _outcomes.add(PurchaseOutcome.failed);
      return;
    }
    // The store has spoken about this product, so no request is unanswered
    // any more. Whether it is holding one is set rather than only cleared:
    // Play can hold a purchase for days and re-deliver it at the next launch,
    // where no tap set anything and a second `buyNonConsumable` for the same
    // non-consumable would go out on top of the one already pending.
    _requestOutstanding = false;
    _storeHolding = status == PurchaseStatus.pending;
    _publishOffer();
    switch (status) {
      case PurchaseStatus.pending:
        // Spec §4: a pending purchase grants nothing. It is also the one
        // status `completePurchase` throws on, which is why this returns
        // before the completion below rather than falling through to it.
        _outcomes.add(PurchaseOutcome.pending);
        return;
      case PurchaseStatus.canceled:
        _outcomes.add(PurchaseOutcome.canceled);
      case PurchaseStatus.error:
        _outcomes.add(PurchaseOutcome.failed);
      case PurchaseStatus.purchased:
        // One sale, one event. A transaction whose completion keeps failing
        // is re-delivered on every launch, and counting each of those would
        // report the same purchase daily.
        if (await _setAdsRemoved(removed: true)) {
          analytics.track('remove_ads_purchase_completed', {
            'product_id': removeAdsProductId,
            'store': store,
          });
        }
        _outcomes.add(PurchaseOutcome.purchased);
      case PurchaseStatus.restored:
        await _setAdsRemoved(removed: true);
        // `remove_ads_restored` counts restores the player asked for, so the
        // launch reconcile grants and caches without recording one — and
        // without a success message for a request nobody made.
        if (byPlayer) {
          analytics.track('remove_ads_restored', {'store': store});
          _outcomes.add(PurchaseOutcome.restored);
        }
    }
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } on Object {
      // The store re-delivers an unfinished transaction on the next launch,
      // and the entitlement the player already holds does not depend on this
      // call succeeding.
    }
  }

  /// Whether the store is still holding this transaction rather than having
  /// settled it.
  ///
  /// Play's own state does not survive its restore path:
  /// `InAppPurchaseAndroidPlatform.restorePurchases` maps every queried
  /// purchase to `PurchaseStatus.restored` after `fromPurchase` had read the
  /// real one, so a purchase Play is still holding arrives indistinguishable
  /// from a settled one — and spec §4 says a pending purchase grants nothing.
  /// The wrapper it was built from keeps the state that was overwritten.
  bool _isHeldByStore(PurchaseDetails purchase) {
    if (purchase.status == PurchaseStatus.pending) return true;
    // Only a status that grants can have been overwritten — the restore path
    // rewrites what it queried, not what it refused — so a cancellation is
    // still read from the status it arrived with.
    if (!_grants(purchase.status)) return false;
    if (purchase case final GooglePlayPurchaseDetails play) {
      // Play's own state has to say the purchase happened. Listing the states
      // to refuse would trust whatever the list forgot, and `unspecified` is
      // precisely the state that says nothing at all.
      return play.billingClientPurchase.purchaseState != PurchaseStateWrapper.purchased;
    }
    return false;
  }

  /// Whether [status] is one that hands the player the entitlement.
  bool _grants(PurchaseStatus status) => status == PurchaseStatus.purchased || status == PurchaseStatus.restored;

  /// The last of the client-side checks, and the only one this class adds.
  ///
  /// Spec §4 asks for the non-consumable to be verified client-side, and most
  /// of that has already happened below this line rather than here. StoreKit 2
  /// — the plugin's default on iOS — validates Apple's JWS itself and forwards
  /// only `.verified` transactions, dropping the rest before they reach Dart,
  /// in both `Transaction.updates` and `currentEntitlements`. Play's results
  /// arrive from the Store app over IPC; verifying their signature here would
  /// mean shipping the app's public key inside the binary, which is what
  /// Google's own guidance tells you not to do, and an attacker who can patch
  /// the check can patch the key with it.
  ///
  /// What is left for this class is the case neither of them covers: a
  /// transaction the plugin produced no purchase evidence for at all.
  /// StoreKit 1's receipt fetch returns an empty string when it fails, and
  /// granting off that would cache an entitlement nothing backs. Anything
  /// beyond this needs a server, which v1.0 does not ship.
  bool _hasReceipt(PurchaseDetails purchase) => purchase.verificationData.serverVerificationData.isNotEmpty;

  /// Returns whether this changed the entitlement, which is what tells a
  /// re-delivered transaction from the sale that first granted it.
  Future<bool> _setAdsRemoved({required bool removed}) async {
    if (removed) _grantCount++;
    final changed = _offer.value.adsRemoved != removed;
    _publishOffer(adsRemoved: removed);
    // The launch reconcile confirms the common case — still not entitled —
    // so writing unconditionally would put a preferences write on every
    // launch to store the value already there. A cache that does not already
    // hold this is the exception, whether because a write failed or because
    // one is still on its way: the queue below settles which.
    if (!changed && _cachedAdsRemoved == removed) return false;
    await _writeCache(removed: removed);
    // The caller counts sales off this, so a write retried for a grant that
    // is already in force is not a second sale.
    return changed;
  }

  /// Puts one entitlement write behind whatever is already queued, and
  /// completes when that write has had its turn.
  ///
  /// Awaited rather than fired off, because `_apply` finishes the transaction
  /// after this returns and the order of those two calls is what the
  /// acknowledgement depends on. Serializing is about ordering the writes
  /// against each other, not about declining to wait for them.
  Future<void> _writeCache({required bool removed}) {
    final queued = _cacheWrites.then((_) async {
      // A write ahead of this one may have already stored this value, and a
      // second trip to disk to store it again would be one the launch
      // reconcile pays on every start.
      if (_cachedAdsRemoved == removed) return;
      try {
        await settings.cacheAdsRemoved(removed: removed);
        _cachedAdsRemoved = removed;
      } on Object {
        // The cache is the offline seed, not the authority, so losing this
        // write costs an offline launch its entitlement until the next
        // restore. It must not cost the player the acknowledgement of a paid
        // transaction, which is what letting it propagate would do: the
        // caller would abort before `completePurchase`, and Play auto-refunds
        // a purchase left unacknowledged. Swallowed here rather than at the
        // caller so the queue itself never faults and the writes behind this
        // one still run.
      }
    });
    _cacheWrites = queued;
    return queued;
  }

  void _publishOffer({bool? adsRemoved}) {
    _offer.value = PurchaseOffer(
      adsRemoved: adsRemoved ?? _offer.value.adsRemoved,
      price: _product?.price,
      awaitingStore: _awaitingStore,
    );
  }

  /// Releases the purchase stream. The app never calls it — this object is
  /// app-scoped and the store's stream stays open for as long as the process
  /// does — but a test that builds one has to let it go.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _offer.dispose();
    await _outcomes.close();
  }
}
