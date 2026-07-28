package com.editaiapp.beauty_mediapipe

import android.graphics.Bitmap
import android.opengl.GLES20
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.egl.EGLSurface

/**
 * Backend de export Body Reshape (Sprint 13).
 *
 * Preferência documentada: Vulkan compute. Esta implementação usa OpenGL ES
 * FBO como fallback portátil e reporta `openGlEs=true` (vulkan=false até
 * o pipeline Vulkan ser ligado no dispositivo).
 */
class BodyReshapeVulkanBackend {
    private var egl: EGL10? = null
    private var eglDisplay: EGLDisplay? = EGL10.EGL_NO_DISPLAY
    private var eglContext: EGLContext? = EGL10.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface? = EGL10.EGL_NO_SURFACE
    private var program = 0
    private var available = false

    init {
        try {
            initEgl()
            program = buildProgram()
            available = program != 0
        } catch (_: Throwable) {
            available = false
            releaseEgl()
        }
    }

    fun capabilities(): Map<String, Any> = mapOf(
        "metal" to false,
        "vulkan" to false,
        "openGlEs" to available,
        "nativeJpegEncode" to true,
    )

    fun isAvailable(): Boolean = available

    fun warpExport(args: Map<String, Any?>): ByteArray {
        check(available) { "gles_unavailable" }
        val rgba = args["rgba"] as? ByteArray ?: error("invalid_args")
        val width = args["width"] as? Int ?: error("invalid_args")
        val height = args["height"] as? Int ?: error("invalid_args")
        require(width > 0 && height > 0 && rgba.size == width * height * 4)

        val fullWidth = (args["fullWidth"] as? Number)?.toFloat() ?: width.toFloat()
        val fullHeight = (args["fullHeight"] as? Number)?.toFloat() ?: height.toFloat()
        val tileOriginX = (args["tileOriginX"] as? Number)?.toFloat() ?: 0f
        val tileOriginY = (args["tileOriginY"] as? Number)?.toFloat() ?: 0f
        val displacementScaleX = (args["displacementScaleX"] as? Number)?.toFloat() ?: 1f
        val displacementScaleY = (args["displacementScaleY"] as? Number)?.toFloat() ?: 1f

        val displacement = args["displacement"] as? ByteArray ?: error("invalid_args")
        val dispW = args["displacementWidth"] as? Int ?: error("invalid_args")
        val dispH = args["displacementHeight"] as? Int ?: error("invalid_args")
        val mask = args["mask"] as? ByteArray ?: error("invalid_args")
        val maskW = args["maskWidth"] as? Int ?: error("invalid_args")
        val maskH = args["maskHeight"] as? Int ?: error("invalid_args")

        val influence = args["influence"] as? ByteArray
        val influenceW = (args["influenceWidth"] as? Int) ?: 1
        val influenceH = (args["influenceHeight"] as? Int) ?: 1
        val protection = args["protection"] as? ByteArray
        val protectionW = (args["protectionWidth"] as? Int) ?: 1
        val protectionH = (args["protectionHeight"] as? Int) ?: 1

        makeCurrent()

        val srcTex = uploadRgbaTexture(rgba, width, height)
        val dispTex = uploadRgbaTexture(displacement, dispW, dispH)
        val maskTex = uploadRgbaTexture(mask, maskW, maskH)
        val infTex = uploadRgbaTexture(
            influence ?: byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()),
            if (influence == null) 1 else influenceW,
            if (influence == null) 1 else influenceH,
        )
        val protTex = uploadRgbaTexture(
            protection ?: byteArrayOf(0, 0, 0, 0xFF.toByte()),
            if (protection == null) 1 else protectionW,
            if (protection == null) 1 else protectionH,
        )

