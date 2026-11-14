// 🐦 Flutter imports:
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/l10n/gen/app_localizations.dart';

export 'package:bubble_shooter/l10n/gen/app_localizations.dart';

/// Delegates for the app strings and the Material UI widget libraries.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
