# Sprint 12 — Eyes

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| EyeScaleFilter | `filters/face/eye_scale.dart` | ✅ |
| EyeDistanceFilter | `filters/face/eye_distance.dart` | ✅ |
| EyeHeightFilter | `filters/face/eye_height.dart` | ✅ |
| EyeRotationFilter | `filters/face/eye_rotation.dart` | ✅ |
| DoubleEyelidFilter | `filters/face/double_eyelid.dart` | ✅ |
| PassEyeOverlay (shader CPU) | `rendering/pass_eye_overlay.dart` | ✅ |
| FaceParams estendido | `models/face_params.dart` | ✅ |
| Link Eyes toggle | `presentation/face_filters_demo_page.dart` | ✅ |

## Critérios de aceite

- [x] Simetria L/R preservada com link toggle (`link_eyes` / `linkEyes`)
- [x] Íris excluída do warp ocular (`irisLandmarkIndices`)
- [x] Double eyelid: warp pálpebra superior + overlay sombra (`PassEyeOverlay`)

## Testes

- `test/beauty_engine/filters/face_filter_pipeline_test.dart` — grupo Sprint 12

## Próximo passo

**Sprint 13 — Jaw + Chin**
