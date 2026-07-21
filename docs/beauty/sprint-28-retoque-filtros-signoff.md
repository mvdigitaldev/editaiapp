# Sprint 28 — Separar Retoque e Filtros

**Status:** Concluído  
**Data:** 2026-07-21

## Objetivo

Corrigir UX confusa que misturava presets 1-toque com retoque manual. Retoque beauty passa a ser ajustes manuais; presets viram filtros LUT+cor (Lightroom) no editor manual.

## Entregas

- [x] `BeautyAdjustmentsPanel` — barra Ajustes (rosto/nariz/olhos/boca/corpo/pele)
- [x] `BeautyEditorPage` — sem strip de presets; preview por overrides
- [x] `PresetCreatorPage` — apenas LUT + tune; salva warp zerado
- [x] Módulo `filter_presets/` — ponte neutra manual ↔ beauty
- [x] `ManualEditorPage` — filtros bundled + user no `filterList`
- [x] Marketplace/perfil — copy "filtros"; install invalida `filterPresetsProvider`
- [x] Testes: `beauty_adjustments_panel_test`, `filter_preset_mapper_test`

## Compatibilidade

- JSON `BeautyPreset` e Supabase inalterados
- Presets legados com warp: ignorados ao converter para filtro manual
- Retoque na nuvem (`beauty_edit`) permanece follow-up

## Critérios de aceite

- [x] Retoque beauty mostra Ajustes, não presets
- [x] Criar filtro / marketplace orientam editor manual
- [x] `flutter test` suite beauty + novos testes passando
