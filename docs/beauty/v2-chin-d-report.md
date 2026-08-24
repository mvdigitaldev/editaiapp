# Chin Sprint D — preview

Integração só. O `ChinField` aprovado nas Sprints A–C entra no preview. Sem recalibração, sem mixer, sem export.

```
RGBA
  → applyJawWarp()
  → applyChinWarp()
  → Body
  → Skin
  → Color
```

Body/Skin/Color **não** foram reordenados. Export tiled continua só Jaw (Sprint E).

## Wiring

`applyChinWarp` copia o padrão de `applyJawWarp`:

```
ChinField.build(face, imageSize, t)
  → DisplacementField
  → BackwardBilinearWarp.apply(WarpRequest(...))
```

`t = parameters['chin']` em `[0, 1]`. Se `face == null` ou `t <= 0`, devolve o RGBA de entrada **sem** chamar o renderer.

`_renderTexture` chama Jaw e depois Chin sobre o RGBA resultante. Cada um gera o seu Field a partir da face original. Sem soma de campos.

Slider Rosto: keys `['jaw', 'chin']` via `FaceFilterPipeline.faceWarpParameterKeys`.

## Ordem Jaw → Chin

Confirmada em `_renderTexture`: `applyJawWarp` depois `applyChinWarp`. Sem `FaceWarpPipeline`, `FaceWarpMixer`, `CompositeField` ou `applyFaceWarp()`.

- `chin = 0`: Chin é no-op; preview = Jaw actual.
- `jaw = 0` e `chin > 0`: só Chin.
- ambos > 0: Jaw depois Chin, sequencial.

## `chin = 0` é identidade

`applyChinWarp` retorna `sourceRgba` quando `t <= 0`. Não chama `ChinField.build` nem o renderer. O lab B já provou t=0 `v2Raw` byte-igual à fonte.

## Field intocado

`git diff` em `lib/.../warp/v2/`: **vazio**.

Não alterados: `chin_field.dart`, `chin_masks.dart`, `chin_metrics.dart`, `jaw_field.dart`, `backward_bilinear_warp.dart`, `displacement_field.dart`, `RegionMasks`, `FieldMetrics`.

## Arquivos modificados

| Ficheiro | O quê |
|---|---|
| `controllers/beauty_engine_controller.dart` | `applyChinWarp`; preview Jaw → Chin |
| `filters/face/face_filter_pipeline.dart` | keys `jaw`, `chin`; `hasActiveWarp` |
| `tools/beauty_tool_registry.dart` | descriptor `chin` |
| `presentation/widgets/beauty_adjustments_panel.dart` | sliders Rosto = keys do pipeline |
| `presentation/beauty_editor_page.dart` | `chin` pede face no preview |
| testes de painel / regressão | aceitam a key `chin` |

**Não alterados:** tiled export, Device Lab, módulo Chin, renderer, Jaw.

## Preview visual (mesmo grafo que o lab B)

O preview chin-only chama o mesmo `ChinField` + `BackwardBilinearWarp` das 9 runs B. Screenshots do `v2Raw` aprovado na C:

**p01** — t=0 / 25 / 50

![p01 t=0](../../.cursor/facial-warp-v2/chin/B/p01/0/v2Raw.png)
![p01 t=25](../../.cursor/facial-warp-v2/chin/B/p01/25/v2Raw.png)
![p01 t=50](../../.cursor/facial-warp-v2/chin/B/p01/50/v2Raw.png)

**p05** — t=0 / 25 / 50

![p05 t=0](../../.cursor/facial-warp-v2/chin/B/p05/0/v2Raw.png)
![p05 t=25](../../.cursor/facial-warp-v2/chin/B/p05/25/v2Raw.png)
![p05 t=50](../../.cursor/facial-warp-v2/chin/B/p05/50/v2Raw.png)

**p12** — t=0 / 25 / 50

![p12 t=0](../../.cursor/facial-warp-v2/chin/B/p12/0/v2Raw.png)
![p12 t=25](../../.cursor/facial-warp-v2/chin/B/p12/25/v2Raw.png)
![p12 t=50](../../.cursor/facial-warp-v2/chin/B/p12/50/v2Raw.png)

Caminhos: `.cursor/facial-warp-v2/chin/B/{p01,p05,p12}/{0,25,50}/v2Raw.png`

## Testes

```
flutter test test/beauty_engine/warp/v2/
```

**31/31 passaram** (suite V2; contratos Jaw/renderer/Chin A/B intactos).

Painel + regressão (keys `chin`) também verdes nesta entrega.

## Rollback

Apagar só a integração: `applyChinWarp`, a chamada no `_renderTexture`, key `'chin'` no pipeline/registry/painel. Infra e Fields ficam.

## Sprint E

**Não iniciada.** Export tiled ainda aplica só Jaw.
