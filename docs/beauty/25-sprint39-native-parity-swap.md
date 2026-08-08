# Sprint 39 — Native Metal export + paridade automática + swap produção

## Objetivo

Fechar o caminho de export nativo piecewise-affine, automatizar checklist de paridade contra corpus golden, e habilitar swap Banuba → editor nativo em produção com gate Face Warp V3.

## Trilha A — Native Metal piecewise (export)

| Artefato | Descrição |
|----------|-----------|
| `native_face_mesh_payload.dart` | Empacota atlas GPU para MethodChannel |
| `face_mesh_native_export_backend.dart` | Contrato Dart |
| `method_channel_native_face_mesh_backend.dart` | Canal `faceMeshWarpExport` |
| `FaceMeshMetalBackend.swift` | Shader Metal espelhando `face_mesh_piecewise.frag` |
| `FaceMeshGlesBackend.kt` | Stub Android (fallback FragmentProgram) |
| `face_mesh_export_warp.dart` | Native → FragmentProgram fallback |

**Flag:** `FaceWarpV3Config.useNativePiecewiseExport` (debug ON; produção segue rollout GPU V3).

**Probe:** `probeExportCapabilities` retorna `faceMeshMetal` / `faceMeshGles`.

## Trilha B — Checklist automático vs golden

| Artefato | Descrição |
|----------|-----------|
| `parity_golden_baseline.dart` | Faixas B3–B6 (jaw, chin, eye_scale, lip_thickness) |
| `parity_auto_evaluator.dart` | Compara `FaceWarpDebugStats` vs baseline |
| `parity_checklist_engine.dart` | Merge heurística + golden no lab |

Painel lab (`ParityChecklistPanel`) exibe hint `golden ✓` ou alerta de fold/Δv baixo.

## Trilha C — Swap Banuba → nativo (produção)

| Mudança | Descrição |
|---------|-----------|
| `faceEditorNativeSwapProvider` | Exige `face_warp_v3_enabled` + bucket swap + bucket V3 |
| `FaceWarpV3Config.forceNativeEntryInLab` | Toggle lab para simular entry nativo em debug |
| `face_warp_v3_rollout_applied_provider` | `useNativePiecewiseExport` = GPU rollout |

Chaves Supabase existentes:
- `face_editor_native_swap_enabled` / `face_editor_native_rollout_percent`
- `face_warp_v3_enabled` / `face_warp_v3_gpu_percent`

## Lab toggles (AppBar)

- **Apple** — export Metal nativo ON/OFF
- **Swap** — força `/face-retouch` nativo em debug

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_v3_sprint39_test.dart
flutter test test/beauty_engine/warp/
```

## Critério de saída

- [ ] `faceMeshWarpExport` disponível no iOS (Metal)
- [ ] Export tiled tenta native antes de FragmentProgram
- [ ] Paridade B3–B6 com avaliação golden automática no lab
- [ ] Swap produção gated por V3 + rollout %
- [ ] Testes Sprint 39 verdes