        val fbo = IntArray(1)
        val outTex = IntArray(1)
        GLES20.glGenFramebuffers(1, fbo, 0)
        GLES20.glGenTextures(1, outTex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, outTex[0])
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null,
        )
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, outTex[0], 0,
        )

        GLES20.glViewport(0, 0, width, height)
        GLES20.glUseProgram(program)
        bindTexture(GLES20.GL_TEXTURE0, srcTex, GLES20.glGetUniformLocation(program, "uInputTexture"), 0)
        bindTexture(GLES20.GL_TEXTURE1, dispTex, GLES20.glGetUniformLocation(program, "uDisplacementMap"), 1)
        bindTexture(GLES20.GL_TEXTURE2, maskTex, GLES20.glGetUniformLocation(program, "uMaskMap"), 2)
        bindTexture(GLES20.GL_TEXTURE3, infTex, GLES20.glGetUniformLocation(program, "uInfluenceMap"), 3)
        bindTexture(GLES20.GL_TEXTURE4, protTex, GLES20.glGetUniformLocation(program, "uProtectionMap"), 4)

        GLES20.glUniform2f(GLES20.glGetUniformLocation(program, "uImageSize"), fullWidth, fullHeight)
        GLES20.glUniform2f(GLES20.glGetUniformLocation(program, "uTileOrigin"), tileOriginX, tileOriginY)
        GLES20.glUniform2f(
            GLES20.glGetUniformLocation(program, "uTileSize"),
            width.toFloat(),
            height.toFloat(),
        )
        GLES20.glUniform2f(
            GLES20.glGetUniformLocation(program, "uDisplacementScalePx"),
            displacementScaleX,
            displacementScaleY,
        )

        drawFullscreenQuad()
        GLES20.glFinish()

        val out = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, out)
        val bytes = ByteArray(width * height * 4)
        out.rewind()
        out.get(bytes)
        // OpenGL origin is bottom-left — flip vertically.
        flipVertically(bytes, width, height)

        GLES20.glDeleteTextures(1, intArrayOf(srcTex, dispTex, maskTex, infTex, protTex, outTex[0]), 0)
        GLES20.glDeleteFramebuffers(1, fbo, 0)
        return bytes
    }

    fun encodeJpeg(args: Map<String, Any?>): ByteArray {
        val rgba = args["rgba"] as? ByteArray ?: error("invalid_args")
        val width = args["width"] as? Int ?: error("invalid_args")
        val height = args["height"] as? Int ?: error("invalid_args")
        val quality = (args["quality"] as? Int)?.coerceIn(1, 100) ?: 90
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        var i = 0
        var p = 0
        while (i < pixels.size) {
            val r = rgba[p].toInt() and 0xFF
            val g = rgba[p + 1].toInt() and 0xFF
            val b = rgba[p + 2].toInt() and 0xFF
            val a = rgba[p + 3].toInt() and 0xFF
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
            i++
            p += 4
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }

    fun dispose() {
        if (program != 0) {
            makeCurrent()
            GLES20.glDeleteProgram(program)
            program = 0
        }
        releaseEgl()
        available = false
    }

    private fun initEgl() {
        val localEgl = EGLContext.getEGL() as EGL10
        egl = localEgl
        val display = localEgl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
        eglDisplay = display
        val version = IntArray(2)
        localEgl.eglInitialize(display, version)
        val attribList = intArrayOf(
            EGL10.EGL_RED_SIZE, 8,
            EGL10.EGL_GREEN_SIZE, 8,
            EGL10.EGL_BLUE_SIZE, 8,
            EGL10.EGL_ALPHA_SIZE, 8,
            EGL10.EGL_RENDERABLE_TYPE, 4, // EGL_OPENGL_ES2_BIT
            EGL10.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfig = IntArray(1)
        localEgl.eglChooseConfig(display, attribList, configs, 1, numConfig)
        val config = configs[0] ?: error("egl_config")
        val ctxAttribs = intArrayOf(0x3098, 2, EGL10.EGL_NONE) // EGL_CONTEXT_CLIENT_VERSION
        eglContext = localEgl.eglCreateContext(display, config, EGL10.EGL_NO_CONTEXT, ctxAttribs)
        val surfaceAttribs = intArrayOf(EGL10.EGL_WIDTH, 1, EGL10.EGL_HEIGHT, 1, EGL10.EGL_NONE)
        eglSurface = localEgl.eglCreatePbufferSurface(display, config, surfaceAttribs)
        makeCurrent()
    }

    private fun makeCurrent() {
        val localEgl = egl ?: return
        localEgl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
    }

    private fun releaseEgl() {
        val localEgl = egl ?: return
        localEgl.eglMakeCurrent(
            eglDisplay,
            EGL10.EGL_NO_SURFACE,
            EGL10.EGL_NO_SURFACE,
            EGL10.EGL_NO_CONTEXT,
        )
        eglSurface?.let { localEgl.eglDestroySurface(eglDisplay, it) }
        eglContext?.let { localEgl.eglDestroyContext(eglDisplay, it) }
        localEgl.eglTerminate(eglDisplay)
        eglSurface = EGL10.EGL_NO_SURFACE
        eglContext = EGL10.EGL_NO_CONTEXT
        eglDisplay = EGL10.EGL_NO_DISPLAY
        egl = null
    }

    private fun buildProgram(): Int {
        val vs = compile(GLES20.GL_VERTEX_SHADER, VERTEX)
        val fs = compile(GLES20.GL_FRAGMENT_SHADER, FRAGMENT)
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

    private fun uploadRgbaTexture(rgba: ByteArray, width: Int, height: Int): Int {
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

    private fun bindTexture(unit: Int, tex: Int, location: Int, index: Int) {
        GLES20.glActiveTexture(unit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
        GLES20.glUniform1i(location, index)
    }

    private fun drawFullscreenQuad() {
        val coords = floatArrayOf(
            -1f, -1f, 0f, 0f,
            1f, -1f, 1f, 0f,
            -1f, 1f, 0f, 1f,
            -1f, 1f, 0f, 1f,
            1f, -1f, 1f, 0f,
            1f, 1f, 1f, 1f,
        )
        val buf: FloatBuffer = ByteBuffer.allocateDirect(coords.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buf.put(coords).position(0)
        val pos = GLES20.glGetAttribLocation(program, "aPosition")
        val uv = GLES20.glGetAttribLocation(program, "aUv")
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
        private const val VERTEX = """
            attribute vec2 aPosition;
            attribute vec2 aUv;
            varying vec2 vUv;
            void main() {
              vUv = aUv;
              gl_Position = vec4(aPosition, 0.0, 1.0);
            }
        """

        private const val FRAGMENT = """
            precision mediump float;
            varying vec2 vUv;
            uniform vec2 uImageSize;
            uniform vec2 uTileOrigin;
            uniform vec2 uTileSize;
            uniform highp vec2 uDisplacementScalePx;
            uniform sampler2D uInputTexture;
            uniform sampler2D uDisplacementMap;
            uniform sampler2D uMaskMap;
            uniform sampler2D uInfluenceMap;
            uniform sampler2D uProtectionMap;
            void main() {
              vec2 local = vUv * uTileSize;
              vec2 fullCoord = uTileOrigin + local;
              vec2 uv = fullCoord / uImageSize;
              float mask = texture2D(uMaskMap, uv).r;
              float influence = texture2D(uInfluenceMap, uv).r;
              float protection = texture2D(uProtectionMap, uv).r;
              float edgeScale = clamp(mask / 0.88, 0.0, 1.0);
              float effectiveMask = mask * influence * (1.0 - protection)
                  * edgeScale * edgeScale;
              if (effectiveMask <= 0.001) {
                gl_FragColor = texture2D(uInputTexture, vUv);
                return;
              }
              vec2 encoded = texture2D(uDisplacementMap, uv).rg;
              highp vec2 dispPx = (encoded * 2.0 - 1.0) * uDisplacementScalePx;
              highp vec2 pullPx = dispPx * effectiveMask;
              float maxPull = max(uImageSize.x, uImageSize.y) * 0.08;
              float pullLength = length(pullPx);
              if (pullLength > maxPull && pullLength > 0.0001) {
                pullPx *= maxPull / pullLength;
              }
              highp vec2 srcUv = uv + pullPx / uImageSize;
              vec2 srcFull = srcUv * uImageSize;
              vec2 srcLocal = (srcFull - uTileOrigin) / uTileSize;
              srcLocal = clamp(srcLocal, vec2(0.0), vec2(1.0));
              gl_FragColor = texture2D(uInputTexture, srcLocal);
            }
        """
    }
}
