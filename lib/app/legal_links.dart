// 🐦 Flutter imports:
import 'package:flutter/widgets.dart';

// 📦 Package imports:
import 'package:url_launcher/url_launcher.dart';

/// Opens the published legal and support pages.
///
/// The stores require a public HTTPS policy URL regardless, so the app links
/// to that page rather than shipping a second copy — one that would drift
/// from the published one the moment either changed.
///
/// The site serves a locale per path, matching the sibling landing sites
/// (`prism-defense.donminzzi.kr/ko/privacy`), so the link follows whichever
/// locale the app resolved rather than the device's raw preference.
class LegalLinks {
  const new({this._launch = launchUrl});

  final Launch _launch;

  static const _base = 'https://pebbix.donminzzi.kr';

  /// Korean for a Korean UI, English everywhere else — the same fallback the
  /// app itself applies, so the page never disagrees with the screen that
  /// linked to it.
  static String _segment(Locale locale) => locale.languageCode == 'ko' ? 'ko' : 'en';

  /// Opens the privacy policy. Support and contact live on the same page,
  /// which is how the sibling sites are laid out.
  ///
  /// A refusal — no browser, a platform that blocks the scheme — is
  /// swallowed: a settings row that throws is worse than one that does
  /// nothing, and there is no second route to offer.
  Future<void> openPrivacyPolicy(Locale locale) async {
    try {
      await _launch(Uri.parse('$_base/${_segment(locale)}/privacy'));
    } on Exception {
      return;
    }
  }
}

/// The `url_launcher` entry point, injected so tests assert the URL that
/// would reach the platform rather than a wrapper's claim about it.
typedef Launch = Future<bool> Function(Uri url);
