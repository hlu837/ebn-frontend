import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Holds the app's current language choice above the Navigator (see
/// `main.dart`), so `MaterialApp.locale` is a live value instead of the old
/// hardcoded `AppLocalizations.fallbackLocale`.
///
/// [locale] starts out `null`, which tells `MaterialApp` to run
/// [AppLocalizations.localeResolutionCallback] against the device's own
/// locale (falling back to English if the device language isn't one of
/// [AppLocalizations.supportedLocales]). Once someone picks a language from
/// the menu, [setLocale] pins it explicitly, persists the choice with
/// `shared_preferences` (see [_restore], called from the constructor, for
/// where it's read back on the next launch), and every listening widget
/// (including `MaterialApp` itself) rebuilds with the new locale.
class LocaleController extends ChangeNotifier {
  LocaleController() {
    _restore();
  }

  static const _kLocaleKey = 'ebn_locale_v1';

  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kLocaleKey);
      if (saved == null || saved.isEmpty) return;
      final locale = Locale(saved);
      if (!AppLocalizations.isSupported(locale)) return;
      _locale = locale;
      notifyListeners();
    } catch (_) {
      // No saved preference yet, or storage unavailable — fall through and
      // keep following the device's own locale.
    }
  }

  /// Pins the app to [locale] and remembers the choice for next launch.
  /// Pass `null` to go back to following the device's own language
  /// setting (and clears any previously saved choice).
  Future<void> setLocale(Locale? locale) async {
    if (locale != null && !AppLocalizations.isSupported(locale)) {
      // Guard against pinning to a language we don't actually ship
      // strings for — fall back to English rather than silently no-op.
      locale = AppLocalizations.fallbackLocale;
    }
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_kLocaleKey);
      } else {
        await prefs.setString(_kLocaleKey, locale.languageCode);
      }
    } catch (_) {
      // Choice still applies for the rest of this session even if it
      // can't be persisted.
    }
  }
}
