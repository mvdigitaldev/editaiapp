package com.banuba.pe_sdk_flutter

// Tag
internal const val TAG = "PhotoEditorPlugin"

// Method channel
internal const val CHANNEL = "pe_sdk_flutter"
internal const val METHOD_START = "startPhotoEditor"

// Input params
internal const val INPUT_PARAM_TOKEN = "token"
internal const val INPUT_PARAM_MODE = "mode"
internal const val INPUT_PARAM_PHOTO_SOURCE = "photoSource"
internal const val INPUT_PARAM_ENABLE_DARK_THEME = "applyDarkTheme"

// Modes
internal const val MODE_GALLERY = "gallery"
internal const val MODE_EDITOR = "editor"

// Errors
internal const val ERR_CODE_SDK_NOT_INITIALIZED = "ERR_SDK_NOT_INITIALIZED"
internal const val ERR_CODE_SDK_LICENSE_REVOKED = "ERR_SDK_LICENSE_REVOKED"
internal const val ERR_MISSING_HOST = "ERR_MISSING_HOST"
internal const val ERR_INVALID_PARAMS = "ERR_INVALID_PARAMS"
internal const val ERR_INVALID_MODE = "ERR_INVALID_MODE"
internal const val ERR_INVALID_PHOTO_SOURCE = "ERR_INVALID_PHOTO_SOURCE"
internal const val ERR_FAILED_TO_SAVE_AN_IMAGE = "ERR_FAILED_TO_SAVE_AN_IMAGE"
internal const val ERR_MISSING_EXPORT_RESULT = "ERR_MISSING_EXPORT_RESULT"
internal const val ERR_PHOTO_EXPORT_CANCEL = "ERR_PHOTO_EXPORT_CANCEL"

// Exported params
internal const val EXPORTED_PHOTO_SOURCE = "exportedPhotoSource"

internal const val ERR_MESSAGE_SDK_NOT_INITIALIZED = """
    Failed to initialize SDK!!! 
    The license token is incorrect: empty or truncated.
    Please check the license token and try again.
"""
internal const val ERR_MESSAGE_LICENSE_REVOKED = """
    "WARNING!!!
    YOUR LICENSE TOKEN EITHER EXPIRED OR REVOKED!
    Please contact Banuba"
"""

internal const val ERR_MESSAGE_MISSING_TOKEN =
    "Missing license token: set correct value to $INPUT_PARAM_TOKEN input params"

internal const val ERR_MESSAGE_MISSING_MODE =
    "Missing Photo Editor mode: set correct value to $INPUT_PARAM_MODE input params"

internal const val ERR_MESSAGE_MISSING_PHOTO_SOURCE =
    "Missing photo source: set correct value to $INPUT_PARAM_PHOTO_SOURCE input params"

internal const val ERR_MESSAGE_FAILED_TO_SAVE_AN_IMAGE =
    "Missing cached image: Failed to save an image"

internal const val ERR_MESSAGE_MISSING_EXPORT_RESULT =
    "Missing export result: photo export has not been completed successfully or canceled."

internal const val ERR_MESSAGE_PHOTO_EXPORT_CANCEL = "The user has canceled photo editing flow!"

internal const val ERR_MESSAGE_MISSING_HOST = "Missing host Activity to start photo editor"
