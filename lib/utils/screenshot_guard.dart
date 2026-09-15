import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Toggles the OS-level "block screenshots & screen recording" flag for
/// screens that show a listing's private details — the property detail
/// page and the property list/grid. Backed by a small native
/// MethodChannel handler (see `MainActivity.kt`) that sets Android's
/// `FLAG_SECURE` on the activity window: screenshots taken while it's on
/// screen come back black, and the app's thumbnail in the Recents
/// switcher is blanked too.
///
/// No-op on web and non-Android platforms (there's no iOS project in
/// this app yet, and the web platform has no equivalent OS-level hook)
/// — [enable]/[disable] are safe to call unconditionally from any screen.
class ScreenshotGuard {
  ScreenshotGuard._();

  static const _channel = MethodChannel('ebn/screenshot_guard');

  /// How many currently-mounted screens want screenshots blocked. A
  /// count rather than a bool so that stacking two guarded screens (e.g.
  /// pushing the detail page from the list, both guarded) doesn't
  /// accidentally re-enable screenshots when the inner one pops first —
  /// the flag only actually clears once nothing guarded is left.
  static int _activeCount = 0;

  static Future<void> enable() async {
    _activeCount++;
    if (_activeCount > 1) return;
    await _setSecure(true);
  }

  static Future<void> disable() async {
    if (_activeCount == 0) return;
    _activeCount--;
    if (_activeCount > 0) return;
    await _setSecure(false);
  }

  static Future<void> _setSecure(bool secure) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Build without the native handler wired up yet — fail open
      // rather than crashing the screen.
    } on PlatformException {
      // Best-effort protection; an unsupported device just won't get it.
    }
  }
}

/// Mixin for a [State] whose screen should block screenshots/screen
/// recording for as long as it's mounted. Composes safely with other
/// guarded screens on the nav stack via [ScreenshotGuard]'s counter.
mixin ScreenshotGuardMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenshotGuard.enable();
  }

  @override
  void dispose() {
    ScreenshotGuard.disable();
    super.dispose();
  }
}
