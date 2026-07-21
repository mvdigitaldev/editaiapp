import Foundation
import UIKit
import MediaPipeTasksVision

final class FaceLandmarkerBridge {
  private var faceLandmarker: FaceLandmarker?

  func initialize(modelPath: String) throws {
    dispose()
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NSError(
        domain: "beauty_mediapipe",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(modelPath)"]
      )
    }

    var options = FaceLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .image
    options.numFaces = 1
    options.minFaceDetectionConfidence = 0.5
    options.minFacePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5

    faceLandmarker = try FaceLandmarker(options: options)
  }

  func detectFace(imageBytes: Data, width: Int, height: Int, rotation: Int) throws -> [String: Any]? {
    guard let landmarker = faceLandmarker else { return nil }
    guard let image = Self.decodeImage(
      imageBytes: imageBytes,
      width: width,
      height: height
    ) else { return nil }

    let oriented = rotate(image: image, degrees: rotation)
    guard let cgImage = oriented.cgImage else { return nil }

    let mpImage = try MPImage(uiImage: UIImage(cgImage: cgImage))
    let result = try landmarker.detect(image: mpImage)

    guard let landmarks = result.faceLandmarks.first, !landmarks.isEmpty else {
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
        "visibility": Double(landmark.visibility ?? 1.0),
      ])
    }

    return [
      "confidence": 0.9,
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
    faceLandmarker = nil
  }

  private static func decodeImage(imageBytes: Data, width: Int, height: Int) -> UIImage? {
    let rgbaSize = width * height * 4
    if width > 0 && height > 0 && imageBytes.count == rgbaSize {
      return rgbaToImage(bytes: [UInt8](imageBytes), width: width, height: height)
    }
    return UIImage(data: imageBytes)
  }

  private static func rgbaToImage(bytes: [UInt8], width: Int, height: Int) -> UIImage? {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    guard let cgImage = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ) else { return nil }
    return UIImage(cgImage: cgImage)
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
