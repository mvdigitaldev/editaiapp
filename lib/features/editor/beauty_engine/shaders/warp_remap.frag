#version 320 es
precision highp float;

/// Aplica WarpField via remap (Sprint 06 — GPU path Sprint 07).
/// Uniforms: uDisplacementMap, uMaskMap, uImageSize, uGridSize

in vec2 vTexCoord;
out vec4 fragColor;

uniform sampler2D uInputTexture;
uniform sampler2D uDisplacementMap;
uniform sampler2D uMaskMap;
uniform vec2 uImageSize;
uniform vec2 uGridSize;

void main() {
  float mask = texture(uMaskMap, vTexCoord).r;
  if (mask <= 0.001) {
    fragColor = texture(uInputTexture, vTexCoord);
    return;
  }

  vec2 dispNorm = texture(uDisplacementMap, vTexCoord).rg;
  vec2 dispPx = dispNorm * uImageSize;
  vec2 srcCoord = vTexCoord + dispPx / uImageSize;

  vec4 warped = texture(uInputTexture, srcCoord);
  vec4 original = texture(uInputTexture, vTexCoord);
  fragColor = mix(original, warped, mask);
}
