package com.editaiapp.beauty_mediapipe

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import java.io.File

class FaceLandmarkerBridge(private val context: Context) {
    private var faceLandmarker: FaceLandmarker? = null

    fun initialize(modelPath: String) {
        dispose()
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file not found: $modelPath")
        }

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(modelPath)
            .build()

        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        faceLandmarker = FaceLandmarker.createFromOptions(context, options)
    }

    fun detectFace(imageBytes: ByteArray, rotation: Int): Map<String, Any?>? {
        val landmarker = faceLandmarker ?: return null

        val bitmap = decodeBitmap(imageBytes, rotation) ?: return null
        val mpImage = BitmapImageBuilder(bitmap).build()

        return try {
            val result: FaceLandmarkerResult = landmarker.detect(mpImage)
            mapResult(result)
        } catch (e: Exception) {
            Log.e(TAG, "detectFace failed", e)
            null
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
    }

    fun dispose() {
        faceLandmarker?.close()
        faceLandmarker = null
    }

    private fun decodeBitmap(imageBytes: ByteArray, rotation: Int): Bitmap? {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            ?: return null

        if (rotation != 0) {
            val matrix = android.graphics.Matrix().apply {
                postRotate(rotation.toFloat())
            }
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (rotated != bitmap) {
                bitmap.recycle()
            }
            bitmap = rotated
        }
        return bitmap
    }

    private fun mapResult(result: FaceLandmarkerResult): Map<String, Any?>? {
        if (result.faceLandmarks().isEmpty()) {
            return null
        }

        val landmarks = result.faceLandmarks()[0]
        if (landmarks.isEmpty()) {
            return null
        }

        val mappedLandmarks = ArrayList<Map<String, Any>>(landmarks.size)
        var minX = 1.0
        var minY = 1.0
        var maxX = 0.0
        var maxY = 0.0

        landmarks.forEachIndexed { index, landmark ->
            val x = landmark.x().toDouble()
            val y = landmark.y().toDouble()
            minX = minOf(minX, x)
            minY = minOf(minY, y)
            maxX = maxOf(maxX, x)
            maxY = maxOf(maxY, y)
            mappedLandmarks.add(
                mapOf(
                    "index" to index,
                    "x" to x,
                    "y" to y,
                    "z" to landmark.z().toDouble(),
                    "visibility" to landmark.visibility().orElse(1.0f).toDouble(),
                ),
            )
        }

        val confidence = 0.9

        return mapOf(
            "confidence" to confidence,
            "landmarks" to mappedLandmarks,
            "boundingBox" to mapOf(
                "left" to minX,
                "top" to minY,
                "right" to maxX,
                "bottom" to maxY,
            ),
        )
    }

    companion object {
        private const val TAG = "FaceLandmarkerBridge"
    }
}
