import Foundation
import Flutter
import Metal

/// Backend GPU do Grupo A (pele): guided filter + separação de frequências
/// em luz linear, com float16 intermediário (Sprint 1 do SDK facial).
///
/// Espelha as constantes e o fluxo de `SkinRetouchEngine` (Dart). O caminho
/// Dart permanece como fallback quando Metal não está disponível.
final class SkinRetouchMetalBackend {
  private let device: MTLDevice?
  private var commandQueue: MTLCommandQueue?
  private var library: MTLLibrary?
  private var extractLumaPSO: MTLComputePipelineState?
  private var boxBlurHPSO: MTLComputePipelineState?
  private var boxBlurVPSO: MTLComputePipelineState?
  private var squarePSO: MTLComputePipelineState?
  private var guidedCoeffPSO: MTLComputePipelineState?
  private var guidedApplyPSO: MTLComputePipelineState?
  private var compositePSO: MTLComputePipelineState?
  private var darkCirclesPSO: MTLComputePipelineState?

  init() {
    device = MTLCreateSystemDefaultDevice()
    commandQueue = device?.makeCommandQueue()
    buildPipelines()
  }

  var isAvailable: Bool {
    device != nil &&
      commandQueue != nil &&
      extractLumaPSO != nil &&
      boxBlurHPSO != nil &&
      boxBlurVPSO != nil &&
      squarePSO != nil &&
      guidedCoeffPSO != nil &&
      guidedApplyPSO != nil &&
      compositePSO != nil &&
      darkCirclesPSO != nil
  }

  func skinRetouch(args: [String: Any]) throws -> FlutterStandardTypedData {
    guard let device, let commandQueue,
          let extractLumaPSO, let boxBlurHPSO, let boxBlurVPSO,
          let squarePSO, let guidedCoeffPSO, let guidedApplyPSO,
          let compositePSO, let darkCirclesPSO else {
      throw BackendError.unavailable
    }

    guard let rgbaData = (args["rgba"] as? FlutterStandardTypedData)?.data,
          let skinData = (args["skinWeights"] as? FlutterStandardTypedData)?.data,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0,
          rgbaData.count == width * height * 4,
          skinData.count == width * height else {
      throw BackendError.invalidArgs
    }

    let underEyeData = (args["underEyeWeights"] as? FlutterStandardTypedData)?.data
      ?? Data(count: width * height)
    let smooth = Float((args["smooth"] as? Double) ?? Double((args["smooth"] as? NSNumber)?.doubleValue ?? 0))
    let acne = Float((args["acne"] as? Double) ?? Double((args["acne"] as? NSNumber)?.doubleValue ?? 0))
    let wrinkles = Float((args["wrinkles"] as? Double) ?? Double((args["wrinkles"] as? NSNumber)?.doubleValue ?? 0))
    let darkCircles = Float((args["darkCircles"] as? Double) ?? Double((args["darkCircles"] as? NSNumber)?.doubleValue ?? 0))
    let shine = Float((args["shine"] as? Double) ?? Double((args["shine"] as? NSNumber)?.doubleValue ?? 0))
    let faceEdgePx = Float(
      (args["faceEdgePx"] as? Double) ??
        Double((args["faceEdgePx"] as? NSNumber)?.doubleValue ?? Double(max(width, height)))
    )

    let fineRadius = max(1, min(18, Int((faceEdgePx * 0.012).rounded())))
    let coarseRadius = max(3, min(48, fineRadius * 3))
    let blemishRadius = max(6, min(96, coarseRadius * 2))

    let srcTex = try makeRgbaTexture(device: device, rgba: rgbaData, width: width, height: height)
    let skinTex = try makeR8Texture(device: device, bytes: skinData, width: width, height: height)
    let underEyeTex = try makeR8Texture(device: device, bytes: underEyeData, width: width, height: height)

    let luma = try makeR16Texture(device: device, width: width, height: height)
    let scratchA = try makeR16Texture(device: device, width: width, height: height)
    let scratchB = try makeR16Texture(device: device, width: width, height: height)
    let meanI = try makeR16Texture(device: device, width: width, height: height)
    let meanII = try makeR16Texture(device: device, width: width, height: height)
    let meanA = try makeR16Texture(device: device, width: width, height: height)
    let meanB = try makeR16Texture(device: device, width: width, height: height)
    let fineBase = try makeR16Texture(device: device, width: width, height: height)
    let coarseBase = try makeR16Texture(device: device, width: width, height: height)
    let blemishRef = try makeR16Texture(device: device, width: width, height: height)
    let outTex = try makeRgbaTextureWritable(device: device, width: width, height: height)

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw BackendError.unavailable
    }

