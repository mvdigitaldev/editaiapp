import Foundation
import Flutter
import Metal
import CoreGraphics
import ImageIO
import MobileCoreServices

/// Backend de export Body Reshape via Metal (Sprint 13).
///
/// Remap GPU full-frame/tile com displacement RG encoded (igual ao shader Dart).
final class BodyReshapeMetalBackend {
  private let device: MTLDevice?
  private var pipelineState: MTLRenderPipelineState?
  private var commandQueue: MTLCommandQueue?
  private var library: MTLLibrary?

  init() {
    device = MTLCreateSystemDefaultDevice()
    commandQueue = device?.makeCommandQueue()
    buildPipeline()
  }

  var isAvailable: Bool {
    device != nil && pipelineState != nil && commandQueue != nil
  }

  func capabilities() -> [String: Any] {
    [
      "metal": isAvailable,
      "vulkan": false,
      "openGlEs": false,
      "nativeJpegEncode": true,
    ]
  }

  func warpExport(args: [String: Any]) throws -> FlutterStandardTypedData {
    guard let device, let pipelineState, let commandQueue else {
      throw BackendError.unavailable
    }
    guard let rgbaData = (args["rgba"] as? FlutterStandardTypedData)?.data,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0,
          rgbaData.count == width * height * 4 else {
      throw BackendError.invalidArgs
    }

    let fullWidth = (args["fullWidth"] as? Double) ?? Double(width)
    let fullHeight = (args["fullHeight"] as? Double) ?? Double(height)
    let tileOriginX = (args["tileOriginX"] as? Double) ?? 0
    let tileOriginY = (args["tileOriginY"] as? Double) ?? 0
    let displacementScaleX = (args["displacementScaleX"] as? Double) ?? 1
    let displacementScaleY = (args["displacementScaleY"] as? Double) ?? 1

    guard let disp = typedBytes(args["displacement"]),
          let dispW = args["displacementWidth"] as? Int,
          let dispH = args["displacementHeight"] as? Int,
          let mask = typedBytes(args["mask"]),
          let maskW = args["maskWidth"] as? Int,
          let maskH = args["maskHeight"] as? Int else {
      throw BackendError.invalidArgs
    }

    let influence = typedBytes(args["influence"])
    let influenceW = (args["influenceWidth"] as? Int) ?? 1
    let influenceH = (args["influenceHeight"] as? Int) ?? 1
    let protection = typedBytes(args["protection"])
    let protectionW = (args["protectionWidth"] as? Int) ?? 1
    let protectionH = (args["protectionHeight"] as? Int) ?? 1

    let sourceTex = try makeTexture(device: device, rgba: rgbaData, width: width, height: height)
    let dispTex = try makeTexture(device: device, rgba: disp, width: dispW, height: dispH)
    let maskTex = try makeTexture(device: device, rgba: mask, width: maskW, height: maskH)
    let infTex = try makeTexture(
      device: device,
      rgba: influence ?? whitePixel(),
      width: influence == nil ? 1 : influenceW,
      height: influence == nil ? 1 : influenceH
    )
    let protTex = try makeTexture(
      device: device,
      rgba: protection ?? blackPixel(),
      width: protection == nil ? 1 : protectionW,
      height: protection == nil ? 1 : protectionH
    )

    let outDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    outDesc.usage = [.renderTarget, .shaderRead]
    guard let outTex = device.makeTexture(descriptor: outDesc) else {
      throw BackendError.textureFailed
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let passDesc = MTLRenderPassDescriptor() as MTLRenderPassDescriptor? else {
      throw BackendError.unavailable
    }
    passDesc.colorAttachments[0].texture = outTex
    passDesc.colorAttachments[0].loadAction = .clear
    passDesc.colorAttachments[0].storeAction = .store
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
      throw BackendError.unavailable
    }
    encoder.setRenderPipelineState(pipelineState)
    encoder.setFragmentTexture(sourceTex, index: 0)
    encoder.setFragmentTexture(dispTex, index: 1)
    encoder.setFragmentTexture(maskTex, index: 2)
    encoder.setFragmentTexture(infTex, index: 3)
    encoder.setFragmentTexture(protTex, index: 4)

    var uniforms: [Float] = [
      Float(fullWidth), Float(fullHeight),
      Float(tileOriginX), Float(tileOriginY),
      Float(width), Float(height),
      Float(displacementScaleX), Float(displacementScaleY),
    ]
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Float>.size * uniforms.count, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    var outBytes = [UInt8](repeating: 0, count: width * height * 4)
    outTex.getBytes(
      &outBytes,
      bytesPerRow: width * 4,
      from: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0
    )
    return FlutterStandardTypedData(bytes: Data(outBytes))
  }

