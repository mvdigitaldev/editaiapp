# Sprint 38 — Export tiled piecewise + inpaint GPU + rollout

## Objetivo

Fechar o gap de **produção** do Face Warp V3: export tiled com shader
piecewise-affine, inpaint na GPU para preview 60fps, checklist A/B no lab e
rollout remoto gradual.

## Entregas

### Trilha A — Export tiled piecewise

| Item | Arquivo |
|------|---------|
| Tile origin no backend mesh | `warp/fragment_program_face_mesh_backend.dart` |
| Orquestrador export facial GPU | `warp/face_mesh_export_warp.dart` |
| Integração tiled export | `performance/tiled_export_engine.dart` |

Fluxo export >8MP:

```
tile expandido + halo
  → FaceMeshExportWarp (piecewise + tileOrigin)
  → inpaint opcional por tile
  → pós-warp pele/cor
```

Fallback: `ExportWarp` com grade CPU quando GPU indisponível.

### Trilha B — Inpaint GPU

| Item | Arquivo |
|------|---------|
| Máscara fantasma RGBA8 | `warp/face_warp_ghost_mask.dart` |
| Shader inpaint | `shaders/face_warp_inpaint.frag` |
| Backend FragmentProgram | `warp/fragment_program_face_inpaint_backend.dart` |
| Flag `useGpuInpaint` | `config/face_warp_v3_config.dart` |
| Preview PassWarp GPU-first | `rendering/pass_warp.dart` |

### Trilha C — QA + rollout

| Item | Arquivo |
|------|---------|
| Engine checklist B3–B6 | `quality/parity_checklist_engine.dart` |
| Painel lab | `presentation/widgets/parity_checklist_panel.dart` |
| Rollout remoto V3 | `config/face_warp_v3_rollout.dart` |
| Provider Riverpod | `di/face_warp_v3_rollout_provider.dart` |
| Toggle lab inpaint GPU | `presentation/beauty_editor_page.dart` |

Chaves Supabase `app_settings`:

| Chave | Valores |
|-------|---------|
| `face_warp_v3_enabled` | `enable` \| `disable` |
| `face_warp_v3_gpu_percent` | 0–100 |
| `face_warp_v3_inpaint_percent` | 0–100 |

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_v3_sprint38_test.dart
flutter test test/beauty_engine/warp/
```

## Critério de saída

- [ ] Export tiled usa piecewise quando `useGpuPiecewiseAffine`
- [ ] Preview inpaint GPU com fallback CPU
- [ ] Lab: painel paridade B3–B6 + toggle speed (inpaint GPU)
- [ ] Rollout remoto aplica flags fora de debug
- [ ] Testes Sprint 38 verdes

## Próximo (Sprint 39+)

- Native Metal piecewise (MethodChannel export)
- Checklist automático vs corpus golden Banuba
- Swap Banuba → nativo em produção (rollout %)
