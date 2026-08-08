import Foundation
import Flutter
import Metal

/// Export face mesh piecewise-affine via Metal (Sprint 39).
///
/// Espelha `face_mesh_piecewise.frag` — baricêntrico por pixel na malha 478pt.
final class FaceMeshMetalBackend {
  private let device: MTLDevice?
  private var pipelineState: MTLRenderPipelineState?
  private var commandQueue: MTLCommandQueue?

  init() {
    device = MTLCreateSystemDefaultDevice()
    commandQueue = device?.makeCommandQueue()
    buildPipeline()
  }

  var isAvailable: Bool {
    device != nil && pipelineState != nil && commandQueue != nil
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

    let imageWidth = (args["imageWidth"] as? Double) ?? fullWidth
    let imageHeight = (args["imageHeight"] as? Double) ?? fullHeight
    let cellSize = (args["cellSize"] as? Double) ?? 2.5
    let vertexCount = (args["vertexCount"] as? Int) ?? 0
    let triangleCount = (args["triangleCount"] as? Int) ?? 0
    let dispScaleX = (args["displacementScaleX"] as? Double) ?? 1
    let dispScaleY = (args["displacementScaleY"] as? Double) ?? 1

    guard vertexCount > 0, triangleCount > 0,
          let vertexData = typedBytes(args["vertexData"]),
          let vertexDataW = args["vertexDataWidth"] as? Int,
          let vertexDataH = args["vertexDataHeight"] as? Int,
          let triIndexData = typedBytes(args["triIndexData"]),
          let triIndexW = args["triIndexWidth"] as? Int,
          let triIndexH = args["triIndexHeight"] as? Int,
          let cellTriData = typedBytes(args["cellTriData"]),
          let cellTriW = args["cellTriWidth"] as? Int,
          let cellTriH = args["cellTriHeight"] as? Int,
          let influence = typedBytes(args["influence"]),
          let influenceW = args["influenceWidth"] as? Int,
          let influenceH = args["influenceHeight"] as? Int,
          let protection = typedBytes(args["protection"]),
          let protectionW = args["protectionWidth"] as? Int,
          let protectionH = args["protectionHeight"] as? Int else {
      throw BackendError.invalidArgs
    }

    let sourceTex = try makeTexture(device: device, rgba: rgbaData, width: width, height: height)
    let influenceTex = try makeTexture(device: device, rgba: influence, width: influenceW, height: influenceH)
    let protectionTex = try makeTexture(device: device, rgba: protection, width: protectionW, height: protectionH)
    let cellTriTex = try makeTexture(device: device, rgba: cellTriData, width: cellTriW, height: cellTriH)
    let vertexTex = try makeTexture(device: device, rgba: vertexData, width: vertexDataW, height: vertexDataH)
    let triIndexTex = try makeTexture(device: device, rgba: triIndexData, width: triIndexW, height: triIndexH)

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
    encoder.setFragmentTexture(influenceTex, index: 1)
    encoder.setFragmentTexture(protectionTex, index: 2)
    encoder.setFragmentTexture(cellTriTex, index: 3)
    encoder.setFragmentTexture(vertexTex, index: 4)
    encoder.setFragmentTexture(triIndexTex, index: 5)

    var uniforms: [Float] = [
      Float(imageWidth), Float(imageHeight),
      Float(tileOriginX), Float(tileOriginY),
      Float(width), Float(height),
      Float(cellTriW), Float(cellTriH),
      Float(cellSize),
      Float(vertexCount), Float(triangleCount),
      Float(dispScaleX), Float(dispScaleY),
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

  private func buildPipeline() {
    guard let device else { return }
    do {
      let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
      guard let vertex = library.makeFunction(name: "face_mesh_vertex"),
            let fragment = library.makeFunction(name: "face_mesh_fragment") else {
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

  enum BackendError: Error {
    case unavailable
    case invalidArgs
    case textureFailed
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
    float2 cellGridSize;
    float cellSize;
    float vertexCount;
    float triangleCount;
    float2 dispScalePx;
  };

  vertex VertexOut face_mesh_vertex(uint vid [[vertex_id]]) {
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

  float decodeU16(float2 ch) {
    return (ch.r * 256.0 + ch.g) / 65535.0;
  }

  float decodeSignedUnit(float ch) {
    return ch * 2.0 - 1.0;
  }

  float2 loadVertexPos(texture2d<float> vertexDataTex, sampler s, float idx, float vertexCount, float2 imageSize) {
    float y = (idx + 0.5) / vertexCount;
    float4 posRow = vertexDataTex.sample(s, float2(0.25, y));
    return float2(decodeU16(posRow.rg), decodeU16(posRow.ba)) * imageSize;
  }

  float2 loadVertexDisp(texture2d<float> vertexDataTex, sampler s, float idx, float vertexCount, float2 dispScalePx) {
    float y = (idx + 0.5) / vertexCount;
    float4 dispRow = vertexDataTex.sample(s, float2(0.75, y));
    return float2(decodeSignedUnit(dispRow.r), decodeSignedUnit(dispRow.g)) * dispScalePx;
  }

  void loadTriangle(texture2d<float> triIndexTex, sampler s, float triIdx, float triangleCount, float vertexCount,
                    thread float& i0, thread float& i1, thread float& i2) {
    float y = (triIdx + 0.5) / triangleCount;
    float3 idxNorm = triIndexTex.sample(s, float2(0.5, y)).rgb;
    float maxIdx = max(vertexCount - 1.0, 1.0);
    i0 = floor(idxNorm.r * maxIdx + 0.5);
    i1 = floor(idxNorm.g * maxIdx + 0.5);
    i2 = floor(idxNorm.b * maxIdx + 0.5);
  }

  float3 barycentric(float2 p, float2 a, float2 b, float2 c) {
    float denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
    if (abs(denom) < 1e-8) {
      return float3(0.0, 0.0, 0.0);
    }
    float w0 = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / denom;
    float w1 = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / denom;
    float w2 = 1.0 - w0 - w1;
    return float3(w0, w1, w2);
  }

  fragment float4 face_mesh_fragment(
      VertexOut in [[stage_in]],
      constant Uniforms& u [[buffer(0)]],
      texture2d<float> src [[texture(0)]],
      texture2d<float> influence [[texture(1)]],
      texture2d<float> protection [[texture(2)]],
      texture2d<float> cellTriMap [[texture(3)]],
      texture2d<float> vertexDataTex [[texture(4)]],
      texture2d<float> triIndexTex [[texture(5)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::nearest);
    float2 local = in.uv * u.tileSize;
    float2 fullCoord = u.tileOrigin + local;
    float2 uv = fullCoord / u.imageSize;

    float inf = influence.sample(s, uv).r;
    float prot = protection.sample(s, uv).r;
    float effectiveMask = inf * (1.0 - prot);
    if (effectiveMask <= 0.001) {
      return src.sample(s, clamp(in.uv, float2(0.0), float2(1.0)));
    }

    float2 cell = floor(fullCoord / u.cellSize);
    float2 cellUv = (cell + float2(0.5)) / u.cellGridSize;
    float triNorm = cellTriMap.sample(s, cellUv).r;
    if (triNorm <= 0.0005) {
      return src.sample(s, clamp(in.uv, float2(0.0), float2(1.0)));
    }

    float triIdx = floor(triNorm * u.triangleCount);
    triIdx = clamp(triIdx, 0.0, u.triangleCount - 1.0);

    float i0, i1, i2;
    loadTriangle(triIndexTex, s, triIdx, u.triangleCount, u.vertexCount, i0, i1, i2);

    float2 v0 = loadVertexPos(vertexDataTex, s, i0, u.vertexCount, u.imageSize);
    float2 v1 = loadVertexPos(vertexDataTex, s, i1, u.vertexCount, u.imageSize);
    float2 v2 = loadVertexPos(vertexDataTex, s, i2, u.vertexCount, u.imageSize);
    float3 w = barycentric(fullCoord, v0, v1, v2);

    if (w.x < -0.001 || w.y < -0.001 || w.z < -0.001) {
      return src.sample(s, clamp(in.uv, float2(0.0), float2(1.0)));
    }

    float2 d0 = loadVertexDisp(vertexDataTex, s, i0, u.vertexCount, u.dispScalePx);
    float2 d1 = loadVertexDisp(vertexDataTex, s, i1, u.vertexCount, u.dispScalePx);
    float2 d2 = loadVertexDisp(vertexDataTex, s, i2, u.vertexCount, u.dispScalePx);
    float2 delta = w.x * d0 + w.y * d1 + w.z * d2;
    float2 pullPx = -delta * effectiveMask;

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
