# Sprint Fase 1 — Manual Editor

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| pro_image_editor + flutter_image_filters | `pubspec.yaml` | ✅ |
| Módulo manual_editor | `lib/features/editor/manual_editor/` | ✅ |
| ExportPipeline + LutFilterProcessor | `manual_editor/data/` | ✅ |
| Filter presets (30+ via presetFiltersList) | `filter_presets.dart` | ✅ |
| ManualEditorPage + Entry | `manual_editor/presentation/` | ✅ |
| Edge Function salvar-edicao-manual | `supabase/functions/` | ✅ |
| Migration manual_edit (0 créditos) | `supabase/migrations/` | ✅ |
| Rota /manual-editor + card Home | `main.dart`, `home_page.dart` | ✅ |
| operation_type manual_edit | `operation_type.dart` | ✅ |
| Comparison + galeria | `comparison_page`, `edit_detail_page` | ✅ |

## Fluxo

1. Home → **Editar manualmente**
2. Selecionar foto → `ManualEditorPage` (ajustes, crop, filtros)
3. Concluir → `salvar-edicao-manual` (automático, 0 créditos)
4. `/comparison` com slider before/after + download

## Critérios de aceite

- [x] LUTs + tune + crop/rotação via pro_image_editor
- [x] Export pipeline + persistência Supabase (`manual_edit`)
- [x] Respeita `max_stored_photos` do plano (limite unificado de armazenamento)
- [x] Sem import de `beauty_engine/` no manual_editor
- [x] Testes unitários export/filter presets

## Notas

- Edição manual: **0 créditos**; sem limite de quantas vezes edita, mas **salvar** consome slot de `max_stored_photos`.
- Fotos manuais entram na mesma contagem de armazenamento que edições IA.
- `pro_image_editor` 11.3.0 (compatível Flutter 3.38); upgrade para 12+ quando SDK ≥ 3.41.
- `flutter_image_filters` 0.0.28 (build conflict com versões mais novas + freezed).
- Assets LUT PNG dedicados entram na Sprint 09 (unificação LutEngine).

**Próximo passo**

**Sprint 10 — Face Slim** (Beauty Engine)
