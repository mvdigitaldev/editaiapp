# Sprint 8 — Paridade Banuba (Warp V2 + Makeup GPU)

Sprint de fechamento de gap entre o editor facial nativo e o Banuba SDK.
Foco em **isolamento regional do warp** e **makeup perceptual** (OKLab + máscaras elípticas).

## Entregas

### Trilha A — Warp V2

| Item | Arquivo | Status |
|------|---------|--------|
| Grupos regionais (`lowerFace`, `midFace`, `eyes`, `mouth`, `cheek`, `contour`) | `filters/face/face_warp_region.dart` | ✅ |
| `FaceInfluenceMapBuilder` — raster 0–1 por landmark + feather | `filters/face/face_influence_map_builder.dart` | ✅ |
| Composição `WarpField.composeSequential` por região | `filters/face/face_filter_pipeline.dart` | ✅ |
| Centro facial real (`faceCenter` / landmarks 1·168·152) | `filters/face/face_warp_context.dart` | ✅ |
| Jaw — estabilizadores testa + influence `lowerFace` | `filters/face/jaw.dart` | ✅ |
| Chin — landmark 152, pivot queixo, lábio estabilizado | `filters/face/chin.dart` | ✅ |
| Head size — pivot `faceOval` geométrico | `filters/face/head_size.dart` | ✅ |
| Nose slim — CPs dorsais + campo isolado `midFace` | `filters/face/nose_slim.dart` | ✅ |
| Cheekbone — overlay retangular GPU **desativado** | `beauty_engine_controller.dart` | ✅ |

### Trilha B — Makeup

| Item | Arquivo | Status |
|------|---------|--------|
| Blush elíptico + `skinWeights` + excluir testa | `filters/face/skin_mask_utils.dart` | ✅ |
| OKLab interim (whitening, blush, eyebrows) | `filters/face/makeup_blend_engine.dart`, `pass_skin_engine.dart` | ✅ |
| `makeup_blend.frag` + `PassMakeupBlend` registrado | `shaders/makeup_blend.frag`, `shader_program_cache.dart` | ✅ |
| `MaskSamplingContext` no apply pós-warp | `pass_skin_engine.dart` | ✅ |

### Trilha C — QA

| Item | Arquivo | Status |
|------|---------|--------|
| Golden jaw / nose (invariantes B3–B4) | `test/golden/face_warp_*_golden_test.dart` | ✅ |
| Golden Grupo C (blush/whitening) | `test/golden/skin_group_c_golden_test.dart` | ✅ |
| Matriz A/B no `/face-retouch-lab` | `presentation/widgets/parity_checklist_panel.dart` | ✅ |

## Sprint 8b — Warp por malha (Banuba-grade)

Referência: [FaceStudio](https://github.com/georgegach/facestudio) usa **piecewise-affine** na malha MediaPipe 478pt, não MLS numa grade grossa.

| Melhoria | Arquivo |
|----------|---------|
| `FaceMeshWarpRasterizer` — baricentrico na malha deformada | `warp/face_mesh_warp_rasterizer.dart` |
| Grade escala com resolução (~4 px/cél, até 512) | `warp/warp_field_builder.dart` |
| Influence map sem envelope retangular | `warp/warp_field_builder.dart` |
| Influence map 128–384 px (proporcional) | `face_influence_map_builder.dart` |
| `refinedForRender` + MLS re-solve pós-upsampling | `models/warp_field.dart` |
| Máscara composta suave (union, não max) | `warp_field.dart` composeSequential |
| Shader: edgeScale linear (sem x²) | `body_reshape_remap.frag` |
| Refine em preview **e** export | `beauty_engine_controller.dart` |


```
Filtros ativos → agrupados por FaceWarpRegion
  → CPs por grupo + InfluenceMap regional
  → WarpField por grupo
  → composeSequential(contour → lowerFace → midFace → cheek → eyes → mouth)
  → GPU warp_remap.frag

Makeup: PassSkinEngine (retouch) + MakeupBlendEngine OKLab (whitening/blush/brows)
  → makeup_blend.frag registrado para path GPU futuro
```

## Paridade estimada

| Milestone | ~% | Ferramentas |
|-----------|-----|-------------|
| Pós A1–A3 | 30–40% | jaw, chin, nose, head, eyes |
| Pós B1–B2 | 50% | blush, whitening, eyebrows |
| Pós A4 + B3 + golden | 65–75% | restante + estabilidade |

## Critério de rollout nativo

Ferramenta só entra no rollout remoto quando passar invariantes B1–B6 / Grupo C em
[`13-visual-quality-targets.md`](13-visual-quality-targets.md), validados no
`/face-retouch-lab` com checklist A/B.

## O que ficou de fora (Sprint 9+)

- Path GPU completo de `makeup_blend.frag` (CPU interim cobre produção)
- TPS/ARAP warp regional
- Presets adaptativos por corpus real
- Swap Banuba → nativo em produção (continua controlado por rollout %)
