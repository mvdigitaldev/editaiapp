package com.editaiapp.beauty_mediapipe

import android.opengl.GLES20
import android.opengl.GLES30
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.egl.EGLSurface
import kotlin.math.cbrt
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Backend nativo do Grupo A (pele) — Sprint 1.
 *
 * Preferência: GLES 3 com texturas R16F (guided filter + frequency separation
 * em luz linear). Fallback: implementação nativa CPU idêntica ao
 * `SkinRetouchEngine` Dart (ainda muito mais rápida que o isolate Dart).
 */
class SkinRetouchBackend {
    private var egl: EGL10? = null
    private var eglDisplay: EGLDisplay? = EGL10.EGL_NO_DISPLAY
    private var eglContext: EGLContext? = EGL10.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface? = EGL10.EGL_NO_SURFACE
    private var gles3 = false
    private var extractProg = 0
    private var blurHProg = 0
    private var blurVProg = 0
    private var squareProg = 0
    private var coeffProg = 0
    private var applyProg = 0
    private var compositeProg = 0
    private var darkProg = 0
    private var available = false

    init {
        try {
            initEgl()
            if (gles3) {
                extractProg = buildProgram(VS, FS_EXTRACT)
                blurHProg = buildProgram(VS, FS_BLUR_H)
                blurVProg = buildProgram(VS, FS_BLUR_V)
                squareProg = buildProgram(VS, FS_SQUARE)
                coeffProg = buildProgram(VS, FS_COEFF)
                applyProg = buildProgram(VS, FS_APPLY)
                compositeProg = buildProgram(VS, FS_COMPOSITE)
                darkProg = buildProgram(VS, FS_DARK)
                available = extractProg != 0 && blurHProg != 0 && compositeProg != 0
            }
        } catch (_: Throwable) {
            available = false
            releaseEgl()
        }
    }

    fun isGpuAvailable(): Boolean = available

    /** Sempre true — CPU nativo cobre o fallback. */
    fun isAvailable(): Boolean = true

    fun skinRetouch(args: Map<String, Any?>): ByteArray {
        val rgba = (args["rgba"] as? ByteArray)?.clone() ?: error("invalid_args")
        val width = args["width"] as? Int ?: error("invalid_args")
        val height = args["height"] as? Int ?: error("invalid_args")
        val skin = args["skinWeights"] as? ByteArray ?: error("invalid_args")
        require(width > 0 && height > 0 && rgba.size == width * height * 4)
        require(skin.size == width * height)

        val underEye = args["underEyeWeights"] as? ByteArray ?: ByteArray(width * height)
        val smooth = (args["smooth"] as? Number)?.toFloat() ?: 0f
        val acne = (args["acne"] as? Number)?.toFloat() ?: 0f
        val wrinkles = (args["wrinkles"] as? Number)?.toFloat() ?: 0f
        val darkCircles = (args["darkCircles"] as? Number)?.toFloat() ?: 0f
        val shine = (args["shine"] as? Number)?.toFloat() ?: 0f
        val faceEdgePx = (args["faceEdgePx"] as? Number)?.toFloat()
            ?: max(width, height).toFloat()

        if (available) {
            try {
                return skinRetouchGpu(
                    rgba, width, height, skin, underEye,
                    smooth, acne, wrinkles, darkCircles, shine, faceEdgePx,
                )
            } catch (_: Throwable) {
                // cai no CPU nativo
            }
        }
        return skinRetouchCpu(
            rgba, width, height, skin, underEye,
            smooth, acne, wrinkles, darkCircles, shine, faceEdgePx,
        )
    }

    fun dispose() {
        if (available) {
            makeCurrent()
            val progs = intArrayOf(
                extractProg, blurHProg, blurVProg, squareProg,
                coeffProg, applyProg, compositeProg, darkProg,
            )
            for (p in progs) {
                if (p != 0) GLES20.glDeleteProgram(p)
            }
        }
        releaseEgl()
        available = false
    }

    // -------------------------------------------------------------------------
    // GLES path
    // -------------------------------------------------------------------------

