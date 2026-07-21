import Foundation
import UIKit
import MediaPipeTasksVision

final class PoseLandmarkerBridge {
  private var poseLandmarker: PoseLandmarker?

  func initialize(modelPath: String) throws {
    dispose()
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NSError(
        domain: "beauty_mediapipe",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(modelPath)"]
      )
    }

    var options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .image
    options.numPoses = 1
    options.minPoseDetectionConfidence = 0.5
    options.minPosePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5

    poseLandmarker = try PoseLandmarker(options: options)
  }

  func detectPose(imageBytes: Data, rotation: Int) throws -> [String: Any]? {
    guard let landmarker = poseLandmarker else { return nil }
    guard let image = UIImage(data: imageBytes) else { return nil }

    let oriented = rotate(image: image, degrees: rotation)
    guard let cgImage = oriented.cgImage else { return nil }

    let mpImage = try MPImage(uiImage: UIImage(cgImage: cgImage))
    let result = try landmarker.detect(image: mpImage)

    guard let landmarks = result.landmarks.first, !landmarks.isEmpty else {
      return nil
    }

    var mappedLandmarks: [[String: Any]] = []
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0

    for (index, landmark) in landmarks.enumerated() {
      let x = Double(landmark.x)
      let y = Double(landmark.y)
      minX = min(minX, x)
      minY = min(minY, y)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
      mappedLandmarks.append([
        "index": index,
        "x": x,
        "y": y,
        "z": Double(landmark.z),
        "visibility": Double(landmark.visibility ?? 0),
      ])
    }

    return [
      "landmarks": mappedLandmarks,
      "boundingBox": [
        "left": minX,
        "top": minY,
        "right": maxX,
        "bottom": maxY,
      ],
    ]
  }

  func dispose() {
    poseLandmarker = nil
  }

  private func rotate(image: UIImage, degrees: Int) -> UIImage {
    guard degrees % 360 != 0 else { return image }
    let radians = CGFloat(degrees) * .pi / 180
    let newSize = CGRect(origin: .zero, size: image.size)
      .applying(CGAffineTransform(rotationAngle: radians))
      .integral.size

    UIGraphicsBeginImageContext(newSize)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else { return image }

    context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
    context.rotate(by: radians)
    image.draw(
      in: CGRect(
        x: -image.size.width / 2,
        y: -image.size.height / 2,
        width: image.size.width,
        height: image.size.height
      )
    )
    return UIGraphicsGetImageFromCurrentImageContext() ?? image
  }
}
