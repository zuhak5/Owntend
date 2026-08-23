package app.owntend.mobile

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private var fullCanvasEnabled = true

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        applySystemUiMode()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            GoogleMobileAdsPlugin.registerNativeAdFactory(
                flutterEngine,
                "owntendNative",
                OwntendNativeAdFactory(this),
            )
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to register native ad factory", e)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "owntend/capabilities",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> {
                    result.success(
                        mapOf(
                            "shellVersion" to 2,
                            "capabilities" to mapOf(
                                "systemUi" to 2,
                                "nativeAds" to 2,
                                "platformEnv" to 1,
                            ),
                        ),
                    )
                }
                "getTimeZoneId" -> result.success(java.util.TimeZone.getDefault().id)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "owntend/system_ui",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFullCanvas" -> {
                    fullCanvasEnabled = call.arguments as? Boolean == true
                    applySystemUiMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                flutterEngine,
                "owntendNative",
            )
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to unregister native ad factory", e)
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applySystemUiMode()
        }
    }

    private fun applySystemUiMode() {
        if (fullCanvasEnabled) {
            hideSystemBars()
        } else {
            showSystemBars()
        }
    }

    private fun hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
    }

    private fun showSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, true)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            show(WindowInsetsCompat.Type.systemBars())
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
    }
}
