package com.dartvision.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dartvision/detection"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setupDetector" -> {
                    // Native Detector (zaglab/DartsMind SDK) ist noch nicht integriert.
                    // Flutter-Seite fällt automatisch auf LocalDetectionService zurück.
                    methodChannel?.invokeMethod("onSetupFailed", mapOf("tag" to "detector"))
                    result.success("Native detector not available — using local fallback")
                }
                "detectFrame" -> {
                    result.error("NOT_AVAILABLE", "Native detector not integrated yet", null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
