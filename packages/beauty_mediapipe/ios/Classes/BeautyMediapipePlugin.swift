import Flutter
import UIKit
import MediaPipeTasksVision

public class BeautyMediapipePlugin: NSObject, FlutterPlugin {
  private var faceBridge: FaceLandmarkerBridge?
  private var poseBridge: PoseLandmarkerBridge?
  private var segmenterBridge: ImageSegmenterBridge?
  private var metalBackend: BodyReshapeMetalBackend?
  private var skinBackend: SkinRetouchMetalBackend?
  private var faceMeshBackend: FaceMeshMetalBackend?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.editaiapp/beauty_mediapipe",
      binaryMessenger: registrar.messenger()
    )
    let instance = BeautyMediapipePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.faceBridge = FaceLandmarkerBridge()
    instance.poseBridge = PoseLandmarkerBridge()
    instance.segmenterBridge = ImageSegmenterBridge()
    instance.metalBackend = BodyReshapeMetalBackend()
    instance.skinBackend = SkinRetouchMetalBackend()
    instance.faceMeshBackend = FaceMeshMetalBackend()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      guard let args = call.arguments as? [String: Any],
            let facePath = args["faceModelPath"] as? String else {
        result(FlutterError(code: "invalid_args", message: "faceModelPath required", details: nil))
        return
      }
      let posePath = args["poseModelPath"] as? String
      let segmenterPath = args["segmenterModelPath"] as? String
      let facePartsPath = args["facePartsModelPath"] as? String
      do {
        try faceBridge?.initialize(modelPath: facePath)
        if let posePath, !posePath.isEmpty {
          try poseBridge?.initialize(modelPath: posePath)
        }
        if let segmenterPath, !segmenterPath.isEmpty {
          try segmenterBridge?.initialize(modelPath: segmenterPath)
        }
        if let facePartsPath, !facePartsPath.isEmpty {
          // Falha no multiclass não pode derrubar a inicialização: a pele
          // cai no fallback geométrico.
          try? segmenterBridge?.initializeFaceParts(modelPath: facePartsPath)
        }
        result(nil)
      } catch {
        result(FlutterError(code: "init_failed", message: error.localizedDescription, details: nil))
      }

    case "detectFace":
      guard let bridge = faceBridge else {
        result(FlutterError(code: "not_initialized", message: "Face bridge unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args", message: "bytes required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      do {
        let mapped = try bridge.detectFace(
          imageBytes: bytes.data,
          width: width,
          height: height,
          rotation: rotation
        )
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "detectFaces":
      guard let bridge = faceBridge else {
        result(FlutterError(code: "not_initialized", message: "Face bridge unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args", message: "bytes required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      do {
        let mapped = try bridge.detectFaces(
          imageBytes: bytes.data,
          width: width,
          height: height,
          rotation: rotation
        )
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "detectPose":
      guard let bridge = poseBridge else {
        result(FlutterError(code: "not_initialized", message: "Pose bridge unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args", message: "bytes required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      do {
        let mapped = try bridge.detectPose(
          imageBytes: bytes.data,
          width: width,
          height: height,
          rotation: rotation
        )
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "detectPersonMask":
      guard let bridge = segmenterBridge else {
        result(FlutterError(code: "not_initialized", message: "Segmenter bridge unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args", message: "bytes required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      do {
        let mapped = try bridge.detectPersonMask(
          imageBytes: bytes.data,
          width: width,
          height: height,
          rotation: rotation
        )
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "detectFaceParts":
      guard let bridge = segmenterBridge else {
        result(FlutterError(code: "not_initialized", message: "Segmenter bridge unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args", message: "bytes required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      do {
        let mapped = try bridge.detectFaceParts(
          imageBytes: bytes.data,
          width: width,
          height: height,
          rotation: rotation
        )
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "detectFaceParsing":
      // BiSeNet CoreML ainda não empacotado — mapper Dart assume (Sprint 4).
      result(nil)

    case "dispose":
      faceBridge?.dispose()
      poseBridge?.dispose()
      segmenterBridge?.dispose()
      result(nil)

    case "probeExportCapabilities":
      var caps: [String: Any] = metalBackend?.capabilities() ?? [
        "metal": false,
        "vulkan": false,
        "openGlEs": false,
        "nativeJpegEncode": false,
      ]
      caps["skinRetouch"] = skinBackend?.isAvailable ?? false
      caps["skinGpu"] = skinBackend?.isAvailable ?? false
      caps["faceMeshMetal"] = faceMeshBackend?.isAvailable ?? false
      caps["faceMeshGles"] = false
      result(caps)

    case "faceMeshWarpExport":
      guard let backend = faceMeshBackend, backend.isAvailable else {
        result(FlutterError(code: "unavailable", message: "Face mesh Metal export unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "args required", details: nil))
        return
      }
      do {
        let data = try backend.warpExport(args: args)
        result(data)
      } catch {
        result(FlutterError(code: "face_mesh_warp_failed", message: error.localizedDescription, details: nil))
      }

    case "skinRetouchExport":
      guard let backend = skinBackend, backend.isAvailable else {
        result(FlutterError(code: "unavailable", message: "Metal skin retouch unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "args required", details: nil))
        return
      }
      do {
        let data = try backend.skinRetouch(args: args)
        result(data)
      } catch {
        result(FlutterError(code: "skin_failed", message: error.localizedDescription, details: nil))
      }

    case "warpExport":
      guard let backend = metalBackend, backend.isAvailable else {
        result(FlutterError(code: "unavailable", message: "Metal export unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "args required", details: nil))
        return
      }
      do {
        let data = try backend.warpExport(args: args)
        result(data)
      } catch {
        result(FlutterError(code: "warp_failed", message: error.localizedDescription, details: nil))
      }

    case "encodeJpeg":
      guard let backend = metalBackend else {
        result(FlutterError(code: "unavailable", message: "JPEG encode unavailable", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "args required", details: nil))
        return
      }
      do {
        let data = try backend.encodeJpeg(args: args)
        result(data)
      } catch {
        result(FlutterError(code: "encode_failed", message: error.localizedDescription, details: nil))
      }

    case "releaseExportResource":
      result(nil)

    case "getThermalState":
      let mapped: String
      if #available(iOS 11.0, *) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
          mapped = "nominal"
        case .fair:
          mapped = "fair"
        case .serious:
          mapped = "serious"
        case .critical:
          mapped = "critical"
        @unknown default:
          mapped = "nominal"
        }
      } else {
        mapped = "nominal"
      }
      result(mapped)

    case "probeHotPathCapabilities":
      result([
        "ffiAvailable": false,
        "sharedMemorySupported": false,
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