    dispatch(extractLumaPSO, commandBuffer, width, height) { enc in
      enc.setTexture(srcTex, index: 0)
      enc.setTexture(luma, index: 1)
    }

    runGuidedFilter(
      commandBuffer: commandBuffer,
      src: luma,
      scratchA: scratchA, scratchB: scratchB,
      meanI: meanI, meanII: meanII, meanA: meanA, meanB: meanB,
      out: fineBase,
      width: width, height: height, radius: fineRadius, eps: 2.5e-4,
      boxBlurHPSO: boxBlurHPSO, boxBlurVPSO: boxBlurVPSO,
      squarePSO: squarePSO, guidedCoeffPSO: guidedCoeffPSO, guidedApplyPSO: guidedApplyPSO
    )

    runGuidedFilter(
      commandBuffer: commandBuffer,
      src: luma,
      scratchA: scratchA, scratchB: scratchB,
      meanI: meanI, meanII: meanII, meanA: meanA, meanB: meanB,
      out: coarseBase,
      width: width, height: height, radius: coarseRadius, eps: 1.2e-3,
      boxBlurHPSO: boxBlurHPSO, boxBlurVPSO: boxBlurVPSO,
      squarePSO: squarePSO, guidedCoeffPSO: guidedCoeffPSO, guidedApplyPSO: guidedApplyPSO
    )

    if acne > 0 {
      boxBlur(commandBuffer, boxBlurHPSO, boxBlurVPSO, luma, scratchA, blemishRef,
              width, height, blemishRadius)
    }

    let skinReferenceLuma = weightedMeanLuma(
      rgba: rgbaData, skin: skinData, width: width, height: height, minWeight: 150
    )

    var uniforms = CompositeUniforms(
      smooth: smooth, acne: acne, wrinkles: wrinkles, shine: shine,
      skinReferenceLuma: skinReferenceLuma,
      highKeepAtMax: 0.70, midKeepAtMax: 0.30
    )
    dispatch(compositePSO, commandBuffer, width, height) { enc in
      enc.setTexture(srcTex, index: 0)
      enc.setTexture(luma, index: 1)
      enc.setTexture(fineBase, index: 2)
      enc.setTexture(coarseBase, index: 3)
      enc.setTexture(blemishRef, index: 4)
      enc.setTexture(skinTex, index: 5)
      enc.setTexture(outTex, index: 6)
      enc.setBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
    }

