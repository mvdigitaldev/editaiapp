# P0 — Baseline reproduzível (Extended ROI)

**Data:** 21 de agosto de 2026  
**Estado:** auditoria concluída. Nenhum morph, warp, fill, amplitude ou flag de produção foi alterado para “corrigir” a imagem. P1 não foi iniciado.

## O que foi medido

Caminho `ExtendedRoiPipeline.compose` + `render` (o mesmo `roiOnly` do editor quando só `jaw`/`chin`/`v_face` estão activos). Harness em `extended_roi_preview_grid_test.dart`.

| Fixture | Ficheiro | Tamanho | Landmarks |
|---|---|---|---|
| p01 | `test/beauty_engine/warp/fixtures/phase12/p01-man-5021469.png` | 695×1024 | cache real |
| p05 | `test/beauty_engine/warp/fixtures/phase12/p05-young-woman.png` | 740×740 | cache real |
| p12 | `test/beauty_engine/warp/fixtures/phase12/p12.jpg` | 960×1440 | cache real |

Ausentes: nenhum dos três.

Matriz: `jaw`, `chin`, `v_face`, `jaw_chin` × 0 / 25 / 50 / 75 / 100% = **60 casos**, mais medição preview vs export em p01 jaw 50%.

Dumps (relativos, sem path absoluto de máquina):

`.cursor/extended-roi/p0/<fixture>/<scenario>/<intensity>/`

Cada pasta tem `original.png`, `rawWarp.png`, `finalOutput.png`, diffs amplificados, máscaras, `metrics.json`, `log.txt`. Parsing ausente → `faceParsingMask.ABSENT.txt`.

## Rota e parâmetros efectivos

| Intensidade | `SilhouetteRouting.decide` | Pipeline |
|---|---|---|
| 0% | `identity` | compose corre, `payload.isIdentity=true`, RGBA = original |
| 25–100% (só silhueta) | `roiOnly` | morph ROI + `BackwardWarp2D` + fill |

Slider → `easeOutCubic(raw) * amplitudeScale(0.5)`:

| raw | t efectivo |
|---|---|
| 0.00 | 0.000 |
| 0.25 | 0.289 |
| 0.50 | 0.438 |
| 0.75 | 0.492 |
| 1.00 | 0.500 |

Isolamento confirmado:

- `jaw` isolado: `chinLift=0`, `dy` da grelha = 0, gônio move em Δx, chinTip/olhos/boca/nariz/orelhas = 0 no campo.
- `chin` isolado: `jawAmp=0`, `dx` da grelha = 0, chinTip e pescoço sobem (coupling 1.0).
- `v_face` e `jaw_chin`: soma jaw Δx + chin Δy.

`face_slim` permanece 0. `faceSlimUsesRoi=false`. Experimentos (personTransport, composer, Phase9Local) OFF.

## Hashes

No mesmo caso, `frameAudit` e `total_ms` partilham o mesmo `inputHash`. Em 0%, `inputHash = rawWarpHash = finalOutputHash`. Auditoria ligada vs desligada: RGBA idêntico (teste dedicado).

p01 jaw 50% preview vs export: **mesmo** `finalOutputHash` (`5580e606c837f9e2`), grelha 80×100 em ambos.

## Diffs (números-chave)

p01, t=50%:

| Cenário | original→raw px | raw→final px | raw RGB p95 | final RGB p95 | ghost raw | ghost final |
|---|---:|---:|---:|---:|---:|---:|
| jaw | 20662 | 6093 | 32 | 101 | 0.986 | 0.977 |
| chin | 40798 | 18788 | 129 | 46 | 0.709 | 0.454 |
| v_face | 59296 | 18501 | 34 | 68 | 0.800 | 0.758 |
| jaw_chin | 58345 | 19413 | 66 | 71 | 0.779 | 0.595 |

Jaw: o fill **aumenta** o pico de erro RGB (p95 32→101, max 187) e **não** reduz o ghost (~0.98). Chin: o fill **reduz** ghost (0.71→0.45) e o p95.

p05/p12 repetem o padrão jaw (released por preencher) vs chin (Telea em holes reais).

## Campo

Jaw t=50% p01: `jawAmp≈9.95 px` (Δx only), `supportPx=966/8000`, `minDetJ≈0.30`, fold=0. Âncoras protegidas a 0. Gônios ≈±9.8 px.

Chin t=50% p01: `chinLift≈17.4 px`, chinTip `dy≈-17.3`, **pescoço `dy≈-17.4` (coupling 1.0)**. Olhos/boca/nariz/gônio a 0.

`outsideJawZonePx` no overlay (banda Y, não anatomia) ≈5335 em p01 jaw — o heatmap de |delta| não é o domínio mandibular.

## Warp

