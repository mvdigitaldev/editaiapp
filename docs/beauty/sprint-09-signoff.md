# Sprint 09 — LUT Engine

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| LutEngine unificado | `beauty_engine/presets/lut_engine.dart` | ✅ |
| LutSquareTable (CPU paridade shader) | `beauty_engine/presets/lut_square_table.dart` | ✅ |
| PassLut GPU pipeline | `beauty_engine/rendering/pass_lut.dart` | ✅ |
| Assets LUT PNG | `assets/filters/lut/` | ✅ |
| Intensity 0..1 | `BeautyPreset.lutIntensity` + uniforms | ✅ |
| Wiring controller | `beauty_engine_controller.dart` | ✅ |
| Manual ExportPipeline LUT | `manual_editor/data/export_pipeline.dart` | ✅ |
| Provider | `lutEngineProvider` | ✅ |
| Gerador de assets | `tool/generate_lut_assets.dart` | ✅ |

## Critérios de aceite

- [x] Paridade visual Manual vs Beauty (`LutEngine.applyToRgba` == `PassLut`, SSIM > 0.98)
- [x] Intensity slider 0..1 funcional (blend source ↔ LUT)
- [x] Assets `natural.png` e `cinema_teal_orange.png` wired nos bundled presets

## Testes

- `test/beauty_engine/presets/lut_engine_test.dart` — 5 testes (SSIM + intensity)
- **53 testes** passando em `test/beauty_engine/`

## Notas

- CPU path usa o mesmo algoritmo do `lookup.frag` (flutter_image_filters).
- `applyToJpegViaGpu` disponível para export de alta fidelidade (Impeller).
- Manual Editor continua com `pro_image_editor` na UI; LUT PNG compartilhado no export via `ExportPipeline`.

## Próximo passo

**Sprint 12 — Eyes**