    var finalTex = outTex
    if darkCircles > 0 {
      let darkOut = try makeRgbaTextureWritable(device: device, width: width, height: height)
      let ref = skinReferenceOklab(
        rgba: rgbaData, skin: skinData, underEye: underEyeData,
        width: width, height: height
      )
      var dc = DarkCircleUniforms(
        intensity: darkCircles, refL: ref.0, refA: ref.1, refB: ref.2
      )
      dispatch(darkCirclesPSO, commandBuffer, width, height) { enc in
        enc.setTexture(outTex, index: 0) // read
        enc.setTexture(skinTex, index: 1)
        enc.setTexture(underEyeTex, index: 2)
        enc.setTexture(darkOut, index: 3) // write
        enc.setBytes(&dc, length: MemoryLayout<DarkCircleUniforms>.stride, index: 0)
      }
      finalTex = darkOut
    }

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    var outBytes = [UInt8](repeating: 0, count: width * height * 4)
    finalTex.getBytes(
      &outBytes,
      bytesPerRow: width * 4,
      from: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0
    )
    return FlutterStandardTypedData(bytes: Data(outBytes))
  }

  private func runGuidedFilter(
    commandBuffer: MTLCommandBuffer,
    src: MTLTexture,
    scratchA: MTLTexture, scratchB: MTLTexture,
    meanI: MTLTexture, meanII: MTLTexture,
    meanA: MTLTexture, meanB: MTLTexture,
    out: MTLTexture,
    width: Int, height: Int, radius: Int, eps: Float,
    boxBlurHPSO: MTLComputePipelineState,
    boxBlurVPSO: MTLComputePipelineState,
    squarePSO: MTLComputePipelineState,
    guidedCoeffPSO: MTLComputePipelineState,
    guidedApplyPSO: MTLComputePipelineState
  ) {
    boxBlur(commandBuffer, boxBlurHPSO, boxBlurVPSO, src, scratchA, meanI, width, height, radius)

    dispatch(squarePSO, commandBuffer, width, height) { enc in
      enc.setTexture(src, index: 0)
      enc.setTexture(scratchB, index: 1)
    }
    boxBlur(commandBuffer, boxBlurHPSO, boxBlurVPSO, scratchB, scratchA, meanII, width, height, radius)

    var epsLocal = eps
    dispatch(guidedCoeffPSO, commandBuffer, width, height) { enc in
      enc.setTexture(meanI, index: 0)
      enc.setTexture(meanII, index: 1)
      enc.setTexture(scratchA, index: 2) // a
      enc.setTexture(scratchB, index: 3) // b
      enc.setBytes(&epsLocal, length: 4, index: 0)
    }

    boxBlur(commandBuffer, boxBlurHPSO, boxBlurVPSO, scratchA, meanI, meanA, width, height, radius)
    boxBlur(commandBuffer, boxBlurHPSO, boxBlurVPSO, scratchB, meanI, meanB, width, height, radius)

    dispatch(guidedApplyPSO, commandBuffer, width, height) { enc in
      enc.setTexture(src, index: 0)
      enc.setTexture(meanA, index: 1)
      enc.setTexture(meanB, index: 2)
      enc.setTexture(out, index: 3)
    }
  }

  private func boxBlur(
    _ commandBuffer: MTLCommandBuffer,
    _ hPSO: MTLComputePipelineState,
    _ vPSO: MTLComputePipelineState,
    _ src: MTLTexture,
    _ tmp: MTLTexture,
    _ dst: MTLTexture,
    _ width: Int, _ height: Int, _ radius: Int
  ) {
    var r = UInt32(radius)
    dispatch(hPSO, commandBuffer, width, height) { enc in
      enc.setTexture(src, index: 0)
      enc.setTexture(tmp, index: 1)
      enc.setBytes(&r, length: 4, index: 0)
    }
    dispatch(vPSO, commandBuffer, width, height) { enc in
      enc.setTexture(tmp, index: 0)
      enc.setTexture(dst, index: 1)
      enc.setBytes(&r, length: 4, index: 0)
    }
  }

  private func dispatch(
    _ pso: MTLComputePipelineState,
    _ commandBuffer: MTLCommandBuffer,
    _ width: Int, _ height: Int,
    configure: (MTLComputeCommandEncoder) -> Void
  ) {
    guard let enc = commandBuffer.makeComputeCommandEncoder() else { return }
    enc.setComputePipelineState(pso)
    configure(enc)
    let tw = pso.threadExecutionWidth
    let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
    enc.dispatchThreads(
      MTLSize(width: width, height: height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1)
    )
    enc.endEncoding()
  }

  private func makeRgbaTexture(device: MTLDevice, rgba: Data, width: Int, height: Int) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderRead]
    guard let tex = device.makeTexture(descriptor: desc) else { throw BackendError.textureFailed }
    rgba.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      tex.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4
      )
    }
    return tex
  }

  private func makeRgbaTextureWritable(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: desc) else { throw BackendError.textureFailed }
    return tex
  }

  private func makeR8Texture(device: MTLDevice, bytes: Data, width: Int, height: Int) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderRead]
    guard let tex = device.makeTexture(descriptor: desc) else { throw BackendError.textureFailed }
    bytes.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      tex.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0, withBytes: base, bytesPerRow: width
      )
    }
    return tex
  }

  private func makeR16Texture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    guard let tex = device.makeTexture(descriptor: desc) else { throw BackendError.textureFailed }
    return tex
  }

  private func weightedMeanLuma(
    rgba: Data, skin: Data, width: Int, height: Int, minWeight: UInt8
  ) -> Float {
    var sum = 0.0
    var count = 0
    rgba.withUnsafeBytes { rgbaPtr in
      skin.withUnsafeBytes { skinPtr in
        guard let rBase = rgbaPtr.bindMemory(to: UInt8.self).baseAddress,
              let sBase = skinPtr.bindMemory(to: UInt8.self).baseAddress else { return }
        for p in 0..<(width * height) {
          if sBase[p] < minWeight { continue }
          let i = p * 4
          let r = srgbToLinear(rBase[i])
          let g = srgbToLinear(rBase[i + 1])
          let b = srgbToLinear(rBase[i + 2])
          sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
          count += 1
        }
      }
    }
    return count == 0 ? 0 : Float(sum / Double(count))
  }

  private func skinReferenceOklab(
    rgba: Data, skin: Data, underEye: Data, width: Int, height: Int
  ) -> (Float, Float, Float) {
    var sumL = 0.0, sumA = 0.0, sumB = 0.0
    var count = 0
    rgba.withUnsafeBytes { rgbaPtr in
      skin.withUnsafeBytes { skinPtr in
        underEye.withUnsafeBytes { eyePtr in
          guard let rBase = rgbaPtr.bindMemory(to: UInt8.self).baseAddress,
                let sBase = skinPtr.bindMemory(to: UInt8.self).baseAddress,
                let eBase = eyePtr.bindMemory(to: UInt8.self).baseAddress else { return }
          for p in 0..<(width * height) {
            if sBase[p] < 180 || eBase[p] > 0 { continue }
            let i = p * 4
            let lab = linearToOklab(
              srgbToLinear(rBase[i]),
              srgbToLinear(rBase[i + 1]),
              srgbToLinear(rBase[i + 2])
            )
            sumL += lab.0; sumA += lab.1; sumB += lab.2
            count += 1
          }
        }
      }
    }
    if count == 0 { return (0.7, 0.0, 0.0) }
    return (
      Float(sumL / Double(count)),
      Float(sumA / Double(count)),
      Float(sumB / Double(count))
    )
  }

  private func srgbToLinear(_ c8: UInt8) -> Double {
    let c = Double(c8) / 255.0
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }

  private func linearToOklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
    return (
      0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    )
  }

  private func buildPipelines() {
    guard let device else { return }
    do {
      library = try device.makeLibrary(source: Self.shaderSource, options: nil)
      guard let library else { return }
      func pso(_ name: String) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else {
          throw BackendError.unavailable
        }
        return try device.makeComputePipelineState(function: fn)
      }
      extractLumaPSO = try pso("skin_extract_luma")
      boxBlurHPSO = try pso("skin_box_blur_h")
      boxBlurVPSO = try pso("skin_box_blur_v")
      squarePSO = try pso("skin_square")
      guidedCoeffPSO = try pso("skin_guided_coeff")
      guidedApplyPSO = try pso("skin_guided_apply")
      compositePSO = try pso("skin_composite")
      darkCirclesPSO = try pso("skin_dark_circles")
    } catch {
      extractLumaPSO = nil
      boxBlurHPSO = nil
      boxBlurVPSO = nil
      squarePSO = nil
      guidedCoeffPSO = nil
      guidedApplyPSO = nil
      compositePSO = nil
      darkCirclesPSO = nil
    }
  }

  enum BackendError: Error {
    case unavailable
    case invalidArgs
    case textureFailed
  }

  private struct CompositeUniforms {
    var smooth: Float
    var acne: Float
    var wrinkles: Float
    var shine: Float
    var skinReferenceLuma: Float
    var highKeepAtMax: Float
    var midKeepAtMax: Float
  }

  private struct DarkCircleUniforms {
    var intensity: Float
    var refL: Float
    var refA: Float
    var refB: Float
  }

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  float srgb_to_linear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
  }
  float linear_to_srgb(float c) {
    c = clamp(c, 0.0, 1.0);
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0/2.4) - 0.055;
  }
  float luma_linear(float3 rgb) {
    return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
  }

  kernel void skin_extract_luma(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::write> luma [[texture(1)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float3 srgb = src.read(gid).rgb;
    float3 lin = float3(srgb_to_linear(srgb.r), srgb_to_linear(srgb.g), srgb_to_linear(srgb.b));
    luma.write(float4(luma_linear(lin), 0, 0, 1), gid);
  }

  kernel void skin_box_blur_h(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::write> dst [[texture(1)]],
      constant uint& radius [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    int r = int(radius);
    float sum = 0.0;
    int count = 0;
    for (int dx = -r; dx <= r; dx++) {
      int x = clamp(int(gid.x) + dx, 0, int(w) - 1);
      sum += src.read(uint2(x, gid.y)).r;
      count += 1;
    }
    dst.write(float4(sum / float(count), 0, 0, 1), gid);
  }

  kernel void skin_box_blur_v(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::write> dst [[texture(1)]],
      constant uint& radius [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    int r = int(radius);
    float sum = 0.0;
    int count = 0;
    for (int dy = -r; dy <= r; dy++) {
      int y = clamp(int(gid.y) + dy, 0, int(h) - 1);
      sum += src.read(uint2(gid.x, y)).r;
      count += 1;
    }
    dst.write(float4(sum / float(count), 0, 0, 1), gid);
  }

  kernel void skin_square(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::write> dst [[texture(1)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float v = src.read(gid).r;
    dst.write(float4(v * v, 0, 0, 1), gid);
  }

  kernel void skin_guided_coeff(
      texture2d<float, access::read> meanI [[texture(0)]],
      texture2d<float, access::read> meanII [[texture(1)]],
      texture2d<float, access::write> outA [[texture(2)]],
      texture2d<float, access::write> outB [[texture(3)]],
      constant float& eps [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= meanI.get_width() || gid.y >= meanI.get_height()) return;
    float mean = meanI.read(gid).r;
    float mii = meanII.read(gid).r;
    float variance = mii - mean * mean;
    float a = variance <= 0.0 ? 0.0 : variance / (variance + eps);
    float b = mean * (1.0 - a);
    outA.write(float4(a, 0, 0, 1), gid);
    outB.write(float4(b, 0, 0, 1), gid);
  }

  kernel void skin_guided_apply(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::read> meanA [[texture(1)]],
      texture2d<float, access::read> meanB [[texture(2)]],
      texture2d<float, access::write> outTex [[texture(3)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float v = meanA.read(gid).r * src.read(gid).r + meanB.read(gid).r;
    outTex.write(float4(v, 0, 0, 1), gid);
  }

  struct CompositeUniforms {
    float smooth;
    float acne;
    float wrinkles;
    float shine;
    float skinReferenceLuma;
    float highKeepAtMax;
    float midKeepAtMax;
  };

  kernel void skin_composite(
      texture2d<float, access::read> src [[texture(0)]],
      texture2d<float, access::read> luma [[texture(1)]],
      texture2d<float, access::read> fineBase [[texture(2)]],
      texture2d<float, access::read> coarseBase [[texture(3)]],
      texture2d<float, access::read> blemishRef [[texture(4)]],
      texture2d<float, access::read> skin [[texture(5)]],
      texture2d<float, access::write> outTex [[texture(6)]],
      constant CompositeUniforms& u [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float4 srgba = src.read(gid);
    float weight = skin.read(gid).r;
    if (weight <= 0.0) {
      outTex.write(srgba, gid);
      return;
    }
    float original = luma.read(gid).r;
    float low = coarseBase.read(gid).r;
    float fine = fineBase.read(gid).r;
    float mid = fine - low;
    float high = original - fine;

    float smoothStrength = min(1.0, u.smooth + u.wrinkles * 0.5);
    float midKeep = 1.0 - (1.0 - u.midKeepAtMax) * smoothStrength;
    float highKeep = 1.0 - (1.0 - u.highKeepAtMax) * smoothStrength;
    float lowMid = low + mid * midKeep;

    if (u.acne > 0.0) {
      float reference = blemishRef.read(gid).r;
      float deficit = reference - fine;
      float threshold = max(reference * 0.05, 0.0015);
      if (deficit > threshold) {
        float spot = clamp((deficit - threshold) / threshold, 0.0, 1.0);
        lowMid += deficit * u.acne * spot;
      }
    }

    float shineKnee = u.skinReferenceLuma * 1.18;
    if (u.shine > 0.0 && shineKnee > 0.0 && lowMid > shineKnee) {
      float excess = lowMid - shineKnee;
      lowMid = shineKnee + excess * (1.0 - 0.7 * u.shine);
    }

    float target = lowMid + high * highKeep;
    float blended = original + (target - original) * weight;

    float3 lin = float3(
      srgb_to_linear(srgba.r),
      srgb_to_linear(srgba.g),
      srgb_to_linear(srgba.b)
    );
    if (original <= 1e-5) {
      float v = linear_to_srgb(clamp(blended, 0.0, 1.0));
      outTex.write(float4(v, v, v, srgba.a), gid);
      return;
    }
    float factor = clamp(blended / original, 0.0, 4.0);
    float3 outLin = clamp(lin * factor, 0.0, 1.0);
    outTex.write(float4(
      linear_to_srgb(outLin.r),
      linear_to_srgb(outLin.g),
      linear_to_srgb(outLin.b),
      srgba.a
    ), gid);
  }

  struct DarkCircleUniforms {
    float intensity;
    float refL;
    float refA;
    float refB;
  };

  float3 linear_to_oklab(float3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    float l_ = pow(l, 1.0/3.0);
    float m_ = pow(m, 1.0/3.0);
    float s_ = pow(s, 1.0/3.0);
    return float3(
      0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
      1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
      0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
    );
  }
  float3 oklab_to_linear(float3 lab) {
    float l_ = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
    float m_ = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
    float s_ = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;
    float l = l_*l_*l_;
    float m = m_*m_*m_;
    float s = s_*s_*s_;
    return float3(
      +4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
      -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
      -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    );
  }

  kernel void skin_dark_circles(
      texture2d<float, access::read> img [[texture(0)]],
      texture2d<float, access::read> skin [[texture(1)]],
      texture2d<float, access::read> underEye [[texture(2)]],
      texture2d<float, access::write> outTex [[texture(3)]],
      constant DarkCircleUniforms& u [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= img.get_width() || gid.y >= img.get_height()) return;
    float4 srgba = img.read(gid);
    float region = underEye.read(gid).r;
    float sk = skin.read(gid).r;
    if (region <= 0.0 || sk <= 0.0) {
      outTex.write(srgba, gid);
      return;
    }
    float3 lin = float3(
      srgb_to_linear(srgba.r),
      srgb_to_linear(srgba.g),
      srgb_to_linear(srgba.b)
    );
    float3 lab = linear_to_oklab(lin);
    if (lab.x >= u.refL) {
      outTex.write(srgba, gid);
      return;
    }
    float t = clamp(u.intensity * region * sk, 0.0, 1.0);
    lab.x = lab.x + (u.refL - lab.x) * t;
    lab.y = lab.y + (u.refA - lab.y) * t * 0.6;
    lab.z = lab.z + (u.refB - lab.z) * t * 0.6;
    float3 outLin = clamp(oklab_to_linear(lab), 0.0, 1.0);
    outTex.write(float4(
      linear_to_srgb(outLin.r),
      linear_to_srgb(outLin.g),
      linear_to_srgb(outLin.b),
      srgba.a
    ), gid);
  }
  """
}
