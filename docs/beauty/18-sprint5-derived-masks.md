# Sprint 5 — Máscaras derivadas e Grupo C

Entrega da Fase 3b: máscaras semânticas derivadas do face parsing,
calibração por tom de pele, ferramentas do Grupo C e amostragem pós-warp.

## Escopo entregue

### Máscaras derivadas (cap. 2.3)

| Máscara | Regra |
|---------|--------|
| **Dentes** | inner mouth ∩ parsing (boca/lábios) ∩ OKLab (L alto, croma baixa) |
| **Olheiras v2** | landmark sob olho ∩ máscara de pele |
| **Brilho/oleosidade** | pele ∩ highlight acima do joelho relativo ao tom |
| **Mandíbula** | banda de contorno (contourRegions) |
| **Íris** | elipse dentro da região ocular |
| **Sobrancelhas** | parsing brow + landmarks |

Arquivos:
- `lib/features/editor/beauty_engine/filters/face/derived_masks.dart`
- `lib/features/editor/beauty_engine/filters/face/skin_tone_calibration.dart`
- `lib/features/editor/beauty_engine/filters/face/mask_sampling.dart`

### Calibração por tom (cap. 16)

- `SkinToneCalibration.sample()` — OKLab + luma linear da bochecha
- Thresholds relativos: `shineKnee`, `teethMinOklabL`, `teethMaxChroma`
- Integrado em `SkinRetouchEngine` (brilho) e máscara de dentes

### Amostragem pós-warp (Sprint 5)

- `WarpField.sourceNormalizedForMask()` — remapeia pixel pós-warp → coordenada anatômica
- `MaskSamplingContext` — usado ao rasterizar máscaras derivadas
- `faceWarp` passado pelo pipeline quando warp facial ativo (preview/export/tiled)

### Grupo C — ferramentas

- **Clarear dentes** — usa `DerivedMaskBundle.teeth` (substitui loop paramétrico)
- **Olheiras** — `DerivedMaskBundle.underEye` (v2)
- **Brilho** — `DerivedMaskBundle.shine` + joelho calibrado
- **Sobrancelhas / contorno** — parsing + jaw band
- **Realce de íris** — novo parâmetro `iris_enhance`

Gating:
- Dentes: boca fechada (`gate_mouth_closed`) + oclusão
- Íris: oclusão + yaw (`ToolGateEngine`)

### Integração

- `PassSkinEngine` — constrói `DerivedMaskBundle` 1× por pass
- `SkinFilterPipeline` — `iris_enhance`, uniform `faceWarp`
- Controller + tiled export propagam `faceWarp`

## Testes

- `test/beauty_engine/filters/skin/derived_masks_test.dart`
- Testes existentes Grupo A permanecem verdes

## Critério de saída

| Meta | Status |
|------|--------|
| Máscaras derivadas (dentes, olheiras, brilho, mandíbula) | ✅ |
| Calibração por tom amostrado | ✅ |
| Amostragem pós-warp | ✅ |
| `iris_enhance` + gating Grupo C | ✅ |
| Golden Grupo C vs Banuba | ⏳ (corpus A/B manual) |

Próximo: **Sprint 6** — FFI hot path, MLS em isolate, Device Capability Manager.
