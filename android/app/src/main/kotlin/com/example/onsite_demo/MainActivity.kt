package com.example.onsite_demo

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Handles the `ebn/screenshot_guard` channel used by
/// `lib/utils/screenshot_guard.dart` to block screenshots and screen
/// recording (and blank the Recents thumbnail) while a property detail
/// or listing screen is on screen, by toggling `FLAG_SECURE` on the
/// activity window.
class MainActivity : FlutterActivity() {
    private val screenshotGuardChannel = "ebn/screenshot_guard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenshotGuardChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
