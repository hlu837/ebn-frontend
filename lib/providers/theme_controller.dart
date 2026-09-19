import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's current theme choice above the Navigator (see
/// `main.dart`), so `MaterialApp.themeMode` is a live value instead of the
/// old hardcoded `AppTheme.light`.
///
/// [mode] starts out [ThemeMode.light] by default, regardless of the
/// device's own setting. Once someone picks Light/Dark/System from
/// Settings, [setMode] pins it, persists the choice with
/// `shared_preferences` (see [_restore], called from the constructor, for
/// where it's read back on the next launch), and every listening widget
/// (including `MaterialApp` itself) rebuilds with the new theme.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _restore();
  }

  static const _kThemeModeKey = 'ebn_theme_mode_v1';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemeModeKey);
      if (saved == null) return;
      final restored = _fromKey(saved);
      if (restored == null) return;
      _mode = restored;
      notifyListeners();
    } catch (_) {
      // No saved preference yet, or storage unavailable — fall through and
      // keep following the device's own theme setting.
    }
  }

  /// Pins the app to [mode] and remembers the choice for next launch.
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _toKey(mode));
    } catch (_) {
      // Choice still applies for the rest of this session even if it
      // can't be persisted.
    }
  }

  static String _toKey(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode? _fromKey(String key) => switch (key) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
}
