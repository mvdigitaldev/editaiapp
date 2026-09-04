# Eyebrow Height Sprint D — preview

Data: 2026-09-04.  
Field vigente: `dy = −t_lado · 0.035 · faceWidth · w` (`docs/beauty/v2-eyebrow-height.md`). C assinada.

Preview no editor. Sem alterar o Field. Sem fill. Sem makeup `eyebrows`. Sem Width / Length / Shape.

```
applyEyebrowHeightWarp → EyebrowHeightField.build + BackwardBilinearWarp
applyFaceWarpChain: head → hairline → eyebrow_height → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

## O que foi feito

- Key `eyebrow_height`, rótulo **Altura**, slider bipolar com Geral / Esquerda / Direita (lados da foto).
- Tab **Sobrancelha** à direita de Rosto. Rosto e Pele não perdem sliders. Makeup `eyebrows` fica na Pele.
- `applyEyebrowHeightWarp` no controller. t=0 não chama o renderer.
- Stage depois do Hairline. Preview e export já partilham `applyFaceWarpChain` — E não é outro grafo.
- Runtime cacheia o unitário; o slider só escala `dy`.

## Isolamento

Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline e Head **não** mudaram de Field. Renderer intacto. Key `eyebrows` intacta.

## Testes

`flutter test test/beauty_engine/presentation/beauty_adjustments_panel_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_chain_composition_test.dart`  
`flutter test test/beauty_engine/regression/beauty_engine_regression_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_height_field_test.dart`

## Sprint E

Não iniciada como sprint à parte. O export já chama o mesmo `applyFaceWarpChain`. Sem relatório E até o Leonardo pedir.
