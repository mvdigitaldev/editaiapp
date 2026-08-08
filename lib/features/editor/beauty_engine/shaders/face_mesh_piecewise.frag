#include <flutter/runtime_effect.glsl>

/// Face mesh piecewise-affine warp (Sprint 37) — baricêntrico por pixel na GPU.
///
/// Texturas:
/// - uVertexDataTex (2 × vertexCount): col0 pos u16, col1 disp signed
/// - uTriIndexTex (1 × triangleCount): RGB = índices normalizados de vértice
/// - uCellTriMap: grade espacial → triângulo primário

uniform vec2 uImageSize;
uniform vec2 uTileOrigin;
uniform vec2 uTileSize;
uniform vec2 uCellGridSize;
uniform float uCellSize;
uniform float uVertexCount;
uniform float uTriangleCount;
uniform vec2 uDispScalePx;

uniform sampler2D uInputTexture;
uniform sampler2D uInfluenceMap;
uniform sampler2D uProtectionMap;
uniform sampler2D uCellTriMap;
uniform sampler2D uVertexDataTex;
uniform sampler2D uTriIndexTex;

out vec4 fragColor;

float decodeU16(vec2 ch) {
  return (ch.r * 256.0 + ch.g) / 65535.0;
}

float decodeSignedUnit(float ch) {
  return ch * 2.0 - 1.0;
}

vec2 loadVertexPos(float idx) {
  float y = (idx + 0.5) / uVertexCount;
  vec4 posRow = texture(uVertexDataTex, vec2(0.25, y));
  return vec2(decodeU16(posRow.rg), decodeU16(posRow.ba)) * uImageSize;
}

vec2 loadVertexDisp(float idx) {
  float y = (idx + 0.5) / uVertexCount;
  vec4 dispRow = texture(uVertexDataTex, vec2(0.75, y));
  return vec2(
    decodeSignedUnit(dispRow.r),
    decodeSignedUnit(dispRow.g)
  ) * uDispScalePx;
}

void loadTriangle(float triIdx, out float i0, out float i1, out float i2) {
  float y = (triIdx + 0.5) / uTriangleCount;
  vec3 idxNorm = texture(uTriIndexTex, vec2(0.5, y)).rgb;
  float maxIdx = max(uVertexCount - 1.0, 1.0);
  i0 = floor(idxNorm.r * maxIdx + 0.5);
  i1 = floor(idxNorm.g * maxIdx + 0.5);
  i2 = floor(idxNorm.b * maxIdx + 0.5);
}

vec3 barycentric(vec2 p, vec2 a, vec2 b, vec2 c) {
  float denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
  if (abs(denom) < 1e-8) {
    return vec3(0.0, 0.0, 0.0);
  }
  float w0 = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / denom;
  float w1 = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / denom;
  float w2 = 1.0 - w0 - w1;
  return vec3(w0, w1, w2);
}

void main() {
  vec2 local = FlutterFragCoord().xy;
  vec2 fullCoord = uTileOrigin + local;
  vec2 uv = fullCoord / uImageSize;

  float influence = texture(uInfluenceMap, uv).r;
  float protection = texture(uProtectionMap, uv).r;
  float effectiveMask = influence * (1.0 - protection);
  if (effectiveMask <= 0.001) {
    vec2 identityLocal = local / uTileSize;
    fragColor = texture(uInputTexture, clamp(identityLocal, vec2(0.0), vec2(1.0)));
    return;
  }

  vec2 cell = floor(fullCoord / uCellSize);
  vec2 cellUv = (cell + vec2(0.5)) / uCellGridSize;
  vec4 cellTri = texture(uCellTriMap, cellUv);
  if (cellTri.a <= 0.5) {
    vec2 identityLocal = local / uTileSize;
    fragColor = texture(uInputTexture, clamp(identityLocal, vec2(0.0), vec2(1.0)));
    return;
  }

  float triPacked = cellTri.r;
  float triIdx = floor(triPacked * (uTriangleCount + 1.0)) - 1.0;
  triIdx = clamp(triIdx, 0.0, uTriangleCount - 1.0);

  float i0;
  float i1;
  float i2;
  loadTriangle(triIdx, i0, i1, i2);

  vec2 v0 = loadVertexPos(i0);
  vec2 v1 = loadVertexPos(i1);
  vec2 v2 = loadVertexPos(i2);
  vec3 w = barycentric(fullCoord, v0, v1, v2);

  if (w.x < -0.001 || w.y < -0.001 || w.z < -0.001) {
    vec2 identityLocal = local / uTileSize;
    fragColor = texture(uInputTexture, clamp(identityLocal, vec2(0.0), vec2(1.0)));
    return;
  }

  vec2 d0 = loadVertexDisp(i0);
  vec2 d1 = loadVertexDisp(i1);
  vec2 d2 = loadVertexDisp(i2);
  vec2 delta = w.x * d0 + w.y * d1 + w.z * d2;
  vec2 pullPx = -delta * effectiveMask;

  float maxPull = max(uImageSize.x, uImageSize.y) * 0.08;
  float pullLength = length(pullPx);
  if (pullLength > maxPull && pullLength > 0.0001) {
    pullPx *= maxPull / pullLength;
  }

  vec2 srcUv = uv + pullPx / uImageSize;
  vec2 srcFull = srcUv * uImageSize;
  vec2 srcLocal = (srcFull - uTileOrigin) / uTileSize;
  srcLocal = clamp(srcLocal, vec2(0.0), vec2(1.0));
  fragColor = texture(uInputTexture, srcLocal);
}
