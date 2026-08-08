# Sprint 36 — Contorno/nariz V3 + render direct na malha

## Objetivo

Completar cobertura **22/22** ferramentas warp faciais no motor V3 (modo pilot)
e introduzir **render direct** — grade fina baricêntrica (~2.5 px/célula) sem
heurísticas de spread/vacancy, reduzindo fantasma e faixas na grade grossa.

## Entregas

### Trilha A — 12 filtros pilot restantes

| Grupo | Tools |
|-------|-------|
| Contorno/volume | `narrow_face`, `v_face`, `jaw`, `chin`, `cheekbone`, `forehead`, `temple`, `head_size` |
| Nariz | `nose_length`, `nose_height`, `nose_tip`, `nose_bridge` |

Arquivo: `warp/anatomy/pilot_warp_contour_nose.dart` — semântica espelhando filtros MLS legados.

Todos os 22 tools em `PilotWarpDisplacement.pilotToolKeys` → `DeformationMode.pilot`.

### Trilha B — Render direct (Sprint 36)

| Item | Arquivo |
|------|---------|
| Grade fina 120–256 (`~2.5 px/célula`) | `warp/warp_field_builder.dart` → `forFaceMeshV3Direct` |
| Sem spread/vacancy/smooth heurístico | `warp/face_mesh_warp_rasterizer.dart` (`directMesh: true`) |
| Flag `useDirectMeshRender` | `config/face_warp_v3_config.dart` |
| Toggle lab (ícone texture) | `presentation/beauty_editor_page.dart` |
| Cache key `useDirectMeshRender` | `rendering/render_stage_cache.dart` |
| Backend debug `v3_direct` | `controllers/beauty_engine_controller.dart` |

### Trilha C — Vacancy fill contorno

`face_warp_vacancy_fill.dart` — lateral tools estendidos: `face_slim`, `narrow_face`, `v_face`, `jaw`, `temple`.

### Rollback MLS

`FaceWarpV3Config.useLegacyFaceMls` — força path MLS no controller (rollback).

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_v3_contour_nose_test.dart
flutter test test/golden/face_warp_v3_contour_nose_golden_test.dart
flutter test test/beauty_engine/warp/
```

Regenerar goldens:

```bash
UPDATE_GOLDENS=1 flutter test test/golden/face_warp_v3_contour_nose_golden_test.dart
```

## Critério de saída

- [ ] 22/22 tools em modo pilot
- [ ] Goldens contorno/nariz verdes
- [ ] Lab: toggle direct mesh + badge `v3_direct`
- [ ] Ajustes finos de qualidade — ver Sprint 37 (inpainting GPU nativo pendente export tiled)

## Sprint 37 (concluída)

Ver [`23-sprint37-gpu-inpaint.md`](23-sprint37-gpu-inpaint.md) — GPU piecewise-affine + inpaint pós-warp.

## Próximo (Sprint 38+)

- Export tiled com shader piecewise
- Inpaint GPU nativo para preview 60fps
- Paridade Banuba checklist A/B completa
