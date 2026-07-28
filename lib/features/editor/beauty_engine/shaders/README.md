# Shaders GLSL / Flutter FragmentProgram

| Shader | Sprint | Descricao |
|--------|--------|-----------|
| `body_reshape_remap.frag` | 09 | Preview Body Reshape (Impeller / FragmentProgram) |
| `warp_remap.frag` | 06 | Referência GLSL ES do WarpField (legado) |
| `bilateral_skin.frag` | 08+ | Skin smooth |
| `lut_apply.frag` | — | LUT |
| `makeup_blend.frag` | — | Blush, lipstick, contour |

Preview V2 (Sprint 9): `FragmentProgramWarpBackend` + `body_reshape_remap.frag`.
Fallback CPU: `WarpCpuRemap` quando o FragmentProgram não estiver disponível.
