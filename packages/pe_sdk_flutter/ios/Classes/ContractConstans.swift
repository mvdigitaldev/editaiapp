import Foundation

extension PeSdkFlutterPlugin {
    static let channel = "pe_sdk_flutter"
    static let methodStart = "startPhotoEditor"
    
    static let errInvalidParams = "ERR_INVALID_PARAMS"
    static let errSdkNotInitialized = "ERR_SDK_NOT_INITIALIZED"
    static let errLicenseRevoked = "ERR_SDK_LICENSE_REVOKED"
    static let errMissingMode = "ERR_SDK_INVALID_MODE"
    static let errMissingHost = "ERR_MISSING_HOST"
    static let errMissingExportResult = "ERR_MISSING_EXPORT_RESULT"
    static let errMissingSavedImage = "ERR_MISSING_SAVED_IMAGE"
    static let errPhotoExportCancel = "ERR_PHOTO_EXPORT_CANCEL"
    
    static let inputParamToken = "token"
    static let inputParamMode = "mode"
    static let inputParamPhotoSource = "photoSource"
    static let inputParamApplyDarkTheme = "applyDarkTheme"

    static let modeGallery = "gallery"
    static let modeEditor = "editor"
    
    static let argExportedPhotoSource = "exportedPhotoSource"
    
    static let errMessageSdkNotInitialized = """
        Failed to initialize SDK!!!
        The license token is incorrect: empty or truncated.
        Please check the license token and try again.
    """
    static let errMessageLicenseRevoked = """
        WARNING!!!
        YOUR LICENSE TOKEN EITHER EXPIRED OR REVOKED!
        Please contact Banuba
    """
    
    static let errMessageMissingToken = "Missing license token: set correct value to \(inputParamToken) input params"
    static let errMessageMissingMode = "Missing screen: set correct value to \(inputParamMode) input params"
    static let errMessageUnknownMethod = "Unknown method name"
    static let errMessageUnknownMode = "Invalid inputParams value: available values(\(modeGallery), \(modeEditor))"
    static let errMessageUnknownInputParams = "Invalid inputParams value"
    static let errMessageUnknownPhotoSource = "Invalid photo source value"
    static let errMessageMissingExportResult =
    "Missing export result: photo export has not been completed successfully. Please try again"
    static let errMessageMissingSavedImage = "Failed to save an image, please try again."
    static let errMessagePhotoExportCancel = "The user has canceled photo editing flow!"
    static let errMessageMissingHost = "Missing host ViewController to start photo editor"
}
