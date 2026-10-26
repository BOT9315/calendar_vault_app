package com.ankushkumar.calendarvault

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required for local_auth v3 biometric prompts
// (BiometricPrompt needs a FragmentActivity host on Android)
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.ankushkumar.calendarvault/app_icon"

    private val aliases = listOf(
        "CalendarAlias",
        "CalculatorAlias",
        "NotesAlias",
        "ClockAlias",
        "WeatherAlias"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentIcon" -> {
                    val activeAlias = getActiveAlias()
                    result.success(activeAlias)
                }
                "changeIcon" -> {
                    val targetAlias = call.argument<String>("alias")
                    if (targetAlias != null && aliases.contains(targetAlias)) {
                        val success = switchAlias(targetAlias)
                        result.success(success)
                    } else {
                        result.error("INVALID_ALIAS", "Unknown alias: $targetAlias", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getActiveAlias(): String {
        for (alias in aliases) {
            val componentName = ComponentName(packageName, "$packageName.$alias")
            val state = packageManager.getComponentEnabledSetting(componentName)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias
            }
        }
        return "CalendarAlias"
    }

    private fun switchAlias(targetAlias: String): Boolean {
        return try {
            val pm = packageManager
            for (alias in aliases) {
                val componentName = ComponentName(packageName, "$packageName.$alias")
                if (alias == targetAlias) {
                    pm.setComponentEnabledSetting(
                        componentName,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP
                    )
                } else {
                    pm.setComponentEnabledSetting(
                        componentName,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP
                    )
                }
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
