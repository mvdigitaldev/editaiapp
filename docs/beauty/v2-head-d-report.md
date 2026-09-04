# Head Sprint D — preview

Data: 2026-09-04.  
Field vigente: `k = 0.12` (`docs/beauty/v2-head.md`). C assinada.

Preview no editor. Sem alterar o Field. Sem fill. Sem `head_size`.

```
applyHeadWarp → HeadField.build + BackwardBilinearWarp
applyFaceWarpChain: head → hairline → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

## O que foi feito

- Key `head`, rótulo **Cabeça**, slider bipolar sem L/R.
- Tab **Proporção** ao lado de Rosto. Rosto não perde sliders.
- `applyHeadWarp` no controller. t=0 não chama o renderer.
- Stage 0 da cadeia. Preview e export já partilham `applyFaceWarpChain` — E não é outro grafo.
- Runtime cacheia o unitário; o slider só multiplica por `α(t)`.

## Isolamento

Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle e Hairline **não** mudaram de Field. Renderer intacto.

## Testes

`flutter test test/beauty_engine/presentation/beauty_adjustments_panel_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_chain_composition_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_head_field_test.dart`

## Sprint E

Não iniciada como sprint à parte. O export já chama o mesmo `applyFaceWarpChain`. Sem relatório E até o Leonardo pedir.
