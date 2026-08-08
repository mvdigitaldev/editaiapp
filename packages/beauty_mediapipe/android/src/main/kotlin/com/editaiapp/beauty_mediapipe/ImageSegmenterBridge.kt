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
    private var facePartsSegmenter: ImageSegmenter? = null

    fun initialize(modelPath: String) {
        imageSegmenter?.close()
        imageSegmenter = null
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

    /// Segmentação semântica multiclass (selfie_multiclass_256x256): usa
    /// category mask, um byte de classe por pixel, em vez das confidence
    /// masks do segmenter binário de pessoa.
    fun initializeFaceParts(modelPath: String) {
        facePartsSegmenter?.close()
        facePartsSegmenter = null
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file not found: $modelPath")
        }

        val options = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(modelPath)
                    .build(),
            )
            .setRunningMode(RunningMode.IMAGE)
            .setOutputConfidenceMasks(false)
            .setOutputCategoryMask(true)
            .build()

        facePartsSegmenter = ImageSegmenter.createFromOptions(context, options)
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

    fun detectFaceParts(
        imageBytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
    ): Map<String, Any?>? {
        val segmenter = facePartsSegmenter ?: return null

        val bitmap = ImageBitmapDecoder.decode(imageBytes, width, height, rotation) ?: return null
        val mpImage = BitmapImageBuilder(bitmap).build()

        return try {
            mapCategoryMask(segmenter.segment(mpImage))
        } catch (e: Exception) {
            Log.e(TAG, "detectFaceParts failed", e)
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
        facePartsSegmenter?.close()
        facePartsSegmenter = null
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

    private fun mapCategoryMask(result: ImageSegmenterResult): Map<String, Any?>? {
        val mask: MPImage = result.categoryMask().orElse(null) ?: return null
        val maskWidth = mask.width
        val maskHeight = mask.height
        val buffer = ByteBufferExtractor.extract(mask)

        val bytes = ByteArray(maskWidth * maskHeight)
        val available = minOf(bytes.size, buffer.capacity())
        for (i in 0 until available) {
            bytes[i] = buffer.get(i)
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