  func encodeJpeg(args: [String: Any]) throws -> FlutterStandardTypedData {
    guard let rgbaData = (args["rgba"] as? FlutterStandardTypedData)?.data,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0 else {
      throw BackendError.invalidArgs
    }
    let quality = max(1, min(100, (args["quality"] as? Int) ?? 90))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: rgbaData as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
      throw BackendError.encodeFailed
    }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      data, kUTTypeJPEG, 1, nil
    ) else {
      throw BackendError.encodeFailed
    }
    let opts: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
    ]
    CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      throw BackendError.encodeFailed
    }
    return FlutterStandardTypedData(bytes: data as Data)
  }

  private func buildPipeline() {
    guard let device else { return }
    do {
      library = try device.makeLibrary(source: Self.shaderSource, options: nil)
      guard let library,
            let vertex = library.makeFunction(name: "body_reshape_vertex"),
            let fragment = library.makeFunction(name: "body_reshape_fragment") else {
        return
      }
      let desc = MTLRenderPipelineDescriptor()
      desc.vertexFunction = vertex
      desc.fragmentFunction = fragment
      desc.colorAttachments[0].pixelFormat = .rgba8Unorm
      pipelineState = try device.makeRenderPipelineState(descriptor: desc)
    } catch {
      pipelineState = nil
    }
  }

  private func makeTexture(device: MTLDevice, rgba: Data, width: Int, height: Int) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead]
    guard let tex = device.makeTexture(descriptor: desc) else {
      throw BackendError.textureFailed
    }
    rgba.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      tex.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: base,
        bytesPerRow: width * 4
      )
    }
    return tex
  }

  private func typedBytes(_ value: Any?) -> Data? {
    (value as? FlutterStandardTypedData)?.data
  }

  private func whitePixel() -> Data {
    Data([255, 255, 255, 255])
  }

  private func blackPixel() -> Data {
    Data([0, 0, 0, 255])
  }

  enum BackendError: Error {
    case unavailable
    case invalidArgs
    case textureFailed
    case encodeFailed
  }

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct VertexOut {
    float4 position [[position]];
    float2 uv;
  };

  struct Uniforms {
    float2 imageSize;
    float2 tileOrigin;
    float2 tileSize;
    float2 displacementScalePx;
  };

  vertex VertexOut body_reshape_vertex(uint vid [[vertex_id]]) {
    float2 positions[6] = {
      float2(-1, -1), float2(1, -1), float2(-1, 1),
      float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    float2 uvs[6] = {
      float2(0, 1), float2(1, 1), float2(0, 0),
      float2(0, 0), float2(1, 1), float2(1, 0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
  }

  fragment float4 body_reshape_fragment(
      VertexOut in [[stage_in]],
      constant Uniforms& u [[buffer(0)]],
      texture2d<float> src [[texture(0)]],
      texture2d<float> disp [[texture(1)]],
      texture2d<float> maskTex [[texture(2)]],
      texture2d<float> influence [[texture(3)]],
      texture2d<float> protection [[texture(4)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 local = in.uv * u.tileSize;
    float2 fullCoord = u.tileOrigin + local;
    float2 uv = fullCoord / u.imageSize;

    float m = maskTex.sample(s, uv).r;
    float inf = influence.sample(s, uv).r;
    float prot = protection.sample(s, uv).r;
    float edgeScale = clamp(m / 0.88, 0.0, 1.0);
    float effective = m * inf * (1.0 - prot) * edgeScale * edgeScale;
    if (effective <= 0.001) {
      return src.sample(s, in.uv);
    }
    float2 encoded = disp.sample(s, uv).rg;
    float2 dispPx = (encoded * 2.0 - 1.0) * u.displacementScalePx;
    float2 pullPx = dispPx * effective;
    float maxPull = max(u.imageSize.x, u.imageSize.y) * 0.08;
    float pullLength = length(pullPx);
    if (pullLength > maxPull && pullLength > 0.0001) {
      pullPx *= maxPull / pullLength;
    }
    float2 srcUv = uv + pullPx / u.imageSize;
    float2 srcFull = srcUv * u.imageSize;
    float2 srcLocal = (srcFull - u.tileOrigin) / u.tileSize;
    srcLocal = clamp(srcLocal, float2(0.0), float2(1.0));
    return src.sample(s, srcLocal);
  }
  """
}
