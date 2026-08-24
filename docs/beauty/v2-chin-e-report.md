# Chin Sprint E — export

Integração só. Preview D permanece a implementação do Chin. O export passa a usar o **mesmo** `applyJawWarp` + `applyChinWarp`. Sem geometria nova, sem segundo renderer, sem pipeline paralela.

```
RGBA
  → applyJawWarp()
  → applyChinWarp()
  → Body
  → Skin
  → Color
```

## Fluxo do export

**Não-tiled** (`BeautyEngineController.exportJpeg` quando a foto não dispara tiles): já chamava `_renderTexture`, o mesmo método do preview (Sprint D). Jaw → Chin → upload GPU → Body → Skin → Color → JPEG. Nenhum código novo neste caminho.

**Tiled** (`TiledExportEngine.exportJpeg`, fotos > 8MP):

1. Detecta face / pose / máscaras (inalterado).
2. `applyJawWarp` no frame inteiro.
3. `applyChinWarp` no RGBA resultante (frame inteiro) — **único acrescento desta sprint**.
4. Body em tiles a partir desse RGBA facial.
5. Skin / Color por tile (`renderPostWarpRgba`).
6. JPEG.

Chin no tiled corre no **frame inteiro**, como o Jaw. Tiles continuam só de body / pós-warp. Sem tiled warp facial, sem `ExportWarp` piecewise, sem inpaint.

`t <= 0` em Chin: `applyChinWarp` devolve o RGBA de entrada sem renderer (contrato D).

## Reutilização

| Peça | Onde |
|---|---|
| `ChinField` | só dentro de `applyChinWarp` (módulo A; não duplicado) |
| `BackwardBilinearWarp` | só via `applyJawWarp` / `applyChinWarp` |
| Preview e export | as mesmas duas funções, mesma ordem |

Não existe `applyChinWarpExport`, Field de export, nem segundo `BackwardBilinearWarp`.

## Arquivos modificados

| Ficheiro | O quê |
|---|---|
| `performance/tiled_export_engine.dart` | `applyChinWarp` a seguir a `applyJawWarp`; body tiles leem `faceRgba` |

## Arquivos não modificados

- `chin_field.dart`, `chin_masks.dart`, `chin_metrics.dart`
- `jaw_field.dart`
- `backward_bilinear_warp.dart`, `DisplacementField`
- `RegionMasks`, `FieldMetrics`
- `applyChinWarp` / `_renderTexture` (Sprint D)
- Skin, Body, Color

`git diff` em `lib/.../warp/v2/`: vazio nesta sprint.

## Critérios

| Caso | Preview | Export |
|---|---|---|
| jaw=0, chin=0 | identidade facial | mesmo grafo |
| jaw>0, chin=0 | só Jaw (`applyChinWarp` no-op) | igual |
| jaw=0, chin>0 | só Chin | igual |
| ambos > 0 | Jaw depois Chin | igual |

Não-tiled: preview e export **são** `_renderTexture`. Tiled: mesmas `apply*` no frame, depois body/pele/cor.

## Testes

```
flutter test test/beauty_engine/warp/v2/
```

**31/31 passaram.** Contratos Jaw / renderer / Chin A–B intactos.

## Preview vs export (visual)

O grafo facial do export é o de D. Chin-only = lab B (`v2Raw`):

- `.cursor/facial-warp-v2/chin/B/p01/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/chin/B/p05/{0,25,50}/v2Raw.png`
- `.cursor/facial-warp-v2/chin/B/p12/{0,25,50}/v2Raw.png`

Captura lado a lado JPEG vs ecrã no device: no editor, mesmos sliders, Guardar, comparar com o preview (hot restart depois desta E). JPEG adiciona compressão; o RGBA facial é o mesmo grafo.

## Rollback

Remover as linhas `applyChinWarp` / `faceRgba` em `tiled_export_engine.dart`. Preview D, Field, renderer e Jaw ficam. Export não-tiled continua a herdar D via `_renderTexture`.

## Fora de escopo (cumprido)

Sem Face Slim / Nose / Eyes / Mouth. Sem Device Lab. Sem mixer. Sem fill/Telea. Sem ajuste geométrico.
