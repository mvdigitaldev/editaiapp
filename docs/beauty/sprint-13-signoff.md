# Sprint 13 — Jaw + Chin

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| JawFilter | `filters/face/jaw.dart` | ✅ |
| ChinFilter | `filters/face/chin.dart` | ✅ |
| FaceParams `jaw` | `models/face_params.dart` | ✅ |

## Critérios de aceite

- [x] Chin shrink independente de face_slim (subset `{175, 199, 200, 18, 313, 421, 428}`)
- [x] Jaw usa índices disjuntos de `MeshRegion.jawLeft/jawRight` (face_slim / v_face)

## Testes

- `test/beauty_engine/filters/face_filter_pipeline_test.dart` — grupo Sprint 13

## Próximo passo

**Sprint 14 — Cheekbone**
