# Sprint 29 — Filtros Lightroom, marketplace e UX

## Escopo entregue

### Fase 1 — UX e permissões
- **Home:** cards *Criar filtro custom* e *Marketplace de filtros* (quando beauty habilitado).
- **Criador:** banner de uso pessoal; nota admin-only quando `beauty_marketplace_publish_admin_only = enable`.
- **Editar manualmente (entrada):** chip para o marketplace.

### Fase 2 — Criador estilo Lightroom
- **`TuneParams` / `FilterTuneParams`:** grade completa (Luz, Cor, Efeito) com JSON retrocompatível.
- **`FilterGradeEngine`:** pipeline GPU via `flutter_image_filters` + LUT (`LutEngine` fallback CPU).
- **`PresetCreatorPage`:** seções LUT / Luz / Cor / Efeito; preview via `FilterGradeEngine` (sem MediaPipe).

### Fase 3 — Editor manual (fidelidade)
- **`filter_preset_mapper`:** preview identidade para presets EditAI (evita dupla aplicação).
- **`ManualEditorPage`:** `onFilterChanged` + reaplicação de grade completa no export via `FilterGradeEngine`.

### Fase 4 — Testes
- `test/filter_presets/filter_preset_mapper_test.dart` (atualizado)
- `test/filter_presets/filter_grade_engine_test.dart`

## Permissões (confirmado)

| Ação | Quem |
|------|------|
| Ver marketplace | Todos (beauty habilitado) |
| Instalar filtros | Todos |
| Criar filtro (uso pessoal) | Todos |
| Publicar no marketplace | Admin quando flag `enable` |

**Publicar ≠ criar.** Criação local/sync permanece disponível para todos.

## Flag Supabase

- `beauty_marketplace_publish_admin_only = enable` → toggle de publicação só para admin (`canPublishBeautyPresetProvider`).

## Limitações conhecidas

- Preview no editor manual usa matriz identidade; efeito EditAI visível após concluir (export com `FilterGradeEngine`).
- Nitidez/vinheta no fallback CPU usam aproximação por matriz; GPU usa shaders nativos quando disponível.

## Signoff

- [x] Home cards criador + marketplace
- [x] Banner uso pessoal no criador
- [x] Grade Lightroom no criador com preview GPU
- [x] Export fiel no editor manual
- [x] Testes unitários mapper + engine
