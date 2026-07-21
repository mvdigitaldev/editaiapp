# Sprint 08 — Sign-off

**Sprint:** 08 — Sistema de Presets (models)  
**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| BeautyPreset + params JSON | `models/beauty_preset.dart`, `*_params.dart` | ✅ |
| Presets bundled (Natural, Beauty, Cinema) | `presets/bundled_presets.dart` | ✅ |
| Persistencia JSON local | `presets/beauty_preset_local_store.dart` | ✅ |
| BeautyPresetRepository impl | `presets/beauty_preset_repository_impl.dart` | ✅ |
| Import/export JSON | `BeautyPresetRepository` | ✅ |
| Provider Riverpod | `di/beauty_engine_providers.dart` | ✅ |
| Unit tests | `test/beauty_engine/presets/` | ✅ |

## Critérios de aceite

- [x] Round-trip JSON encode/decode (models + repository)
- [x] 3 presets factory bundled (Natural, Beauty, Cinema)
- [x] Campo `version` em `BeautyPreset`
- [x] CRUD local: list / save / delete presets do usuario

## Notas

- Persistencia em arquivo JSON (`user_presets.json`) via `path_provider`; Hive permanece disponivel no projeto para evolucao (Sprint 23 sync).
- LUT assets referenciados nos presets bundled serao wired na Sprint 09 (`assets/filters/lut/`).
- Presets bundled sao read-only (`bundled_*` ids).

## Testes

```
flutter test test/beauty_engine/
```

## Próximo passo

**Sprint 10 — Face Slim**
