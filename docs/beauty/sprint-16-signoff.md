# Sprint 16 — Lips + Mouth

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| MouthWidthFilter | `filters/face/mouth_width.dart` | ✅ |
| LipThicknessFilter | `filters/face/lip_thickness.dart` | ✅ |
| SmileFilter | `filters/face/smile.dart` | ✅ |
| FaceParams `mouthWidth`, `smile` | `models/face_params.dart` | ✅ |

## Critérios de aceite

- [x] Smile ≤ 0.5 afeta só cantos — `innerMouthExcluded` protege dentes
- [x] Lip thickness usa contorno externo dos lábios

## Testes

- `test/beauty_engine/filters/face_filter_pipeline_test.dart` — grupo Sprint 16

## Próximo passo

**Sprint 17 — Skin Engine**
