import Foundation
import UIKit
import MediaPipeTasksVision

final class ImageSegmenterBridge {
  private var imageSegmenter: ImageSegmenter?
  private var facePartsSegmenter: ImageSegmenter?

  func initialize(modelPath: String) throws {
    imageSegmenter = nil
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NSError(
        domain: "beauty_mediapipe",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(modelPath)"]
      )
    }

    let options = ImageSegmenterOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .image
    options.shouldOutputConfidenceMasks = true
    options.shouldOutputCategoryMask = false

    imageSegmenter = try ImageSegmenter(options: options)
  }

  /// Segmentação semântica multiclass (selfie_multiclass_256x256): usa
  /// category mask, um byte de classe por pixel, em vez das confidence masks
  /// do segmenter binário de pessoa.
  func initializeFaceParts(modelPath: String) throws {
    facePartsSegmenter = nil
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NSError(
        domain: "beauty_mediapipe",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Model file not found: \(modelPath)"]
      )
    }

    let options = ImageSegmenterOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .image
    options.shouldOutputConfidenceMasks = false
    options.shouldOutputCategoryMask = true

    facePartsSegmenter = try ImageSegmenter(options: options)
  }

  func detectFaceParts(
    imageBytes: Data,
    width: Int,
    height: Int,
    rotation: Int
  ) throws -> [String: Any]? {
    guard let segmenter = facePartsSegmenter else { return nil }
    guard let image = Self.decodeImage(
      imageBytes: imageBytes,
      width: width,
      height: height
    ) else { return nil }

    let oriented = rotate(image: image, degrees: rotation)
    guard let cgImage = oriented.cgImage else { return nil }

    let mpImage = try MPImage(uiImage: UIImage(cgImage: cgImage))
    let result = try segmenter.segment(image: mpImage)

    guard let mask = result.categoryMask else { return nil }
    let maskWidth = mask.width
    let maskHeight = mask.height
    let count = maskWidth * maskHeight
    let pointer = mask.uint8Data

    var bytes = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
      bytes[i] = pointer[i]
    }

    return [
      "bytes": Data(bytes),
      "width": maskWidth,
      "height": maskHeight,
    ]
  }

  func detectPersonMask(
    imageBytes: Data,
    width: Int,
    height: Int,
    rotation: Int
  ) throws -> [String: Any]? {
    guard let segmenter = imageSegmenter else { return nil }
    guard let image = Self.decodeImage(
      imageBytes: imageBytes,
      width: width,
      height: height
    ) else { return nil }

    let oriented = rotate(image: image, degrees: rotation)
    guard let cgImage = oriented.cgImage else { return nil }

    let mpImage = try MPImage(uiImage: UIImage(cgImage: cgImage))
    let result = try segmenter.segment(image: mpImage)

    guard let masks = result.confidenceMasks, !masks.isEmpty else {
      return nil
    }

    // Selfie: background=0, person=1. Alguns builds devolvem só a máscara da pessoa.
    let personMask = masks.count > 1 ? masks[1] : masks[0]
    let maskWidth = personMask.width
    let maskHeight = personMask.height
    let count = maskWidth * maskHeight
    let floatPtr = personMask.float32Data

    var bytes = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
      let v = max(0, min(1, floatPtr[i]))
      bytes[i] = UInt8(v * 255)
    }

    return [
      "bytes": Data(bytes),
      "width": maskWidth,
      "height": maskHeight,
    ]
  }

  func dispose() {
    imageSegmenter = nil
    facePartsSegmenter = nil
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
