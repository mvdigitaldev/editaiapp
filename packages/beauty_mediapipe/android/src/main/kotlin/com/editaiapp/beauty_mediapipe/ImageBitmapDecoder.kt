package com.editaiapp.beauty_mediapipe

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix

/** Decodifica JPEG/PNG ou buffer RGBA bruto (width×height×4) para Bitmap. */
object ImageBitmapDecoder {
    fun decode(
        imageBytes: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
    ): Bitmap? {
        val rgbaSize = width * height * 4
        if (width > 0 && height > 0 && imageBytes.size == rgbaSize) {
            return rotate(rgbaToBitmap(imageBytes, width, height), rotation)
        }
        return decodeEncoded(imageBytes, rotation)
    }

    private fun rgbaToBitmap(imageBytes: ByteArray, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val offset = i * 4
            val r = imageBytes[offset].toInt() and 0xFF
            val g = imageBytes[offset + 1].toInt() and 0xFF
            val b = imageBytes[offset + 2].toInt() and 0xFF
            val a = imageBytes[offset + 3].toInt() and 0xFF
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }

    private fun decodeEncoded(imageBytes: ByteArray, rotation: Int): Bitmap? {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            ?: return null
        return rotate(decoded, rotation)
    }

    private fun rotate(bitmap: Bitmap, rotation: Int): Bitmap {
        if (rotation == 0 || rotation % 360 == 0) {
            return bitmap
        }
        val matrix = Matrix().apply {
            postRotate(rotation.toFloat())
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated != bitmap && !bitmap.isRecycled) {
            bitmap.recycle()
        }
        return rotated
    }
}
