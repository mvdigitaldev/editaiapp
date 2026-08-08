#include <flutter/runtime_effect.glsl>

/// Inpaint leve pós-warp — preenche faixas fantasma a partir de vizinhos (Sprint 38).

uniform vec2 uImageSize;
uniform vec2 uTileOrigin;
uniform vec2 uTileSize;

uniform sampler2D uInputTexture;
uniform sampler2D uGhostMask;

out vec4 fragColor;

void main() {
  vec2 local = FlutterFragCoord().xy;
  vec2 fullCoord = uTileOrigin + local;
  vec2 uv = fullCoord / uImageSize;
  vec2 localUv = local / uTileSize;

  float ghost = texture(uGhostMask, uv).r;
  if (ghost <= 0.5) {
    fragColor = texture(uInputTexture, clamp(localUv, vec2(0.0), vec2(1.0)));
    return;
  }

  vec3 sum = vec3(0.0);
  float count = 0.0;
  const float radius = 4.0;

  for (float dy = -radius; dy <= radius; dy += 1.0) {
    for (float dx = -radius; dx <= radius; dx += 1.0) {
      if (dx == 0.0 && dy == 0.0) {
        continue;
      }
      vec2 nFull = fullCoord + vec2(dx, dy);
      vec2 nUv = nFull / uImageSize;
      if (nUv.x < 0.0 || nUv.y < 0.0 || nUv.x > 1.0 || nUv.y > 1.0) {
        continue;
      }
      if (texture(uGhostMask, nUv).r > 0.5) {
        continue;
      }
      vec2 nLocal = (nFull - uTileOrigin) / uTileSize;
      sum += texture(uInputTexture, clamp(nLocal, vec2(0.0), vec2(1.0))).rgb;
      count += 1.0;
    }
  }

  vec4 src = texture(uInputTexture, clamp(localUv, vec2(0.0), vec2(1.0)));
  if (count <= 0.5) {
    fragColor = src;
    return;
  }

  vec3 avg = sum / count;
  fragColor = vec4(mix(src.rgb, avg, 0.88), src.a);
}
