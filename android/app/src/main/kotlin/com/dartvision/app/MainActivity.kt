package com.dartvision.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.lang.ref.WeakReference
import com.zaglab.dartsmind.dartsVision.Detector
import com.zaglab.dartsmind.dartsVision.DetectorDevice
import com.zaglab.dartsmind.dartsVision.DetectorDelegate
import com.zaglab.dartsmind.dartsVision.BBox
import com.zaglab.dartsmind.appSupport.MyApp

class MainActivity: FlutterActivity(), DetectorDelegate {
    private val CHANNEL = "com.dartvision/detection"
    private lateinit var detector: Detector
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize MyApp with this activity for model loading
        MyApp.Companion.setMainActivity(this)

        // Create detector
        detector = Detector(DetectorDevice.GPU, "detector", false)
        detector.delegate = WeakReference(this)

        // Setup method channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setupDetector" -> {
                    try {
                        detector.setup()
                        result.success("Detector setup initiated")
                    } catch (e: Exception) {
                        result.error("SETUP_ERROR", e.message, null)
                    }
                }
                "detectFrame" -> {
                    val byteArray = call.argument<ByteArray>("bitmapBytes")
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    if (byteArray != null) {
                        try {
                            val bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)
                            if (bitmap != null) {
                                detector.detectVideoBuffer(bitmap)
                                result.success("Detection started")
                            } else {
                                result.error("DECODE_ERROR", "Failed to decode bitmap", null)
                            }
                        } catch (e: Exception) {
                            result.error("DETECT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Bitmap bytes required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun setupSuccess(tag: String) {
        runOnUiThread {
            methodChannel?.invokeMethod("onSetupSuccess", mapOf("tag" to tag))
        }
    }

    override fun setupFailed(tag: String) {
        runOnUiThread {
            methodChannel?.invokeMethod("onSetupFailed", mapOf("tag" to tag))
        }
    }

    override fun cannotDetect(tag: String, errorCode: Int) {
        runOnUiThread {
            methodChannel?.invokeMethod("onCannotDetect", mapOf("tag" to tag, "errorCode" to errorCode))
        }
    }

    override fun processDetection(tag: String, bBoxes: List<BBox>, bufferW: Int, bufferH: Int, inferenceTime: Long?) {
        runOnUiThread {
            val boxes = bBoxes.map { box ->
                mapOf(
                    "minX" to box.minX,
                    "minY" to box.minY,
                    "maxX" to box.maxX,
                    "maxY" to box.maxY,
                    "cx" to box.cx,
                    "cy" to box.cy,
                    "w" to box.w,
                    "h" to box.h,
                    "cnf" to box.cnf,
                    "clsName" to box.clsName
                )
            }
            methodChannel?.invokeMethod("onDetectionResult", mapOf(
                "tag" to tag,
                "boxes" to boxes,
                "bufferW" to bufferW,
                "bufferH" to bufferH,
                "inferenceTime" to inferenceTime
            ))
        }
    }
}
