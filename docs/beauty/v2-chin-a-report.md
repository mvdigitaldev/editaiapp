# Chin Sprint A — ChinField

Field isolado. Sem RGBA, sem renderer, sem preview, sem export, sem controller. Jaw e a infra V2 não foram alterados.

Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md), [`v2-chin-plan.md`](./v2-chin-plan.md).

```
ChinField.build(face:, imageSize:, t:) → DisplacementField
```

`t` em `[0, 1]`. t=0 → campo zero. Sem `BackwardBilinearWarp` neste módulo.

## O que foi feito

Módulo `warp/v2/chin/` no template obrigatório:

- `chin_field.dart` — só **Δy** (dx = 0). Mentão sobe: `dy = −amplitude × peso`.
- `chin_masks.dart` — hull do mento, `chinActive`, protecções. Reutiliza só `RegionMaskRaster`. Não altera a classe `RegionMasks`.
- `chin_metrics.dart` — métricas próprias. Não altera `FieldMetrics`.

Handles / hull são constantes **deste módulo** (ajustáveis na A sem mudar arquitectura):

- primário inicial: `{152}`
- secundários: `{148, 377, 176, 400}` (peso 0.85)
- hull: `{152, 148, 176, 149, 377, 400, 378}`
- domínio Jaw hard-zero: `{58, 288, 132, 361}` + `{172, 136, 365, 397}`

Amplitude lab: `t * 0.04 * faceWidth`. Rampa + kernel gaussiano (código novo; sem helpers de `jaw_field.dart`). A faixa “barba” do Jaw **não** é protecção Chin.

Métrica de produto: `chinShortens` no handle principal vigente (hoje 152).

## Gates

| Gate | Resultado |
|---|---|
| t=0 campo zero | passou nas 3 fotos |
| t=0.5 `chinShortens`, Δy@152 > 1.5 px | passou |
| `|dy|` no primário > 40% de `influenceMax` | passou |
| dx = 0 em todo o campo | passou |
| `|d|` em 58 e 288 = 0 | passou |
| protecções p95 = 0 | passou |
| `outsideChinZoneP95` = 0 | passou |
| `minDetJ > 0` | passou |
| isolamento de imports | passou |
| testes Jaw / renderer / lab Jaw inalterados | passaram |

## Métricas t=0.5

| Foto | chinAmplitude | influenceMax | dy@152 | Δy 152 | gônios \|d\| | minDetJ | protect p95 |
|---|---|---|---|---|---|---|---|
| p01 | 7.58 | 5.86 | −3.66 | **−3.66** | 0 | 0.746 | 0 |
| p05 | 5.75 | 4.11 | −2.83 | **−2.83** | 0 | 0.771 | 0 |
| p12 | 6.51 | 4.91 | −3.33 | **−3.33** | 0 | 0.754 | 0 |

`maxNeighborJump` ≤ 0.22. JSON: `.cursor/facial-warp-v2/chin/A/{real-p01,real-p05,real-p12}/metrics.json`

## Isolamento

O módulo não importa renderer, controller, UI, `extended_roi`, MLS, Telea, `jaw_field.dart` nem `sourceRgba`. Catálogo partilhado só **lido** (oval, olhos, gônios). Nenhum conjunto Chin foi acrescentado a `region_catalog.dart`.

`rm -rf warp/v2/chin` não exige alterar Jaw, renderer ou testes de contrato.

## Testes

`flutter test test/beauty_engine/warp/v2/`

**29/29 passaram.** Inclui os 3 casos novos em `facial_warp_v2_chin_field_test.dart`. Contratos Jaw / renderer / displacement / lab / Device Lab sem mudança de expectativa.

## Arquivos

**Criados**

- `lib/features/editor/beauty_engine/warp/v2/chin/chin_field.dart`
- `lib/features/editor/beauty_engine/warp/v2/chin/chin_masks.dart`
- `lib/features/editor/beauty_engine/warp/v2/chin/chin_metrics.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_chin_field_test.dart`
- `docs/beauty/v2-chin-a-report.md` (este relatório)
- `.cursor/facial-warp-v2/chin/A/` — métricas t=0.5

**Não alterados**

`BackwardBilinearWarp`, `DisplacementField`, `JawField`, `RegionMasks`, `FieldMetrics`, `region_catalog.dart`, controller, preview, export, UI, Device Lab, Body, Skin, Color. Testes de contrato V2 existentes.

## Sprint B

**Não iniciada.** Sem RGBA, sem `v2Raw`, sem lab. A B só depois de aprovação explícita desta A.
