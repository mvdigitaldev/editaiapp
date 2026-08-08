#include <flutter/runtime_effect.glsl>

/// Body Reshape remap (Sprint 9 + tile export Sprint 13).
/// Displacement RG: signed unit (v*0.5+0.5), escalado por
/// uDisplacementScalePx para preservar precisão subpixel em RGBA8.
/// Effective mask = fieldMask * influence * (1 - protection).
///
/// Tile mode: uTileOrigin/uTileSize describe the current draw in full-image
/// pixels. Full-frame uses origin (0,0) and tileSize == uImageSize.

uniform vec2 uImageSize;
uniform vec2 uTileOrigin;
uniform vec2 uTileSize;
uniform vec2 uDisplacementScalePx;
uniform sampler2D uInputTexture;
uniform sampler2D uDisplacementMap;
uniform sampler2D uMaskMap;
uniform sampler2D uInfluenceMap;
uniform sampler2D uProtectionMap;

out vec4 fragColor;

void main() {
  vec2 local = FlutterFragCoord().xy;
  vec2 fullCoord = uTileOrigin + local;
  vec2 uv = fullCoord / uImageSize;

  float mask = texture(uMaskMap, uv).r;
  float influence = texture(uInfluenceMap, uv).r;
  float protection = texture(uProtectionMap, uv).r;
  // Suaviza transição da máscara sem degrau brusco (menos blockiness nas bordas).
  float edgeScale = smoothstep(0.0, 1.0, clamp(mask / 0.94, 0.0, 1.0));
  float effectiveMask = mask * influence * (1.0 - protection) * edgeScale;

  if (effectiveMask <= 0.001) {
    vec2 identityLocal = local / uTileSize;
    fragColor = texture(uInputTexture, clamp(identityLocal, vec2(0.0), vec2(1.0)));
    return;
  }

  vec2 encoded = texture(uDisplacementMap, uv).rg;
  vec2 dispPx = (encoded * 2.0 - 1.0) * uDisplacementScalePx;
  vec2 pullPx = dispPx * effectiveMask;
  float maxPull = max(uImageSize.x, uImageSize.y) * 0.08;
  float pullLength = length(pullPx);
  if (pullLength > maxPull && pullLength > 0.0001) {
    pullPx *= maxPull / pullLength;
  }
  // Liquify-style: scale displacement by mask — NEVER color-mix (avoids ghosting).
  vec2 srcUv = uv + pullPx / uImageSize;
  vec2 srcFull = srcUv * uImageSize;
  vec2 srcLocal = (srcFull - uTileOrigin) / uTileSize;
  srcLocal = clamp(srcLocal, vec2(0.0), vec2(1.0));
  fragColor = texture(uInputTexture, srcLocal);
}
