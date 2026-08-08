# Sprint 37 — GPU piecewise-affine + inpainting pós-warp

## Objetivo

Eliminar a grade intermediária de displacement no path de preview/export facial,
computando warp **piecewise-affine por pixel na GPU**, e reduzir fantasma residual
em warps laterais (`eye_distance`, contorno) com inpainting leve pós-warp.

## Entregas

### Trilha A — GPU piecewise-affine

| Item | Arquivo |
|------|---------|
| Grade espacial célula → triângulo | `warp/face_mesh_cell_index.dart` |
| Atlas RGBA8 (vértices, triângulos, células) | `warp/face_mesh_gpu_payload.dart` |
| Shader baricêntrico por pixel | `shaders/face_mesh_piecewise.frag` |
| Backend FragmentProgram | `warp/fragment_program_face_mesh_backend.dart` |
| `TriMeshSpatialIndex.locateTriangleIndex` | `mesh/tri_mesh_spatial_index.dart` |
| Flag `useGpuPiecewiseAffine` | `config/face_warp_v3_config.dart` |
| PassId `face_mesh_v3_gpu` | `warp/anatomy/face_mesh_deformation_engine.dart` |
| Integração PassWarp + controller | `rendering/pass_warp.dart`, `controllers/beauty_engine_controller.dart` |
| Toggle lab (ícone memory) | `presentation/beauty_editor_page.dart` |
| Backend debug `v3_gpu` | controller |

Fluxo:

```
ACE → ConstrainedVertexField
  → FaceMeshGpuAtlas (texturas)
  → face_mesh_piecewise.frag (baricêntrico por pixel)
  → RGBA warped
```

Fallback: se GPU indisponível, usa `WarpField` (grade direct Sprint 36).

### Trilha B — Inpainting pós-warp

| Item | Arquivo |
|------|---------|
| Detecção de faixas fantasma (disp local ≪ vizinhos) | `warp/face_warp_post_inpaint.dart` |
| Flag `usePostWarpInpaint` | `config/face_warp_v3_config.dart` |
| Aplicação após warp no PassWarp | `rendering/pass_warp.dart` |
| Toggle lab (ícone healing) | `presentation/beauty_editor_page.dart` |

Ativo apenas para tools laterais (`FaceWarpVacancyFill.lateralToolKeys`).

### Trilha C — Cache / QA

| Item | Arquivo |
|------|---------|
| Cache key `useGpuPiecewiseAffine` | `rendering/render_stage_cache.dart` |
| Testes unitários Sprint 37 | `test/beauty_engine/warp/face_warp_v3_gpu_inpaint_test.dart` |

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_v3_gpu_inpaint_test.dart
flutter test test/beauty_engine/warp/
```

## Critério de saída

- [ ] Lab: toggle GPU piecewise + badge `v3_gpu`
- [ ] Lab: toggle inpaint pós-warp
- [ ] Testes Sprint 37 verdes
- [ ] Fallback CPU quando FragmentProgram indisponível
- [ ] Validação visual A/B no `/face-retouch-lab`

## Próximo (Sprint 39+)

Ver [`24-sprint38-export-inpaint-rollout.md`](24-sprint38-export-inpaint-rollout.md) — concluída.

- Native Metal piecewise export
- Checklist automático vs corpus Banuba
- Swap Banuba → nativo produção
