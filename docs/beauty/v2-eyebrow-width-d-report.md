# Eyebrow Width Sprint D — preview

Data: 2026-09-04.  
Field vigente: `dy = t_lado · 0.008 · faceWidth · w · s` (`docs/beauty/v2-eyebrow-width.md`). C assinada.

Preview no editor. Sem alterar o Field. Sem fill. Sem makeup `eyebrows`. Sem Length / End / Front / Angle / Shape.

```
applyEyebrowWidthWarp → EyebrowWidthField.build + BackwardBilinearWarp
applyFaceWarpChain: head → hairline → eyebrow_height → eyebrow_width → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

## O que foi feito

- Key `eyebrow_width`, rótulo **Largura**, slider bipolar com Geral / Esquerda / Direita (lados da foto).
- Ícone na tab **Sobrancelha**, à direita de Altura. Makeup `eyebrows` fica na Pele.
- `applyEyebrowWidthWarp` no controller. t=0 não chama o renderer.
- Stage depois da Altura. Preview e export já partilham `applyFaceWarpChain` — E não é outro grafo.
- Runtime cacheia `w · s`; o slider só escala `dy`.

## Isolamento

Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline, Head e Eyebrow Height **não** mudaram de Field. Renderer intacto. Key `eyebrows` intacta.

## Testes

`flutter test test/beauty_engine/presentation/beauty_adjustments_panel_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_chain_composition_test.dart`  
`flutter test test/beauty_engine/regression/beauty_engine_regression_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_width_field_test.dart`

## Sprint E

Não iniciada como sprint à parte. O export já chama o mesmo `applyFaceWarpChain`. Sem relatório E até o Leonardo pedir.
