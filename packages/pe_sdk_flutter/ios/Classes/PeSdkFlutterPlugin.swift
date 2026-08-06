import Flutter
import UIKit

public class PeSdkFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "pe_sdk_flutter", binaryMessenger: registrar.messenger())
        let instance = PeSdkFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    let photoEditor = PhotoEditorModule()

    public func handle(_ call: FlutterMethodCall,result: @escaping FlutterResult) {

        guard let args = call.arguments as? Dictionary<String, Any> else {
            result(
                FlutterError.init(
                    code: PeSdkFlutterPlugin.errInvalidParams,
                    message: PeSdkFlutterPlugin.errMessageUnknownInputParams,
                    details: nil
                )
            )
            return
        }

        guard let licenseToken = args[PeSdkFlutterPlugin.inputParamToken] as? String else {
            result(
                FlutterError(
                    code: PeSdkFlutterPlugin.errInvalidParams,
                    message: PeSdkFlutterPlugin.errMessageMissingToken,
                    details: nil
                )
            )
            return
        }

        guard let mode = args[PeSdkFlutterPlugin.inputParamMode] as? String else {
            result(
                FlutterError(
                    code: PeSdkFlutterPlugin.errMissingMode,
                    message: PeSdkFlutterPlugin.errMessageMissingMode,
                    details: nil
                )
            )
            return
        }

        if (!photoEditor.initPhotoEditor(token: licenseToken)) {
            result(
                FlutterError(
                    code: PeSdkFlutterPlugin.errSdkNotInitialized,
                    message: PeSdkFlutterPlugin.errMessageSdkNotInitialized,
                    details: nil
                )
            )
            return
        }

        guard let controller = UIApplication.shared.keyWindow?.rootViewController as? FlutterViewController else {
            result(
                FlutterError(
                    code: PeSdkFlutterPlugin.errMissingHost,
                    message: PeSdkFlutterPlugin.errMessageMissingHost,
                    details: nil
                )
            )
            return
        }

        guard call.method == PeSdkFlutterPlugin.methodStart else {
            result(
                FlutterError(
                    code: PeSdkFlutterPlugin.errInvalidParams,
                    message: PeSdkFlutterPlugin.errMessageUnknownMethod,
                    details: nil
                )
            )
            return
        }

        let applyDarkTheme = args[PeSdkFlutterPlugin.inputParamApplyDarkTheme] as? Bool ?? false

        switch mode {
            case PeSdkFlutterPlugin.modeGallery:
                photoEditor.openFromGallery(
                    fromViewController: controller,
                    applyDarkTheme: applyDarkTheme,
                    flutterResult: result
                )
            case PeSdkFlutterPlugin.modeEditor:
                let photoSource = args[PeSdkFlutterPlugin.inputParamPhotoSource] as? String
                if (photoSource == nil || photoSource!.isEmpty) {
                    result(FlutterError(code: PeSdkFlutterPlugin.errInvalidParams, message: PeSdkFlutterPlugin.errMessageUnknownPhotoSource, details: nil))
                    return
                }
                self.photoEditor.openFromEditor(fromViewController: controller, photoSource: URL(fileURLWithPath: photoSource!), applyDarkTheme: applyDarkTheme, flutterResult: result)
            default:
                debugPrint("Unknown screen value = \(mode)" )
                result(FlutterError(code: PeSdkFlutterPlugin.errInvalidParams, message: PeSdkFlutterPlugin.errMessageMissingMode, details: nil))
                return
        }
    }
}
