package com.editaiapp.beauty_mediapipe

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
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
            .setNumFaces(MAX_FACES)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        faceLandmarker = FaceLandmarker.createFromOptions(context, options)
    }

    fun detectFace(imageBytes: ByteArray, width: Int, height: Int, rotation: Int): Map<String, Any?>? {
        val faces = detectFaces(imageBytes, width, height, rotation)
        if (faces.isEmpty()) {
            return null
        }
        return faces.maxByOrNull { faceArea(it) }
    }

    fun detectFaces(imageBytes: ByteArray, width: Int, height: Int, rotation: Int): List<Map<String, Any?>> {
        val landmarker = faceLandmarker ?: return emptyList()

        val bitmap = ImageBitmapDecoder.decode(imageBytes, width, height, rotation) ?: return emptyList()
        val mpImage = BitmapImageBuilder(bitmap).build()

        return try {
            val result: FaceLandmarkerResult = landmarker.detect(mpImage)
            mapAllResults(result)
        } catch (e: Exception) {
            Log.e(TAG, "detectFaces failed", e)
            emptyList()
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

    private fun mapAllResults(result: FaceLandmarkerResult): List<Map<String, Any?>> {
        if (result.faceLandmarks().isEmpty()) {
            return emptyList()
        }
        return result.faceLandmarks()
            .mapNotNull { landmarks -> mapLandmarks(landmarks) }
            .sortedByDescending { faceArea(it) }
    }

    private fun mapLandmarks(landmarks: List<NormalizedLandmark>): Map<String, Any?>? {
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

        return mapOf(
            "confidence" to 0.9,
            "landmarks" to mappedLandmarks,
            "boundingBox" to mapOf(
                "left" to minX,
                "top" to minY,
                "right" to maxX,
                "bottom" to maxY,
            ),
        )
    }

    private fun faceArea(face: Map<String, Any?>): Double {
        @Suppress("UNCHECKED_CAST")
        val box = face["boundingBox"] as Map<String, Any?>
        val left = box["left"] as Double
        val top = box["top"] as Double
        val right = box["right"] as Double
        val bottom = box["bottom"] as Double
        return (right - left) * (bottom - top)
    }

    companion object {
        private const val TAG = "FaceLandmarkerBridge"
        const val MAX_FACES = 5
    }
}