    private fun skinRetouchGpu(
        rgba: ByteArray,
        width: Int,
        height: Int,
        skin: ByteArray,
        underEye: ByteArray,
        smooth: Float,
        acne: Float,
        wrinkles: Float,
        darkCircles: Float,
        shine: Float,
        faceEdgePx: Float,
    ): ByteArray {
        makeCurrent()
        val fineRadius = max(1, min(18, (faceEdgePx * 0.012f).toInt()))
        val coarseRadius = max(3, min(48, fineRadius * 3))
        val blemishRadius = max(6, min(96, coarseRadius * 2))

        val srcTex = uploadRgba(rgba, width, height)
        val skinTex = uploadR8(skin, width, height)
        val eyeTex = uploadR8(underEye, width, height)

        val luma = createR16F(width, height)
        val scratchA = createR16F(width, height)
        val scratchB = createR16F(width, height)
        val meanI = createR16F(width, height)
        val meanII = createR16F(width, height)
        val meanA = createR16F(width, height)
        val meanB = createR16F(width, height)
        val fine = createR16F(width, height)
        val coarse = createR16F(width, height)
        val blemish = createR16F(width, height)
        val outTex = createRgba(width, height)

        val fbo = IntArray(1)
        GLES20.glGenFramebuffers(1, fbo, 0)

        drawTo(fbo[0], luma[0], width, height, extractProg) {
            bindTex(extractProg, GLES20.GL_TEXTURE0, srcTex, "uSrc", 0)
        }

        guidedFilter(
            fbo[0], src = luma[0], scratchA[0], scratchB[0],
            meanI[0], meanII[0], meanA[0], meanB[0], out = fine[0],
            width, height, fineRadius, 2.5e-4f,
        )
        guidedFilter(
            fbo[0], src = luma[0], scratchA[0], scratchB[0],
            meanI[0], meanII[0], meanA[0], meanB[0], out = coarse[0],
            width, height, coarseRadius, 1.2e-3f,
        )
        if (acne > 0f) {
            boxBlur(fbo[0], luma[0], scratchA[0], blemish[0], width, height, blemishRadius)
        }

        val skinRef = weightedMeanLuma(rgba, skin, width, height, 150)

        drawTo(fbo[0], outTex[0], width, height, compositeProg) {
            bindTex(compositeProg, GLES20.GL_TEXTURE0, srcTex, "uSrc", 0)
            bindTex(compositeProg, GLES20.GL_TEXTURE1, luma[0], "uLuma", 1)
            bindTex(compositeProg, GLES20.GL_TEXTURE2, fine[0], "uFine", 2)
            bindTex(compositeProg, GLES20.GL_TEXTURE3, coarse[0], "uCoarse", 3)
            bindTex(compositeProg, GLES20.GL_TEXTURE4, blemish[0], "uBlemish", 4)
            bindTex(compositeProg, GLES20.GL_TEXTURE5, skinTex, "uSkin", 5)
            GLES20.glUniform1f(loc(compositeProg, "uSmooth"), smooth)
            GLES20.glUniform1f(loc(compositeProg, "uAcne"), acne)
            GLES20.glUniform1f(loc(compositeProg, "uWrinkles"), wrinkles)
            GLES20.glUniform1f(loc(compositeProg, "uShine"), shine)
            GLES20.glUniform1f(loc(compositeProg, "uSkinRef"), skinRef)
            GLES20.glUniform1f(loc(compositeProg, "uHighKeep"), 0.70f)
            GLES20.glUniform1f(loc(compositeProg, "uMidKeep"), 0.30f)
        }

        if (darkCircles > 0f) {
            val (refL, refA, refB) = skinReferenceOklab(rgba, skin, underEye, width, height)
            // Ping-pong: não ler e escrever a mesma textura.
            val darkOut = createRgba(width, height)
            drawTo(fbo[0], darkOut[0], width, height, darkProg) {
                bindTex(darkProg, GLES20.GL_TEXTURE0, outTex[0], "uSrc", 0)
                bindTex(darkProg, GLES20.GL_TEXTURE1, skinTex, "uSkin", 1)
                bindTex(darkProg, GLES20.GL_TEXTURE2, eyeTex, "uEye", 2)
                GLES20.glUniform1f(loc(darkProg, "uIntensity"), darkCircles)
                GLES20.glUniform1f(loc(darkProg, "uRefL"), refL)
                GLES20.glUniform1f(loc(darkProg, "uRefA"), refA)
                GLES20.glUniform1f(loc(darkProg, "uRefB"), refB)
            }
            // Troca: ler do darkOut no final.
            GLES20.glDeleteTextures(1, outTex, 0)
            outTex[0] = darkOut[0]
        }

        GLES20.glFinish()
        val out = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, outTex[0], 0,
        )
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, out)
        val bytes = ByteArray(width * height * 4)
        out.rewind()
        out.get(bytes)
        flipVertically(bytes, width, height)

        val texIds = intArrayOf(
            srcTex, skinTex, eyeTex,
            luma[0], scratchA[0], scratchB[0], meanI[0], meanII[0],
            meanA[0], meanB[0], fine[0], coarse[0], blemish[0], outTex[0],
        )
        GLES20.glDeleteTextures(texIds.size, texIds, 0)
        GLES20.glDeleteFramebuffers(1, fbo, 0)
        return bytes
    }

    private fun guidedFilter(
        fbo: Int,
        src: Int, scratchA: Int, scratchB: Int,
        meanI: Int, meanII: Int, meanA: Int, meanB: Int,
        out: Int,
        width: Int, height: Int, radius: Int, eps: Float,
    ) {
        boxBlur(fbo, src, scratchA, meanI, width, height, radius)
        drawTo(fbo, scratchB, width, height, squareProg) {
            bindTex(squareProg, GLES20.GL_TEXTURE0, src, "uSrc", 0)
        }
        boxBlur(fbo, scratchB, scratchA, meanII, width, height, radius)
        drawTo(fbo, scratchA, width, height, coeffProg) {
            bindTex(coeffProg, GLES20.GL_TEXTURE0, meanI, "uMeanI", 0)
            bindTex(coeffProg, GLES20.GL_TEXTURE1, meanII, "uMeanII", 1)
            GLES20.glUniform1f(loc(coeffProg, "uEps"), eps)
            GLES20.glUniform1i(loc(coeffProg, "uMode"), 0) // a
        }
        drawTo(fbo, scratchB, width, height, coeffProg) {
            bindTex(coeffProg, GLES20.GL_TEXTURE0, meanI, "uMeanI", 0)
            bindTex(coeffProg, GLES20.GL_TEXTURE1, meanII, "uMeanII", 1)
            GLES20.glUniform1f(loc(coeffProg, "uEps"), eps)
            GLES20.glUniform1i(loc(coeffProg, "uMode"), 1) // b
        }
        boxBlur(fbo, scratchA, meanI, meanA, width, height, radius)
        boxBlur(fbo, scratchB, meanI, meanB, width, height, radius)
        drawTo(fbo, out, width, height, applyProg) {
            bindTex(applyProg, GLES20.GL_TEXTURE0, src, "uSrc", 0)
            bindTex(applyProg, GLES20.GL_TEXTURE1, meanA, "uMeanA", 1)
            bindTex(applyProg, GLES20.GL_TEXTURE2, meanB, "uMeanB", 2)
        }
    }

    private fun boxBlur(
        fbo: Int, src: Int, tmp: Int, dst: Int,
        width: Int, height: Int, radius: Int,
    ) {
        drawTo(fbo, tmp, width, height, blurHProg) {
            bindTex(blurHProg, GLES20.GL_TEXTURE0, src, "uSrc", 0)
            GLES20.glUniform1i(loc(blurHProg, "uRadius"), radius)
            GLES20.glUniform2f(loc(blurHProg, "uSize"), width.toFloat(), height.toFloat())
        }
        drawTo(fbo, dst, width, height, blurVProg) {
            bindTex(blurVProg, GLES20.GL_TEXTURE0, tmp, "uSrc", 0)
            GLES20.glUniform1i(loc(blurVProg, "uRadius"), radius)
            GLES20.glUniform2f(loc(blurVProg, "uSize"), width.toFloat(), height.toFloat())
        }
    }

    // -------------------------------------------------------------------------
    // CPU fallback (paridade com SkinRetouchEngine Dart)
    // -------------------------------------------------------------------------

    private fun skinRetouchCpu(
        rgba: ByteArray,
        width: Int,
        height: Int,
        skin: ByteArray,
        underEye: ByteArray,
        smooth: Float,
        acne: Float,
        wrinkles: Float,
        darkCircles: Float,
        shine: Float,
        faceEdgePx: Float,
    ): ByteArray {
        val pixels = width * height
        val output = rgba.copyOf()
        if (smooth <= 0f && acne <= 0f && wrinkles <= 0f && darkCircles <= 0f && shine <= 0f) {
            return output
        }

        val luma = FloatArray(pixels)
        for (p in 0 until pixels) {
            val i = p * 4
            val r = srgbToLinear(output[i].toInt() and 0xFF)
            val g = srgbToLinear(output[i + 1].toInt() and 0xFF)
            val b = srgbToLinear(output[i + 2].toInt() and 0xFF)
            luma[p] = (0.2126f * r + 0.7152f * g + 0.0722f * b)
        }

        val fineRadius = max(1, min(18, (faceEdgePx * 0.012f).toInt()))
        val coarseRadius = max(3, min(48, fineRadius * 3))
        val fineBase = guidedFilterSelf(luma, width, height, fineRadius, 2.5e-4f)
        val coarseBase = guidedFilterSelf(luma, width, height, coarseRadius, 1.2e-3f)
        val blemishRef = if (acne > 0f) {
            boxMean(luma, width, height, max(6, min(96, coarseRadius * 2)))
        } else {
            null
        }

        val smoothStrength = min(1f, smooth + wrinkles * 0.5f)
        val midKeep = 1f - (1f - 0.30f) * smoothStrength
        val highKeep = 1f - (1f - 0.70f) * smoothStrength
        val skinRef = weightedMeanLuma(output, skin, width, height, 150)
        val shineKnee = skinRef * 1.18f

        for (p in 0 until pixels) {
            val weight = (skin[p].toInt() and 0xFF) / 255f
            if (weight <= 0f) continue
            val original = luma[p]
            val low = coarseBase[p]
            val fine = fineBase[p]
            val mid = fine - low
            val high = original - fine
            var lowMid = low + mid * midKeep

            if (blemishRef != null) {
                val reference = blemishRef[p]
                val deficit = reference - fine
                val threshold = max(reference * 0.05f, 0.0015f)
                if (deficit > threshold) {
                    val spot = ((deficit - threshold) / threshold).coerceIn(0f, 1f)
                    lowMid += deficit * acne * spot
                }
            }
            if (shine > 0f && shineKnee > 0f && lowMid > shineKnee) {
                val excess = lowMid - shineKnee
                lowMid = shineKnee + excess * (1f - 0.7f * shine)
            }

            val target = lowMid + high * highKeep
            val blended = original + (target - original) * weight
            if (blended == original) continue

            val i = p * 4
            val rLin = srgbToLinear(output[i].toInt() and 0xFF)
            val gLin = srgbToLinear(output[i + 1].toInt() and 0xFF)
            val bLin = srgbToLinear(output[i + 2].toInt() and 0xFF)
            if (original <= 1e-5f) {
                val v = linearToSrgb8(blended.coerceIn(0f, 1f))
                output[i] = v; output[i + 1] = v; output[i + 2] = v
                continue
            }
            val factor = (blended / original).coerceIn(0f, 4f)
            output[i] = linearToSrgb8((rLin * factor).coerceIn(0f, 1f))
            output[i + 1] = linearToSrgb8((gLin * factor).coerceIn(0f, 1f))
            output[i + 2] = linearToSrgb8((bLin * factor).coerceIn(0f, 1f))
        }

        if (darkCircles > 0f) {
            applyDarkCircles(output, skin, underEye, pixels, darkCircles)
        }
        return output
    }

    private fun guidedFilterSelf(
        src: FloatArray, width: Int, height: Int, radius: Int, eps: Float,
    ): FloatArray {
        val meanI = boxMean(src, width, height, radius)
        val squared = FloatArray(src.size) { src[it] * src[it] }
        val meanII = boxMean(squared, width, height, radius)
        val a = FloatArray(src.size)
        val b = FloatArray(src.size)
        for (i in src.indices) {
            val mean = meanI[i]
            val variance = meanII[i] - mean * mean
            val ai = if (variance <= 0f) 0f else variance / (variance + eps)
            a[i] = ai
            b[i] = mean * (1f - ai)
        }
        val meanA = boxMean(a, width, height, radius)
        val meanB = boxMean(b, width, height, radius)
        return FloatArray(src.size) { meanA[it] * src[it] + meanB[it] }
    }

    private fun boxMean(src: FloatArray, width: Int, height: Int, radius: Int): FloatArray {
        val iw = width + 1
        val integral = DoubleArray(iw * (height + 1))
        for (y in 0 until height) {
            var rowSum = 0.0
            val srcRow = y * width
            val cur = (y + 1) * iw
            val prev = y * iw
            for (x in 0 until width) {
                rowSum += src[srcRow + x]
                integral[cur + x + 1] = integral[prev + x + 1] + rowSum
            }
        }
        val out = FloatArray(src.size)
        for (y in 0 until height) {
            val y0 = max(0, y - radius)
            val y1 = min(height - 1, y + radius)
            for (x in 0 until width) {
                val x0 = max(0, x - radius)
                val x1 = min(width - 1, x + radius)
                val count = (y1 - y0 + 1) * (x1 - x0 + 1)
                val sum = integral[(y1 + 1) * iw + (x1 + 1)] -
                    integral[y0 * iw + (x1 + 1)] -
                    integral[(y1 + 1) * iw + x0] +
                    integral[y0 * iw + x0]
                out[y * width + x] = (sum / count).toFloat()
            }
        }
        return out
    }

    private fun applyDarkCircles(
        output: ByteArray,
        skin: ByteArray,
        underEye: ByteArray,
        pixels: Int,
        intensity: Float,
    ) {
        var sumL = 0.0; var sumA = 0.0; var sumB = 0.0; var count = 0
        val lab = FloatArray(3)
        for (p in 0 until pixels) {
            if ((skin[p].toInt() and 0xFF) < 180 || (underEye[p].toInt() and 0xFF) > 0) continue
            val i = p * 4
            linearRgbToOklab(
                srgbToLinear(output[i].toInt() and 0xFF),
                srgbToLinear(output[i + 1].toInt() and 0xFF),
                srgbToLinear(output[i + 2].toInt() and 0xFF),
                lab,
            )
            sumL += lab[0]; sumA += lab[1]; sumB += lab[2]
            count++
        }
        if (count == 0) return
        val refL = (sumL / count).toFloat()
        val refA = (sumA / count).toFloat()
        val refB = (sumB / count).toFloat()
        val rgb = FloatArray(3)
        for (p in 0 until pixels) {
            val region = (underEye[p].toInt() and 0xFF) / 255f
            if (region <= 0f) continue
            val sk = (skin[p].toInt() and 0xFF) / 255f
            if (sk <= 0f) continue
            val i = p * 4
            linearRgbToOklab(
                srgbToLinear(output[i].toInt() and 0xFF),
                srgbToLinear(output[i + 1].toInt() and 0xFF),
                srgbToLinear(output[i + 2].toInt() and 0xFF),
                lab,
            )
            if (lab[0] >= refL) continue
            val t = (intensity * region * sk).coerceIn(0f, 1f)
            oklabToLinearRgb(
                lab[0] + (refL - lab[0]) * t,
                lab[1] + (refA - lab[1]) * t * 0.6f,
                lab[2] + (refB - lab[2]) * t * 0.6f,
                rgb,
            )
            output[i] = linearToSrgb8(rgb[0].coerceIn(0f, 1f))
            output[i + 1] = linearToSrgb8(rgb[1].coerceIn(0f, 1f))
            output[i + 2] = linearToSrgb8(rgb[2].coerceIn(0f, 1f))
        }
    }

    // -------------------------------------------------------------------------
    // Color helpers
    // -------------------------------------------------------------------------

    private fun srgbToLinear(c8: Int): Float {
        val c = c8 / 255f
        return if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)
    }

    private fun linearToSrgb8(c: Float): Byte {
        val s = if (c <= 0.0031308f) 12.92f * c else 1.055f * c.pow(1f / 2.4f) - 0.055f
        return (s.coerceIn(0f, 1f) * 255f + 0.5f).toInt().toByte()
    }

    private fun linearRgbToOklab(r: Float, g: Float, b: Float, out: FloatArray) {
        val l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b
        val m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b
        val s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b
        val l_ = cbrt(l.toDouble()).toFloat()
        val m_ = cbrt(m.toDouble()).toFloat()
        val s_ = cbrt(s.toDouble()).toFloat()
        out[0] = 0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_
        out[1] = 1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_
        out[2] = 0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_
    }

    private fun oklabToLinearRgb(L: Float, a: Float, b: Float, out: FloatArray) {
        val l_ = L + 0.3963377774f * a + 0.2158037573f * b
        val m_ = L - 0.1055613458f * a - 0.0638541728f * b
        val s_ = L - 0.0894841775f * a - 1.2914855480f * b
        val l = l_ * l_ * l_
        val m = m_ * m_ * m_
        val s = s_ * s_ * s_
        out[0] = +4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s
        out[1] = -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s
        out[2] = -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s
    }

    private fun weightedMeanLuma(
        rgba: ByteArray, skin: ByteArray, width: Int, height: Int, minWeight: Int,
    ): Float {
        var sum = 0.0; var count = 0
        val pixels = width * height
        for (p in 0 until pixels) {
            if ((skin[p].toInt() and 0xFF) < minWeight) continue
            val i = p * 4
            val r = srgbToLinear(rgba[i].toInt() and 0xFF)
            val g = srgbToLinear(rgba[i + 1].toInt() and 0xFF)
            val b = srgbToLinear(rgba[i + 2].toInt() and 0xFF)
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            count++
        }
        return if (count == 0) 0f else (sum / count).toFloat()
    }

    private fun skinReferenceOklab(
        rgba: ByteArray, skin: ByteArray, underEye: ByteArray, width: Int, height: Int,
    ): Triple<Float, Float, Float> {
        var sumL = 0.0; var sumA = 0.0; var sumB = 0.0; var count = 0
        val lab = FloatArray(3)
        val pixels = width * height
        for (p in 0 until pixels) {
            if ((skin[p].toInt() and 0xFF) < 180 || (underEye[p].toInt() and 0xFF) > 0) continue
            val i = p * 4
            linearRgbToOklab(
                srgbToLinear(rgba[i].toInt() and 0xFF),
                srgbToLinear(rgba[i + 1].toInt() and 0xFF),
                srgbToLinear(rgba[i + 2].toInt() and 0xFF),
                lab,
            )
            sumL += lab[0]; sumA += lab[1]; sumB += lab[2]
            count++
        }
        if (count == 0) return Triple(0.7f, 0f, 0f)
        return Triple(
            (sumL / count).toFloat(),
            (sumA / count).toFloat(),
            (sumB / count).toFloat(),
        )
    }

    // -------------------------------------------------------------------------
    // EGL / GL helpers
    // -------------------------------------------------------------------------

    private fun initEgl() {
        val localEgl = EGLContext.getEGL() as EGL10
        egl = localEgl
        val display = localEgl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
        eglDisplay = display
        localEgl.eglInitialize(display, IntArray(2))
        val attribList = intArrayOf(
            EGL10.EGL_RED_SIZE, 8,
            EGL10.EGL_GREEN_SIZE, 8,
            EGL10.EGL_BLUE_SIZE, 8,
            EGL10.EGL_ALPHA_SIZE, 8,
            EGL10.EGL_RENDERABLE_TYPE, 0x0040, // EGL_OPENGL_ES3_BIT
            EGL10.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfig = IntArray(1)
        if (!localEgl.eglChooseConfig(display, attribList, configs, 1, numConfig) || numConfig[0] == 0) {
            // fallback ES2 — GPU path desligado
            val attrib2 = intArrayOf(
                EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8,
                EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_ALPHA_SIZE, 8,
                EGL10.EGL_RENDERABLE_TYPE, 4, EGL10.EGL_NONE,
            )
            localEgl.eglChooseConfig(display, attrib2, configs, 1, numConfig)
            gles3 = false
        } else {
            gles3 = true
        }
        val config = configs[0] ?: error("egl_config")
        val version = if (gles3) 3 else 2
        val ctxAttribs = intArrayOf(0x3098, version, EGL10.EGL_NONE)
        eglContext = localEgl.eglCreateContext(display, config, EGL10.EGL_NO_CONTEXT, ctxAttribs)
        eglSurface = localEgl.eglCreatePbufferSurface(
            display, config, intArrayOf(EGL10.EGL_WIDTH, 1, EGL10.EGL_HEIGHT, 1, EGL10.EGL_NONE),
        )
        makeCurrent()
        if (gles3) {
            // Confirma half-float renderable
            val exts = GLES20.glGetString(GLES20.GL_EXTENSIONS) ?: ""
            if (!exts.contains("GL_EXT_color_buffer_half_float") &&
                !exts.contains("GL_OES_texture_half_float")
            ) {
                // Ainda tentamos R16F em GLES3 core — se falhar no create, available=false.
            }
        }
    }

    private fun makeCurrent() {
        val localEgl = egl ?: return
        localEgl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
    }

    private fun releaseEgl() {
        val localEgl = egl ?: return
        localEgl.eglMakeCurrent(
            eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT,
        )
        eglSurface?.let { localEgl.eglDestroySurface(eglDisplay, it) }
        eglContext?.let { localEgl.eglDestroyContext(eglDisplay, it) }
        localEgl.eglTerminate(eglDisplay)
        egl = null
    }

    private fun buildProgram(vsSrc: String, fsSrc: String): Int {
        val vs = compile(GLES20.GL_VERTEX_SHADER, vsSrc)
        val fs = compile(GLES20.GL_FRAGMENT_SHADER, fsSrc)
        val prog = GLES20.glCreateProgram()
        GLES20.glAttachShader(prog, vs)
        GLES20.glAttachShader(prog, fs)
        GLES20.glLinkProgram(prog)
        val status = IntArray(1)
        GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, status, 0)
        GLES20.glDeleteShader(vs)
        GLES20.glDeleteShader(fs)
        if (status[0] == 0) {
            GLES20.glDeleteProgram(prog)
            return 0
        }
        return prog
    }

    private fun compile(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }

    private fun createR16F(width: Int, height: Int): IntArray {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES30.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES30.GL_R16F, width, height, 0,
            GLES30.GL_RED, GLES30.GL_HALF_FLOAT, null,
        )
        return tex
    }

    private fun createRgba(width: Int, height: Int): IntArray {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null,
        )
        return tex
    }

    private fun uploadRgba(rgba: ByteArray, width: Int, height: Int): Int {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        val buf = ByteBuffer.allocateDirect(rgba.size).order(ByteOrder.nativeOrder())
        buf.put(rgba).position(0)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf,
        )
        return tex[0]
    }

    private fun uploadR8(bytes: ByteArray, width: Int, height: Int): Int {
        // Empacota R8 em RGBA8 (R=peso).
        val rgba = ByteArray(width * height * 4)
        for (i in bytes.indices) {
            val o = i * 4
            rgba[o] = bytes[i]
            rgba[o + 3] = 0xFF.toByte()
        }
        return uploadRgba(rgba, width, height)
    }

    private fun drawTo(fbo: Int, colorTex: Int, width: Int, height: Int, prog: Int, setup: () -> Unit) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo)
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, colorTex, 0,
        )
        GLES20.glViewport(0, 0, width, height)
        GLES20.glUseProgram(prog)
        setup()
        drawQuad(prog)
    }

    private fun bindTex(prog: Int, unit: Int, tex: Int, name: String, index: Int) {
        GLES20.glActiveTexture(unit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(prog, name), index)
    }

    private fun loc(prog: Int, name: String) = GLES20.glGetUniformLocation(prog, name)

    private fun drawQuad(prog: Int) {
        val coords = floatArrayOf(
            -1f, -1f, 0f, 0f,
            1f, -1f, 1f, 0f,
            -1f, 1f, 0f, 1f,
            -1f, 1f, 0f, 1f,
            1f, -1f, 1f, 0f,
            1f, 1f, 1f, 1f,
        )
        val buf: FloatBuffer = ByteBuffer.allocateDirect(coords.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        buf.put(coords).position(0)
        val pos = GLES20.glGetAttribLocation(prog, "aPosition")
        val uv = GLES20.glGetAttribLocation(prog, "aUv")
        buf.position(0)
        GLES20.glEnableVertexAttribArray(pos)
        GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 16, buf)
        buf.position(2)
        GLES20.glEnableVertexAttribArray(uv)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 16, buf)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, 6)
        GLES20.glDisableVertexAttribArray(pos)
        GLES20.glDisableVertexAttribArray(uv)
    }

    private fun flipVertically(bytes: ByteArray, width: Int, height: Int) {
        val stride = width * 4
        val tmp = ByteArray(stride)
        for (y in 0 until height / 2) {
            val top = y * stride
            val bottom = (height - 1 - y) * stride
            System.arraycopy(bytes, top, tmp, 0, stride)
            System.arraycopy(bytes, bottom, bytes, top, stride)
            System.arraycopy(tmp, 0, bytes, bottom, stride)
        }
    }

    companion object {
        private const val VS = """#version 300 es
            in vec2 aPosition;
            in vec2 aUv;
            out vec2 vUv;
            void main() {
              vUv = aUv;
              gl_Position = vec4(aPosition, 0.0, 1.0);
            }
        """

        private const val FS_EXTRACT = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            out vec4 fragColor;
            float srgb_to_linear(float c) {
              return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
            }
            void main() {
              vec3 s = texture(uSrc, vUv).rgb;
              vec3 lin = vec3(srgb_to_linear(s.r), srgb_to_linear(s.g), srgb_to_linear(s.b));
              float luma = 0.2126*lin.r + 0.7152*lin.g + 0.0722*lin.b;
              fragColor = vec4(luma, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_BLUR_H = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            uniform int uRadius;
            uniform vec2 uSize;
            out vec4 fragColor;
            void main() {
              float sum = 0.0;
              float count = 0.0;
              for (int dx = -64; dx <= 64; dx++) {
                if (dx < -uRadius || dx > uRadius) continue;
                float x = clamp(vUv.x + float(dx) / uSize.x, 0.0, 1.0);
                sum += texture(uSrc, vec2(x, vUv.y)).r;
                count += 1.0;
              }
              fragColor = vec4(sum / count, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_BLUR_V = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            uniform int uRadius;
            uniform vec2 uSize;
            out vec4 fragColor;
            void main() {
              float sum = 0.0;
              float count = 0.0;
              for (int dy = -64; dy <= 64; dy++) {
                if (dy < -uRadius || dy > uRadius) continue;
                float y = clamp(vUv.y + float(dy) / uSize.y, 0.0, 1.0);
                sum += texture(uSrc, vec2(vUv.x, y)).r;
                count += 1.0;
              }
              fragColor = vec4(sum / count, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_SQUARE = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            out vec4 fragColor;
            void main() {
              float v = texture(uSrc, vUv).r;
              fragColor = vec4(v * v, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_COEFF = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uMeanI;
            uniform sampler2D uMeanII;
            uniform float uEps;
            uniform int uMode;
            out vec4 fragColor;
            void main() {
              float mean = texture(uMeanI, vUv).r;
              float meanII = texture(uMeanII, vUv).r;
              float variance = meanII - mean * mean;
              float a = variance <= 0.0 ? 0.0 : variance / (variance + uEps);
              float b = mean * (1.0 - a);
              fragColor = vec4(uMode == 0 ? a : b, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_APPLY = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            uniform sampler2D uMeanA;
            uniform sampler2D uMeanB;
            out vec4 fragColor;
            void main() {
              float v = texture(uMeanA, vUv).r * texture(uSrc, vUv).r + texture(uMeanB, vUv).r;
              fragColor = vec4(v, 0.0, 0.0, 1.0);
            }
        """

        private const val FS_COMPOSITE = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            uniform sampler2D uLuma;
            uniform sampler2D uFine;
            uniform sampler2D uCoarse;
            uniform sampler2D uBlemish;
            uniform sampler2D uSkin;
            uniform float uSmooth;
            uniform float uAcne;
            uniform float uWrinkles;
            uniform float uShine;
            uniform float uSkinRef;
            uniform float uHighKeep;
            uniform float uMidKeep;
            out vec4 fragColor;
            float srgb_to_linear(float c) {
              return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
            }
            float linear_to_srgb(float c) {
              c = clamp(c, 0.0, 1.0);
              return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0/2.4) - 0.055;
            }
            void main() {
              vec4 srgba = texture(uSrc, vUv);
              float weight = texture(uSkin, vUv).r;
              if (weight <= 0.0) { fragColor = srgba; return; }
              float original = texture(uLuma, vUv).r;
              float low = texture(uCoarse, vUv).r;
              float fine = texture(uFine, vUv).r;
              float mid = fine - low;
              float high = original - fine;
              float smoothStrength = min(1.0, uSmooth + uWrinkles * 0.5);
              float midKeep = 1.0 - (1.0 - uMidKeep) * smoothStrength;
              float highKeep = 1.0 - (1.0 - uHighKeep) * smoothStrength;
              float lowMid = low + mid * midKeep;
              if (uAcne > 0.0) {
                float reference = texture(uBlemish, vUv).r;
                float deficit = reference - fine;
                float threshold = max(reference * 0.05, 0.0015);
                if (deficit > threshold) {
                  float spot = clamp((deficit - threshold) / threshold, 0.0, 1.0);
                  lowMid += deficit * uAcne * spot;
                }
              }
              float shineKnee = uSkinRef * 1.18;
              if (uShine > 0.0 && shineKnee > 0.0 && lowMid > shineKnee) {
                float excess = lowMid - shineKnee;
                lowMid = shineKnee + excess * (1.0 - 0.7 * uShine);
              }
              float target = lowMid + high * highKeep;
              float blended = original + (target - original) * weight;
              vec3 lin = vec3(
                srgb_to_linear(srgba.r),
                srgb_to_linear(srgba.g),
                srgb_to_linear(srgba.b)
              );
              if (original <= 1e-5) {
                float v = linear_to_srgb(clamp(blended, 0.0, 1.0));
                fragColor = vec4(v, v, v, srgba.a);
                return;
              }
              float factor = clamp(blended / original, 0.0, 4.0);
              vec3 outLin = clamp(lin * factor, 0.0, 1.0);
              fragColor = vec4(
                linear_to_srgb(outLin.r),
                linear_to_srgb(outLin.g),
                linear_to_srgb(outLin.b),
                srgba.a
              );
            }
        """

        private const val FS_DARK = """#version 300 es
            precision highp float;
            in vec2 vUv;
            uniform sampler2D uSrc;
            uniform sampler2D uSkin;
            uniform sampler2D uEye;
            uniform float uIntensity;
            uniform float uRefL;
            uniform float uRefA;
            uniform float uRefB;
            out vec4 fragColor;
            float srgb_to_linear(float c) {
              return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
            }
            float linear_to_srgb(float c) {
              c = clamp(c, 0.0, 1.0);
              return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0/2.4) - 0.055;
            }
            vec3 linear_to_oklab(vec3 c) {
              float l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
              float m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
              float s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
              float l_ = pow(l, 1.0/3.0);
              float m_ = pow(m, 1.0/3.0);
              float s_ = pow(s, 1.0/3.0);
              return vec3(
                0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
                1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
                0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
              );
            }
            vec3 oklab_to_linear(vec3 lab) {
              float l_ = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
              float m_ = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
              float s_ = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;
              float l = l_*l_*l_;
              float m = m_*m_*m_;
              float s = s_*s_*s_;
              return vec3(
                +4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
                -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
                -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
              );
            }
            void main() {
              vec4 srgba = texture(uSrc, vUv);
              float region = texture(uEye, vUv).r;
              float sk = texture(uSkin, vUv).r;
              if (region <= 0.0 || sk <= 0.0) { fragColor = srgba; return; }
              vec3 lin = vec3(
                srgb_to_linear(srgba.r),
                srgb_to_linear(srgba.g),
                srgb_to_linear(srgba.b)
              );
              vec3 lab = linear_to_oklab(lin);
              if (lab.x >= uRefL) { fragColor = srgba; return; }
              float t = clamp(uIntensity * region * sk, 0.0, 1.0);
              lab.x = lab.x + (uRefL - lab.x) * t;
              lab.y = lab.y + (uRefA - lab.y) * t * 0.6;
              lab.z = lab.z + (uRefB - lab.z) * t * 0.6;
              vec3 outLin = clamp(oklab_to_linear(lab), 0.0, 1.0);
              fragColor = vec4(
                linear_to_srgb(outLin.r),
                linear_to_srgb(outLin.g),
                linear_to_srgb(outLin.b),
                srgba.a
              );
            }
        """
    }
}
