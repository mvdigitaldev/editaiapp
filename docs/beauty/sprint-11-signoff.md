# Sprint 11 — Nose Slim

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| NoseSlimFilter | `filters/face/nose_slim.dart` | ✅ |
| NoseLengthFilter | `filters/face/nose_length.dart` | ✅ |
| NoseHeightFilter | `filters/face/nose_height.dart` | ✅ |
| NoseTipFilter | `filters/face/nose_tip.dart` | ✅ |
| NoseBridgeFilter | `filters/face/nose_bridge.dart` | ✅ |
| FaceParams estendido | `models/face_params.dart` | ✅ |

## Critérios de aceite

- [x] Sliders independentes e combináveis via `FaceFilterPipeline`
- [x] Nariz permanece centrado (deslocamentos em torno do eixo nasal)
- [x] Bridge usa subset separado (não arrasta ponta/laterais baixos)

## Testes

- `test/beauty_engine/filters/face_filter_pipeline_test.dart` — 7 testes

## Próximo passo

**Sprint 12 — Eyes**
