#include <flutter/runtime_effect.glsl>

/// Body Reshape preview remap (Sprint 9).
/// Displacement RG: encoded signed unit (v*0.5+0.5) → decode rg*2-1 = dx/w, dy/h.
/// Effective mask = fieldMask * influence * (1 - protection).

uniform vec2 uImageSize;
uniform sampler2D uInputTexture;
uniform sampler2D uDisplacementMap;
uniform sampler2D uMaskMap;
uniform sampler2D uInfluenceMap;
uniform sampler2D uProtectionMap;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uImageSize;

  float mask = texture(uMaskMap, uv).r;
  float influence = texture(uInfluenceMap, uv).r;
  float protection = texture(uProtectionMap, uv).r;
  float effectiveMask = mask * influence * (1.0 - protection);

  if (effectiveMask <= 0.001) {
    fragColor = texture(uInputTexture, uv);
    return;
  }

  vec2 encoded = texture(uDisplacementMap, uv).rg;
  vec2 dispNorm = encoded * 2.0 - 1.0;
  // Liquify-style: scale displacement by mask — NEVER color-mix (avoids ghosting).
  vec2 srcUv = uv + dispNorm * effectiveMask;
  srcUv = clamp(srcUv, vec2(0.0), vec2(1.0));
  fragColor = texture(uInputTexture, srcUv);
}
