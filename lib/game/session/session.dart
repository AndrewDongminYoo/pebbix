// `admob_ads_gateway.dart` and `ump_consent_gateway.dart` are deliberately
// absent. Both import `google_mobile_ads`, and exporting them here would put
// its types in scope for every file that reaches for this barrel — which is
// most of the app, and exactly the plugin-ignorance `ads_gateway.dart` and
// `consent_gateway.dart` exist to hold. `native_gateways.dart` imports them
// directly; it is the only file that may.
export 'ad_setup.dart';
export 'ads_gateway.dart';
export 'analytics_sink.dart';
export 'consent_gateway.dart';
export 'entitlement_repository.dart';
export 'fakes.dart';
export 'game_session_controller.dart';
export 'game_session_state.dart';
export 'haptics_gateway.dart';
export 'native_gateways.dart';
export 'no_ads_gateways.dart';
export 'purchase_gateway.dart';
export 'session_config.dart';
export 'settings_repository.dart';
export 'shared_preferences_settings_repository.dart';
export 'store_purchase_gateway.dart';
