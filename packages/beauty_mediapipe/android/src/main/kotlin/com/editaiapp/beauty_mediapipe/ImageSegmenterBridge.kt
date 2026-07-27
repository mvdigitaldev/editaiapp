package com.editaiapp.beauty_mediapipe

import android.content.Context
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import java.io.File
import java.nio.ByteOrder

class ImageSegmenterBridge(private val context: Context) {
    private var imageSegmenter: ImageSegmenter? = null

    fun initialize(modelPath: String) {
        dispose()
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file not found: $modelPath")
        }

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(modelPath)
            .build()

        val options = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setOutputConfidenceMasks(true)
            .setOutputCategoryMask(false)
            .build()

        imageSegmenter = ImageSegmenter.createFromOptions(context, options)
    }

    fun detectPersonMask(
        imageBytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
    ): Map<String, Any?>? {
        val segmenter = imageSegmenter ?: return null

        val bitmap = ImageBitmapDecoder.decode(imageBytes, width, height, rotation) ?: return null
        val mpImage = BitmapImageBuilder(bitmap).build()

        return try {
            val result: ImageSegmenterResult = segmenter.segment(mpImage)
            mapResult(result)
        } catch (e: Exception) {
            Log.e(TAG, "detectPersonMask failed", e)
            null
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
    }

    fun dispose() {
        imageSegmenter?.close()
        imageSegmenter = null
    }

    private fun mapResult(result: ImageSegmenterResult): Map<String, Any?>? {
        val masks = result.confidenceMasks().orElse(null)
        if (masks == null || masks.isEmpty()) {
            return null
        }

        // Selfie: background=0, person=1. Alguns builds devolvem só a máscara da pessoa.
        val personMask: MPImage = if (masks.size > 1) masks[1] else masks[0]
        val maskWidth = personMask.width
        val maskHeight = personMask.height
        val floatBuffer = ByteBufferExtractor.extract(personMask)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        val bytes = ByteArray(maskWidth * maskHeight)
        for (i in bytes.indices) {
            val v = floatBuffer.get(i).coerceIn(0f, 1f)
            bytes[i] = (v * 255f).toInt().toByte()
        }

        return mapOf(
            "bytes" to bytes,
            "width" to maskWidth,
            "height" to maskHeight,
        )
    }

    companion object {
        private const val TAG = "ImageSegmenterBridge"
    }
}
