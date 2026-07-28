import Flutter
import UIKit
import MediaPipeTasksVision

public class BeautyMediapipePlugin: NSObject, FlutterPlugin {
  private var faceBridge: FaceLandmarkerBridge?
  private var poseBridge: PoseLandmarkerBridge?
  private var segmenterBridge: ImageSegmenterBridge?
  private var metalBackend: BodyReshapeMetalBackend?

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
      do {
        try faceBridge?.initialize(modelPath: facePath)
        if let posePath, !posePath.isEmpty {
          try poseBridge?.initialize(modelPath: posePath)
        }
        if let segmenterPath, !segmenterPath.isEmpty {
          try segmenterBridge?.initialize(modelPath: segmenterPath)
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

    case "dispose":
      faceBridge?.dispose()
      poseBridge?.dispose()
      segmenterBridge?.dispose()
      result(nil)

    case "probeExportCapabilities":
      result(metalBackend?.capabilities() ?? [
        "metal": false,
        "vulkan": false,
        "openGlEs": false,
        "nativeJpegEncode": false,
      ])

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

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
