// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

/// Project-owned surface over the UMP consent flow (spec §2 package G).
/// The real adapter arrives with the AdMob work; nothing above this
/// interface may import an ad SDK.
abstract interface class ConsentGateway {
  /// Refreshes consent state at launch and shows the form when the current
  /// state requires one.
  ///
  /// Never throws. Consent is a precondition for *ads*, not for play —
  /// spec §Privacy requires that ATT denial, and by extension any consent
  /// failure, never blocks gameplay.
  Future<void> gather();

  /// Whether ads may be requested right now. False until [gather] has
  /// resolved the state, so an ad request can never precede consent: the
  /// failure mode of a bug here is silence, never ads without consent.
  bool get canRequestAds;

  /// Whether the store region requires a reopenable privacy entry point.
  /// Settings offers its row only when this is true.
  ///
  /// Observable, not a plain bool: [gather] deliberately does not block the
  /// player, so Settings can be open before the requirement is known, and a
  /// row that snapshotted it would stay disabled for that whole visit.
  ValueListenable<bool> get privacyOptionsRequired;

  /// Reopens the privacy options form from Settings. Never throws.
  Future<void> showPrivacyOptions();
}
