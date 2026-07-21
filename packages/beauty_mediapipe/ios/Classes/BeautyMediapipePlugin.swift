import Flutter
import UIKit
import MediaPipeTasksVision

public class BeautyMediapipePlugin: NSObject, FlutterPlugin {
  private var faceBridge: FaceLandmarkerBridge?
  private var poseBridge: PoseLandmarkerBridge?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.editaiapp/beauty_mediapipe",
      binaryMessenger: registrar.messenger()
    )
    let instance = BeautyMediapipePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.faceBridge = FaceLandmarkerBridge()
    instance.poseBridge = PoseLandmarkerBridge()
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
      do {
        try faceBridge?.initialize(modelPath: facePath)
        if let posePath, !posePath.isEmpty {
          try poseBridge?.initialize(modelPath: posePath)
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
      do {
        let mapped = try bridge.detectFace(imageBytes: bytes.data, rotation: rotation)
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
      do {
        let mapped = try bridge.detectPose(imageBytes: bytes.data, rotation: rotation)
        result(mapped)
      } catch {
        result(FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
      }

    case "dispose":
      faceBridge?.dispose()
      poseBridge?.dispose()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