Jaw p01 t=50%: `coveragePx=18628`, `holePx=0`, `pullOntoPersonPx=32` (reconstrução da política, não um contador no renderer), `blendWithOriginalPx=0`, `rejectedPersonMaskPx=13341`, `rejectedInvalidSourcePx=6961`. ~3590 px mudam **fora** da região com |campo|>0.25.

Chin p01 t=50%: `pullOntoPersonPx≈1923`, `blendWithOriginalPx=242`, Telea 1192 px.

`rawWarp` já inclui o `SilhouetteRingAa` chamado **dentro** de `BackwardWarp2D.apply` quando há `contourMasks`. Não é o splat cru.

## Reconstrução

Jaw: `releasedOriginalPx = releasedUnfilledPx` (3139 em p01 t=50%). `fillFromBackgroundPx=0`. Telea=0. A banda libertada **não é preenchida**. ContourBandFill escreve abandoned (pele/vizinho), não released.

Chin: released=0; Telea preenche holes reais; ghost desce.

## Performance

Preview p50 aparente ~300–550 ms (compose ~10 ms, warp ~400 ms, fill ~30–50 ms) nestas fotos, grelha 80×100, sem fallback 64×80 no harness (budget reset por caso).

## Testes

Comando:

```bash
flutter test test/beauty_engine/warp/extended_roi/extended_roi_preview_grid_test.dart
```

Resultado: **15 passou, 1 falhou**.

P0 (todos passaram):

- auditoria não muda RGBA
- identidade 0%
- `inputHash` coerente entre `frameAudit` e `total_ms`
- matriz 60 casos + export
- dumps sem path `/Users/...`

Falha pré-existente / limiar apertado, **não ajustada** (P0 não altera matemática):

- `p01 chin+jaw`: ghost proxy 0.5907 > limiar 0.58 do teste antigo. Não é evidência de regressão visual introduzida pela auditoria; o proxy já estava no bordo. Não subi o limiar.

## Limitações

- Person mask do harness é **sintético** (oval + banda de pescoço), não o Selfie Segmenter do editor.
- Face parsing **ausente** (`parsingEmpty=true`). Não tratar isto como protecção de orelha/cabelo comprovada.
- `hashBytes` é FNV subamostrado (hex pode parecer “negativo”).
- Ghost SSIM/gradiente ≠ smear visual. Jaw ghost ~0.98 no raw já mostra o problema antes do fill.
- Dumps em `.cursor/` estão no `.gitignore`.

## Ficheiros alterados

- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_frame_audit.dart`
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_p0_dump.dart` (novo)
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_pipeline.dart` (cópias/hashes/identidade; RGBA de produto inalterado)
- `lib/features/editor/beauty_engine/warp/extended_roi/extended_roi_payload.dart` (campos de telemetria)
- `lib/features/editor/beauty_engine/warp/extended_roi/silhouette_routing.dart` (`snapshotEffective`, `decide` intacto)
- `lib/features/editor/beauty_engine/controllers/beauty_engine_controller.dart` (`lastEffectiveWarpParameters`)
- `test/beauty_engine/warp/extended_roi/extended_roi_preview_grid_test.dart`
- `docs/beauty/p0-baseline-report.md`
- `docs/beauty/p0-baseline-report.json`

Não alterados: `JawNarrowMorph`, `ChinShorteningMorph`, `ArtisticMorphLibrary`, `DenseGrid2D`, `BackwardWarp2D`, `ContourMasks`, `ContourBandFill`, `HoleFillInpaint`, `PassWarp`, `amplitudeScale`, `useExtendedRoi`.

## Decisão recomendada (aguardar aprovação)

Não começar P1 automaticamente. Com base nos diffs numéricos e nos PNGs:

1. **Jaw — o raw já está errado e o final não reconstitui a borda.** Ghost ~0.98 no `rawWarp`; released 100% unfilled; fill sobe o pico RGB. Isso aponta a **P2 (renderer)** e **P3 (reconstrução por classe)** para mandíbula, não a subir amplitude.
2. **Chin — o campo acopla o pescoço 1:1** (`neck_dy ≈ chinTip_dy`). Isso é o contrato P1.1 (jaw-only vs jaw–neck / chin–neck), separado da borda do jaw.
3. Âncoras faciais protegidas (olhos/boca/nariz) estão a 0 no campo; o vazamento visível do jaw está na **silhueta/released**, não em mover a boca.

Leitura sugerida dos PNGs antes de escolher a fase:

- `.cursor/extended-roi/p0/p01/jaw/50/diff_original_to_raw.png`
- `.cursor/extended-roi/p0/p01/jaw/50/diff_raw_to_final.png`
- o mesmo em `chin/50` e `jaw_chin/50`
- p05 e p12 equivalentes

Se a inspecção humana confirmar smear já no raw do jaw → P2 em paralelo com P3. Se o raw do jaw parecer geometricamente correcto e só o buraco da mandíbula falhar → P3 primeiro. P1 continua necessário para o coupling de pescoço do chin e para tornar jaw-only explícito, mas **não** é o único gargalo visível.
