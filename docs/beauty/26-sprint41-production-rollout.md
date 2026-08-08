# Sprint 41 — Rollout V3 em produção

## Objetivo

Aplicar **todas** as flags Face Warp V3 fora de debug via Supabase `app_settings`,
com buckets independentes por sub-feature, telemetria de sessão e gate de swap
Banuba alinhado ao rollout master.

## Entregas

### Trilha A — Rollout remoto completo

| Chave | Descrição |
|-------|-----------|
| `face_warp_v3_enabled` | Master switch |
| `face_warp_v3_rollout_percent` | Bucket malha V3 (0–100) |
| `face_warp_v3_direct_percent` | Render direct (~2.5 px/célula) |
| `face_warp_v3_gpu_percent` | GPU piecewise-affine |
| `face_warp_v3_inpaint_percent` | Inpaint pós-warp (+ GPU inpaint) |
| `face_warp_v3_native_percent` | Export Metal nativo (requer GPU) |

| Artefato | Descrição |
|----------|-----------|
| `face_warp_v3_rollout.dart` | Chaves + `FaceWarpV3RolloutSnapshot` |
| `face_warp_v3_rollout_applier.dart` | Resolve bucket → aplica `FaceWarpV3Config` |
| `face_warp_v3_rollout_provider.dart` | Providers remoto + snapshot + apply |
| Migration | `20260807193000_face_warp_v3_sprint41_rollout.sql` |

### Trilha B — Entry + telemetria

| Item | Descrição |
|------|-----------|
| `FaceRetouchEntryPage` | Aguarda rollout V3 antes do swap Banuba/nativo |
| `faceEditorNativeSwapProvider` | Usa `face_warp_v3_rollout_percent` (não mais 100 fixo) |
| `BeautyEditorPage` | `editor_open` com metadata V3 (`v3_bucket`, flags) |

## Rollout gradual sugerido

```sql
-- 1) Master V3 + mesh only (MLS fallback GPU off)
update app_settings set setting_value = 'enable'
  where setting_key = 'face_warp_v3_enabled';
update app_settings set setting_value = '10'
  where setting_key = 'face_warp_v3_rollout_percent';

-- 2) Direct + GPU
update app_settings set setting_value = '25'
  where setting_key in ('face_warp_v3_rollout_percent', 'face_warp_v3_direct_percent');
update app_settings set setting_value = '25'
  where setting_key = 'face_warp_v3_gpu_percent';

-- 3) Inpaint + native export iOS
update app_settings set setting_value = '50'
  where setting_key = 'face_warp_v3_inpaint_percent';
update app_settings set setting_value = '50'
  where setting_key = 'face_warp_v3_native_percent';

-- 4) Swap Banuba → nativo (após paridade lab)
update app_settings set setting_value = 'enable'
  where setting_key = 'face_editor_native_swap_enabled';
update app_settings set setting_value = '10'
  where setting_key = 'face_editor_native_rollout_percent';
```

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_v3_sprint41_test.dart
flutter test test/beauty_engine/warp/
```

## Critério de saída

- [ ] Produção aplica todas as flags V3 via applier (não só mesh/gpu/inpaint)
- [ ] Swap nativo respeita `face_warp_v3_rollout_percent`
- [ ] Entry `/face-retouch` aguarda rollout antes de abrir editor
- [ ] Telemetria `editor_open` inclui bucket + flags V3
- [ ] Testes Sprint 41 verdes
