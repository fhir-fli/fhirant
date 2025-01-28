import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

export 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Extension for [BuildContext] to access [AppLocalizations]
extension AppLocalizationsX on BuildContext {
  /// Get the [AppLocalizations] for the current context
  AppLocalizations get l10n => AppLocalizations.of(this);
}
