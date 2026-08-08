# Sprint 4 — Face parsing e MaskFactory

Entrega da Fase 3a do SDK facial: arquitetura de parsing 19 classes
(CelebAMask/BiSeNet), `MaskFactory` com feather + cache R8, e integração
no pipeline de pele substituindo máscaras geométricas puras.

## Escopo entregue

### Face parsing 19 classes

- `FaceParsingClass` — enum compatível com CelebAMask-HQ / BiSeNet
- `FaceParsingResult` — máscara categórica R8 + `FaceParsingSource`
- `FaceParsingMapper` — converte multiclass MediaPipe (6) + landmarks → 19 classes
- `ParsingFallbackPolicy` — escolhe BiSeNet / multiclass / geométrico
- `FaceParsingDetector` — bridge BiSeNet (stub `null`) + mapper Dart

Arquivos:
- `lib/features/editor/beauty_engine/segment/face_parsing_*.dart`
- `lib/features/editor/beauty_engine/segment/parsing_*.dart`

### MaskFactory (cap. 2.3)

- `MaskFactory.buildSkin()` — pele com proteção olhos/boca/sobrancelhas (A1)
- `MaskFactory.buildRegionMask()` — regiões arbitrárias (cabelo, etc.)
- `ParsingMaskCache` — LRU de máscaras R8 por tile/região
- `SkinWeightMap.build(parsing:)` — roteia para MaskFactory quando parsing disponível

Arquivos:
- `lib/features/editor/beauty_engine/filters/face/mask_factory.dart`
- `lib/features/editor/beauty_engine/segment/parsing_mask_cache.dart`

### Bridge BiSeNet (backlog explícito)

- `detectFaceParsing` no MethodChannel — retorna `null` até o modelo TFLite/CoreML
  estar no asset e nos bridges nativos
- Quando disponível, preenche `FaceParsingResult` com `source: bisenet`

Arquivos:
- `packages/beauty_mediapipe/lib/src/beauty_mediapipe_bindings.dart`
- Android/iOS plugins (`detectFaceParsing` → `null`)

### Integração pipeline

- `BeautyEngineController.detectFaceParsing()` + `lastFaceParsing`
- Preview/export/tiled passam `faceParsing` ao `SkinFilterPipeline` / `PassSkinEngine`
- `maskFactory.clearCache()` no `invalidateRenderStageCache()`

## Testes

- `test/beauty_engine/filters/skin/mask_factory_test.dart`
  - IoU pele ≥ 0.90 vs máscara legada multiclass
  - IoU cabelo ≥ 0.85 vs segmentação sintética
  - Invariante A1 (olhos/boca zerados)

## Critério de saída

| Meta | Status |
|------|--------|
| Arquitetura 19 classes + mapper | ✅ |
| MaskFactory + cache R8 | ✅ |
| Pipeline de pele usa parsing | ✅ |
| Fallback geométrico quando confiança baixa | ✅ |
| Bridge BiSeNet preparado (stub) | ✅ |
| IoU skin ≥ 0.90 / hair ≥ 0.85 (sintético) | ✅ |
| IoU em corpus anotado 15–20 fotos | ⏳ (requer BiSeNet + dataset) |
| Latência parsing ≤ 80 ms | ⏳ (requer modelo nativo) |

Próximo: **Sprint 6** — FFI hot path e tempo real.
