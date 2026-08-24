# Face Slim Sprint A — FaceSlimField

Field isolado. Sem RGBA, sem renderer, sem preview, sem export, sem controller. Jaw, Chin e a infra V2 não foram alterados.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md), [`v2-face-slim-plan.md`](./v2-face-slim-plan.md).

```
FaceSlimField.build(face:, imageSize:, t:) → DisplacementField
```

`t` em `[0, 1]`. t=0 → campo zero. Sem `BackwardBilinearWarp` neste módulo.

## O que foi feito

Módulo `warp/v2/face_slim/` no template obrigatório:

- `face_slim_field.dart` — só **Δx** (dy = 0). Direcção: midline (`src = dest − d`).
- `face_slim_masks.dart` — união de dois hulls de bochecha, `slimActive`, protecções. Reutiliza só `RegionMaskRaster`. Não altera a classe `RegionMasks`.
- `face_slim_metrics.dart` — métricas próprias. Não altera `FieldMetrics`.

Handles / hull são constantes **deste módulo**:

- candidatos iniciais: `{123, 352}`
- primários vigentes: `{123, 411}` — 352 cai no disco da orelha em p01; 411 é bochecha direita e ficou activo nas três fotos
- secundários: resto das bochechas, incluindo 352; sem IDs Jaw/Chin
- hull: união `leftCheek` ∪ `rightCheek` (dois convex hulls, não o hull único do par)
- domínio Jaw hard-zero (constantes locais): `{58, 288, 132, 361}` + `{172, 136, 365, 397}`
- domínio Chin hard-zero (constantes locais): `{152, 148, 176, 149, 377, 400, 378}`

Amplitude: `t * 0.04 * faceWidth`. Kernel próprio: lóbulos Lorentzianos anisotrópicos + união probabilística + rampa lateral (zona morta na midline) + rampa de fronteira por camadas de erosão. Sem helpers de `jaw_field.dart` / `chin_field.dart`. Sem chamfer copiado.

Métrica de produto: `slimWidthBefore` / `slimWidthAfter` / `faceSlimNarrows` nos primários vigentes.

Limiar de Δ largura calibrado nesta sprint (só geometria): mínimo observado **10.7 px** (p01) a t=0.5. Não é sign-off visual.

## Gates

| Gate | Resultado |
|---|---|
| t=0 campo zero | passou nas 3 fotos |
| t=0.5 `faceSlimNarrows` | passou |
| `|dx|` nos primários > 40% de `influenceMax` | passou |
| dy = 0 em todo o campo | passou |
| `|d|` em 58, 288 e 152 = 0 | passou |
| protecções p95 = 0 | passou |
| `outsideSlimZoneP95` = 0 | passou |
| `minDetJ > 0` | passou |
| isolamento de imports | passou |
| testes Jaw / Chin / renderer / lab inalterados | passaram |

Percepção visual oficial: **não avaliada**. Continua nas Sprints B (`v2Raw`) e C.

## Métricas t=0.5

| Foto | slimAmplitude | influenceMax | dx@123 | dx@411 | Δ largura | \|d\| 58/288/152 | minDetJ | protect p95 |
|---|---|---|---|---|---|---|---|---|
| p01 | 7.58 | 7.58 | +7.58 | −3.12 | **10.70** | 0 | 0.370 | 0 |
| p05 | 5.75 | 5.75 | +5.75 | −5.75 | **11.49** | 0 | 0.341 | 0 |
| p12 | 6.51 | 6.51 | +6.51 | −6.51 | **13.02** | 0 | 0.277 | 0 |

`maxNeighborJump` ≤ 0.73. JSON: `.cursor/facial-warp-v2/face-slim/A/{real-p01,real-p05,real-p12}/metrics.json`

Em p01 o direito é mais fraco (411 mais perto da fronteira / orelha) mas ainda acima de 40% de `influenceMax`.

## Isolamento

O módulo não importa renderer, controller, UI, `extended_roi`, MLS, Telea, `jaw_field.dart`, `chin_field.dart` nem `sourceRgba`. Catálogo partilhado só **lido** (oval, olhos, lábios, orelhas). Nenhum conjunto Face Slim foi acrescentado a `region_catalog.dart`.

`rm -rf warp/v2/face_slim` + apagar testes/relatórios Face Slim. Diff esperado: renderer / controller / Jaw / Chin / infra = vazio.

## Testes

`flutter test test/beauty_engine/warp/v2/`

**34/34 passaram.** Inclui os 3 casos novos em `facial_warp_v2_face_slim_field_test.dart`. Contratos Jaw / Chin / renderer / displacement / lab / Device Lab sem mudança de expectativa.

## Arquivos

**Criados**

- `lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_field.dart`
- `lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_masks.dart`
- `lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_metrics.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_face_slim_field_test.dart`
- `docs/beauty/v2-face-slim-plan.md` (spec congelada)
- `docs/beauty/v2-face-slim-a-report.md` (este relatório)
- `.cursor/facial-warp-v2/face-slim/A/` — métricas t=0.5

**Modificados**

- `docs/beauty/FacialWarpV2-Development-Rules.md` — regra geral: nenhum Field depende de outro Field V2 (secção 3). Não é código de efeito.

**Não alterados (diff vazio)**

`BackwardBilinearWarp`, `DisplacementField`, `JawField`, módulo `chin/`, `RegionMasks`, `FieldMetrics`, `region_catalog.dart`, controller, preview, export, UI, Device Lab, Body, Skin, Color. Testes de contrato V2 existentes.

## Observações técnicas

- 123/352 não foram congelados. 352 sobrepõe o disco da orelha em p01; a redefinição ficou em `{123, 411}` só neste módulo.
- O kernel não reutiliza o gaussiano+chamfer do Jaw/Chin. A rampa de fronteira é por camadas de erosão (`_onionFade`), necessária para `minDetJ > 0` (corte seco na máscara dobrava o campo).
- A Sprint A não produz `v2Raw`. Δ largura ~11–13 px é evidência geométrica, não percepção renderizada.

## Sprint B

**Não iniciada.** Sem RGBA, sem `v2Raw`, sem lab. A B só depois de aprovação explícita desta A.
