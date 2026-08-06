package com.banuba.pe_sdk_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.banuba.sdk.core.license.EditorSdk
import com.banuba.sdk.pe.PhotoCreationActivity
import com.banuba.sdk.pe.PhotoExportResultContract
import com.banuba.sdk.pe.data.PhotoEditorConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/** PeSdkFlutterPlugin */
class PeSdkFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var currentActivity: Activity? = null
    private var channelResult: Result? = null

    companion object {
        private const val PHOTO_EDITOR_REQUEST_CODE = 2000
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        channelResult = result
        val methodName = call.method
        Log.d(TAG, "Received method call = $methodName")

        val licenseToken = call.argument<String>(INPUT_PARAM_TOKEN)
        if (licenseToken.isNullOrEmpty()) {
            channelResult?.error(ERR_INVALID_PARAMS, ERR_MESSAGE_MISSING_TOKEN, null)
            return
        }

        val mode = call.argument<String>(INPUT_PARAM_MODE)
        if (mode.isNullOrEmpty()) {
            channelResult?.error(ERR_INVALID_MODE, ERR_MESSAGE_MISSING_MODE, null)
            return
        }

        val applyDarkTheme = call.argument<Boolean>(INPUT_PARAM_ENABLE_DARK_THEME) ?: false

        when (methodName) {
            METHOD_START -> {
                initialize(licenseToken) { activity ->
                    // Config mínimo do PE SDK: todas as ferramentas liberadas pela
                    // licença já vêm ativas por padrão (retouch, makeup, effects…).
                    val config = PhotoEditorConfig.Builder(context = activity.applicationContext)
                        .saveToGallery(saveToGallery = false)
                        .build()

                    val intent = when (mode) {
                        MODE_GALLERY -> {
                            Log.d(TAG, "Start photo editor from gallery")
                            PhotoCreationActivity.startFromGallery(
                                activity,
                                config = config,
                                applyDarkTheme = applyDarkTheme
                            )
                        }

                        MODE_EDITOR -> {
                            val photoSource = call.argument<String>(INPUT_PARAM_PHOTO_SOURCE)
                            Log.d(TAG, "Received photo source = $photoSource")

                            if (photoSource.isNullOrEmpty()) {
                                channelResult?.error(
                                    ERR_INVALID_PARAMS,
                                    ERR_MESSAGE_MISSING_PHOTO_SOURCE,
                                    null
                                )
                                return@initialize
                            }

                            val imageUri = Uri.fromFile(File(photoSource))
                            Log.d(TAG, "Start photo editor in editor mode with photo = $imageUri")

                            PhotoCreationActivity.startFromEditor(
                                activity,
                                config = config,
                                imageUri = imageUri,
                                applyDarkTheme = applyDarkTheme
                            )
                        }

                        else -> null
                    }
                    if (intent == null) {
                        Log.e(TAG, "Cannot start: unknown mode = $mode")
                        channelResult?.error(ERR_INVALID_MODE, ERR_MESSAGE_MISSING_HOST, null)
                        return@initialize
                    }
                    activity.startActivityForResult(intent, PHOTO_EDITOR_REQUEST_CODE)
                }
            }

            else -> {
                Log.e(TAG, "Unhandled method call = $methodName")
                channelResult?.notImplemented()
            }
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        intent: Intent?,
    ): Boolean {
        Log.d(TAG, "onActivityResult: code = $resultCode, result = $resultCode, intent = $intent")
        return if (requestCode == PHOTO_EDITOR_REQUEST_CODE) {
            val resultUri: Uri? = PhotoExportResultContract().parseResult(resultCode, intent)
            if (resultCode == Activity.RESULT_OK && resultUri != null) {
                currentActivity?.let { activity ->
                    val cachedFile = saveFileFromUri(activity, resultUri)
                    if (cachedFile != null) {
                        val resultData = mapOf(EXPORTED_PHOTO_SOURCE to cachedFile.absolutePath)
                        channelResult?.success(resultData)
                    }
                }
            } else {
                Log.d(TAG, "No export result: the user closed photo editor")
                channelResult?.error(ERR_PHOTO_EXPORT_CANCEL, ERR_MESSAGE_PHOTO_EXPORT_CANCEL, null)
            }
            true
        } else {
            Log.e(TAG, "Unhandled request code = $requestCode")
            false
        }
    }

    private fun initialize(token: String, block: (Activity) -> Unit) {
        val activity = currentActivity

        if (activity == null) {
            Log.e(TAG, ERR_MESSAGE_MISSING_HOST)
            channelResult?.error(ERR_MISSING_HOST, ERR_MESSAGE_MISSING_HOST, null)
            return
        }

        val sdk = EditorSdk.initialize(token)

        if (sdk == null) {
            Log.e(TAG, ERR_MESSAGE_SDK_NOT_INITIALIZED)
            channelResult?.error(
                ERR_CODE_SDK_NOT_INITIALIZED,
                ERR_MESSAGE_SDK_NOT_INITIALIZED,
                null
            )
            return
        }

        sdk.getLicenseState { isValid ->
            if (isValid) {
                Log.d(TAG, "The license token is valid!")
                block(activity)
            } else {
                Log.e(TAG, ERR_MESSAGE_LICENSE_REVOKED)
                channelResult?.error(
                    ERR_CODE_SDK_LICENSE_REVOKED,
                    ERR_MESSAGE_LICENSE_REVOKED,
                    null
                )
            }
        }
    }

    private fun saveFileFromUri(context: Context, uri: Uri): File? {
        return try {
            val cacheFile = File(context.getExternalFilesDir(null), "${System.currentTimeMillis()}.jpg")
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                FileOutputStream(cacheFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            }
            cacheFile
        } catch (e: IOException) {
            Log.e(TAG, ERR_FAILED_TO_SAVE_AN_IMAGE, e)
            channelResult?.error(
                ERR_FAILED_TO_SAVE_AN_IMAGE,
                ERR_MESSAGE_FAILED_TO_SAVE_AN_IMAGE,
                null
            )
            null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
