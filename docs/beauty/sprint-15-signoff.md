# Sprint 15 — Forehead + Temple

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| ForeheadFilter | `filters/face/forehead.dart` | ✅ |
| TempleFilter | `filters/face/temple.dart` | ✅ |
| FaceParams `temple` | `models/face_params.dart` | ✅ |

## Critérios de aceite

- [x] Hairline respeitada — landmarks `{9, 10, 151, 337, 338}` excluídos do warp
- [x] Têmporas estreitadas lateralmente sem afetar hairline

## Testes

- `test/beauty_engine/filters/face_filter_pipeline_test.dart` — grupo Sprint 15

## Próximo passo

**Sprint 16 — Lips + Mouth**
