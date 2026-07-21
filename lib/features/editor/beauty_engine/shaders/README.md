# Shaders GLSL/SPIR-V

| Shader | Sprint | Descricao |
|--------|--------|-----------|
| `warp_remap.frag` | 06 | Aplica WarpField (MLS remap) |
| `bilateral_skin.frag` | 08+ | Skin smooth |
| `lut_apply.frag` | — | LUT |
| `makeup_blend.frag` | — | Blush, lipstick, contour |

GPU path completo na Sprint 07. Sprint 06 usa CPU remap via `WarpCpuRemap` + `GPURendererStub`.
