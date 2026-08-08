#version 320 es
precision highp float;

/// Makeup blend — blush/contour/eyebrows em OKLab aproximado (Sprint 8).
in vec2 vTexCoord;
out vec4 fragColor;

uniform sampler2D uInputTexture;
uniform sampler2D uBlushMask;
uniform sampler2D uContourMask;
uniform sampler2D uEyebrowMask;
uniform float uBlush;
uniform float uContour;
uniform float uEyebrows;

vec3 srgbToLinear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 linearToSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 rgbToOklab(vec3 rgb) {
  float l = dot(rgb, vec3(0.4122214708, 0.5363325363, 0.0514459929));
  float m = dot(rgb, vec3(0.2119034982, 0.6806995451, 0.1073969566));
  float s = dot(rgb, vec3(0.0883024619, 0.2817188376, 0.6299787005));
  l = pow(l, 1.0 / 3.0);
  m = pow(m, 1.0 / 3.0);
  s = pow(s, 1.0 / 3.0);
  return vec3(
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  );
}

vec3 oklabToRgb(vec3 lab) {
  float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
  float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
  float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
  float l = l_ * l_ * l_;
  float m = m_ * m_ * m_;
  float s = s_ * s_ * s_;
  return vec3(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

void main() {
  vec4 src = texture(uInputTexture, vTexCoord);
  vec3 rgb = srgbToLinear(src.rgb);
  vec3 lab = rgbToOklab(rgb);

  float blushW = texture(uBlushMask, vTexCoord).r * uBlush;
  if (blushW > 0.001) {
    vec3 blushLab = rgbToOklab(srgbToLinear(vec3(0.86, 0.38, 0.42)));
    lab = mix(lab, blushLab, blushW * 0.45);
  }

  float browW = texture(uEyebrowMask, vTexCoord).r * uEyebrows;
  if (browW > 0.001) {
    lab.x = mix(lab.x, lab.x - 0.08, browW * 0.55);
  }

  float contourW = texture(uContourMask, vTexCoord).r * uContour;
  if (contourW > 0.001) {
    lab.x = mix(lab.x, lab.x - 0.05, contourW * 0.35);
  }

  rgb = oklabToRgb(lab);
  fragColor = vec4(linearToSrgb(rgb), src.a);
}
