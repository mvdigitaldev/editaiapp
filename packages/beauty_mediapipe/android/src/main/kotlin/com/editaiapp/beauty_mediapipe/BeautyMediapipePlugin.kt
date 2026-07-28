package com.editaiapp.beauty_mediapipe

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class BeautyMediapipePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var faceBridge: FaceLandmarkerBridge? = null
    private var poseBridge: PoseLandmarkerBridge? = null
    private var segmenterBridge: ImageSegmenterBridge? = null
    private var exportBackend: BodyReshapeVulkanBackend? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        faceBridge = FaceLandmarkerBridge(binding.applicationContext)
        poseBridge = PoseLandmarkerBridge(binding.applicationContext)
        segmenterBridge = ImageSegmenterBridge(binding.applicationContext)
        exportBackend = BodyReshapeVulkanBackend()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        faceBridge?.dispose()
        faceBridge = null
        poseBridge?.dispose()
        poseBridge = null
        segmenterBridge?.dispose()
        segmenterBridge = null
        exportBackend?.dispose()
        exportBackend = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val facePath = call.argument<String>("faceModelPath")
                val posePath = call.argument<String>("poseModelPath")
                val segmenterPath = call.argument<String>("segmenterModelPath")
                if (facePath.isNullOrBlank()) {
                    result.error("invalid_args", "faceModelPath is required", null)
                    return
                }
                try {
                    faceBridge?.initialize(facePath)
                    if (!posePath.isNullOrBlank()) {
                        poseBridge?.initialize(posePath)
                    }
                    if (!segmenterPath.isNullOrBlank()) {
                        segmenterBridge?.initialize(segmenterPath)
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    result.error("init_failed", e.message ?: e.toString(), null)
                }
            }

            "detectFace" -> {
                val bridge = faceBridge
                if (bridge == null) {
                    result.error("not_initialized", "Face bridge unavailable", null)
                    return
                }
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val rotation = call.argument<Int>("rotation") ?: 0
                if (bytes == null || bytes.isEmpty()) {
                    result.error("invalid_args", "bytes is required", null)
                    return
                }
                try {
                    val mapped = bridge.detectFace(bytes, width, height, rotation)
                    result.success(mapped)
                } catch (e: Throwable) {
                    result.error("detect_failed", e.message ?: e.toString(), null)
                }
            }

            "detectPose" -> {
                val bridge = poseBridge
                if (bridge == null) {
                    result.error("not_initialized", "Pose bridge unavailable", null)
                    return
                }
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val rotation = call.argument<Int>("rotation") ?: 0
                if (bytes == null || bytes.isEmpty()) {
                    result.error("invalid_args", "bytes is required", null)
                    return
                }
                try {
                    val mapped = bridge.detectPose(bytes, width, height, rotation)
                    result.success(mapped)
                } catch (e: Throwable) {
                    result.error("detect_failed", e.message ?: e.toString(), null)
                }
            }

            "detectPersonMask" -> {
                val bridge = segmenterBridge
                if (bridge == null) {
                    result.error("not_initialized", "Segmenter bridge unavailable", null)
                    return
                }
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val rotation = call.argument<Int>("rotation") ?: 0
                if (bytes == null || bytes.isEmpty()) {
                    result.error("invalid_args", "bytes is required", null)
                    return
                }
                try {
                    val mapped = bridge.detectPersonMask(bytes, width, height, rotation)
                    result.success(mapped)
                } catch (e: Throwable) {
                    result.error("detect_failed", e.message ?: e.toString(), null)
                }
            }

            "dispose" -> {
                faceBridge?.dispose()
                poseBridge?.dispose()
                segmenterBridge?.dispose()
                result.success(null)
            }

            "probeExportCapabilities" -> {
                result.success(
                    exportBackend?.capabilities() ?: mapOf(
                        "metal" to false,
                        "vulkan" to false,
                        "openGlEs" to false,
                        "nativeJpegEncode" to false,
                    ),
                )
            }

            "warpExport" -> {
                val backend = exportBackend
                if (backend == null || !backend.isAvailable()) {
                    result.error("unavailable", "GLES export unavailable", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                if (args == null) {
                    result.error("invalid_args", "args required", null)
                    return
                }
                try {
                    result.success(backend.warpExport(args))
                } catch (e: Throwable) {
                    result.error("warp_failed", e.message ?: e.toString(), null)
                }
            }

            "encodeJpeg" -> {
                val backend = exportBackend
                if (backend == null) {
                    result.error("unavailable", "JPEG encode unavailable", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                if (args == null) {
                    result.error("invalid_args", "args required", null)
                    return
                }
                try {
                    result.success(backend.encodeJpeg(args))
                } catch (e: Throwable) {
                    result.error("encode_failed", e.message ?: e.toString(), null)
                }
            }

            "releaseExportResource" -> result.success(null)

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.editaiapp/beauty_mediapipe"
    }
}
