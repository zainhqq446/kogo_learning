package com.example.kogo_voice_learning

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kogo/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> result.success(
                    launch(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                )
                "openTtsSettings" -> result.success(
                    launch(Intent("com.android.settings.TTS_SETTINGS")) ||
                        launch(Intent(Settings.ACTION_SETTINGS))
                )
                "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                else -> result.notImplemented()
            }
        }
    }

    private fun launch(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }
}
