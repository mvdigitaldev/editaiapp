# Sprint 17 — Skin Engine

**Status:** ✅ Concluída  
**Data:** 2026-07-20

## Entregáveis

| Item | Local | Status |
|------|-------|--------|
| SkinMaskUtils | `filters/face/skin_mask_utils.dart` | ✅ |
| SkinFilterPipeline | `filters/face/skin_filter_pipeline.dart` | ✅ |
| PassSkinEngine (CPU bilateral-like) | `rendering/pass_skin_engine.dart` | ✅ |
| SkinParams estendido | `models/skin_params.dart` | ✅ |

## Parâmetros

`skin_smooth`, `skin_whitening`, `remove_acne`, `remove_wrinkles`, `remove_dark_circles`, `teeth_whitening`, `blush`, `contour`, `eyebrows`, `eyelashes`

## Critérios de aceite

- [x] Skin smooth preserva bordas olhos/boca (máscara `protectedRegions`)
- [x] Makeup blend conservador (blush/contour/eyebrows/eyelashes)
- [x] Teeth whitening restrito à região interna da boca

## Testes

- `test/beauty_engine/filters/skin_filter_pipeline_test.dart`

## Próximo passo

**Sprint 21 — Beauty Presets bundled**
