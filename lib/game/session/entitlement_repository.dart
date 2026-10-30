/// Read surface for the remove_ads entitlement. The store purchase
/// state is the source of truth; implementations cache it (spec §4).
abstract interface class EntitlementRepository {
  bool get adsRemoved;
}
