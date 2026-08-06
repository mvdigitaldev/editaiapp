import Flutter
import Foundation
import BanubaPhotoEditorSDK
import BanubaDesignSystem

protocol PhotoEditor {
    func initPhotoEditor(token: String) -> Bool

    func openFromGallery(fromViewController controller: FlutterViewController, applyDarkTheme: Bool, flutterResult: @escaping FlutterResult)

    func openFromEditor(fromViewController controller: FlutterViewController, photoSource: URL, applyDarkTheme: Bool, flutterResult: @escaping FlutterResult)
}

class PhotoEditorModule: PhotoEditor{
    
    private var photoEditorSDK: BanubaPhotoEditor?
    private var flutterResult: FlutterResult?
    
    func initPhotoEditor(token: String) -> Bool {
        
        guard photoEditorSDK == nil else {
            debugPrint("Photo Editor SDK is already initialized")
            return true
        }
        
        // PhotoEditorConfig não expõe toggles por ferramenta: retouch, makeup,
        // effects, adjust, transform e text vêm ativos conforme a licença +
        // beauty mask padrão do SDK.
        let configuration = PhotoEditorConfig(
            editorScreenConfiguration: EditorScreenConfiguration(
                saveResultToPhotoLibrary: false
            ),
            beautyMaskURL: PhotoEditorConfig.defaultBeautyMaskBundleURL
        )
        
        photoEditorSDK = BanubaPhotoEditor(
            token: token,
            configuration: configuration
        )
        if photoEditorSDK == nil {
            debugPrint("Photo Editor SDK is not initialized, please check Banuba token")
            return false
        }
        
        photoEditorSDK?.delegate = self
        return true
    }
    
    func openFromGallery(fromViewController controller: FlutterViewController, applyDarkTheme: Bool, flutterResult: @escaping FlutterResult) {
        // Flutter platform channel calls always arrive on the main thread.
        MainActor.assumeIsolated {
            BNBDesignSystem.theme = applyDarkTheme ? .dark : .light
        }
        let config = PhotoEditorLaunchConfig(hostController: controller, entryPoint: .gallery)
        self.flutterResult = flutterResult
        checkLicenseAndStartPhotoEditor(with: config, flutterResult: flutterResult)
    }

    func openFromEditor(fromViewController controller: FlutterViewController, photoSource: URL, applyDarkTheme: Bool, flutterResult: @escaping FlutterResult) {
        // Flutter platform channel calls always arrive on the main thread.
        MainActor.assumeIsolated {
            BNBDesignSystem.theme = applyDarkTheme ? .dark : .light
        }
        let config = PhotoEditorLaunchConfig(hostController: controller, entryPoint: .editorWithURL(photoSource))
        self.flutterResult = flutterResult
        checkLicenseAndStartPhotoEditor(with: config, flutterResult: flutterResult)
    }
    
    func checkLicenseAndStartPhotoEditor(with config: PhotoEditorLaunchConfig, flutterResult: @escaping FlutterResult) {
        if photoEditorSDK == nil {
            flutterResult(FlutterError(code: PeSdkFlutterPlugin.errSdkNotInitialized, message: PeSdkFlutterPlugin.errMessageSdkNotInitialized, details: nil))
            return
        }
        
        // Checking the license might take around 1 sec in the worst case.
        // Please optimize use if this method in your application for the best user experience
        photoEditorSDK?.getLicenseState(completion: { [weak self] isValid in
            guard let self else { return }
            if isValid {
                print("✅ The license is active")
                DispatchQueue.main.async {
                    self.photoEditorSDK?.presentPhotoEditor(withLaunchConfiguration: config, completion: nil)
                }
            } else {
                self.photoEditorSDK = nil
                print("❌ Use of SDK is restricted: the license is revoked or expired")
                flutterResult(FlutterError(code: PeSdkFlutterPlugin.errLicenseRevoked, message: PeSdkFlutterPlugin.errMessageLicenseRevoked, details: nil))
            }
        })
    }
}

// MARK: - BanubaPhotoEditorSDKDelegate
extension PhotoEditorModule: BanubaPhotoEditorDelegate {
    func photoEditorDidCancel(_ photoEditor: BanubaPhotoEditor) {
        print("Photo Editor SDK was cancelled")
        photoEditor.dismissPhotoEditor(animated: true) {
            self.photoEditorSDK = nil
            self.flutterResult?(FlutterError(code: PeSdkFlutterPlugin.errPhotoExportCancel, message: PeSdkFlutterPlugin.errMessagePhotoExportCancel, details: nil))
        }
    }
    
    func photoEditorDidFinishWithImage(_ photoEditor: BanubaPhotoEditor, image: UIImage) {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let imageData = image.jpegData(compressionQuality: 1.0) {
            let filename = paths[0].appendingPathComponent("\(Int(Date().timeIntervalSince1970)).jpg")
            do {
                try imageData.write(to: filename)
                print("Image saved at path: \(filename.path)")
                let data = [PeSdkFlutterPlugin.argExportedPhotoSource: filename.path]
                self.flutterResult?(data)
            } catch {
                print("Failed to save image: \(error.localizedDescription)")
                self.flutterResult?(FlutterError(code: PeSdkFlutterPlugin.errMissingSavedImage, message: PeSdkFlutterPlugin.errMissingSavedImage, details: nil))
            }
        }
        
        photoEditor.dismissPhotoEditor(animated: true){
            self.photoEditorSDK = nil
        }
    }
}
