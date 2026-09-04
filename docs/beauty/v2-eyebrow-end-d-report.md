# Eyebrow End Sprint D — preview

Data: 2026-09-04.  
Field vigente: `dx = t_lado · 0.030 · faceWidth · w · band · s_inner · away` (`docs/beauty/v2-eyebrow-end.md`). C assinada. Amplitude calibrada 2026-09-04 (`0.010` → `0.016` → `0.020` → `0.030`).

Preview no editor. Sem alterar o Field. Sem fill. Sem makeup `eyebrows`. Sem Length / Front / Angle / Shape.

```
applyEyebrowEndWarp → EyebrowEndField.build + BackwardBilinearWarp
applyFaceWarpChain: head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

## O que foi feito

- Key `eyebrow_end`, rótulo **Ponta**, slider bipolar com Geral / Esquerda / Direita (lados da foto).
- Ícone na tab **Sobrancelha**, à direita de Largura. Makeup `eyebrows` fica na Pele.
- `applyEyebrowEndWarp` no controller. t=0 não chama o renderer.
- Stage depois da Largura. Preview e export já partilham `applyFaceWarpChain` — E não é outro grafo.
- Runtime cacheia `w · band · s_inner · away`; o slider só escala `dx`.

## Isolamento

Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle, Hairline, Head, Eyebrow Height e Eyebrow Width **não** mudaram de Field. Renderer intacto. Key `eyebrows` intacta.

## Testes

`flutter test test/beauty_engine/presentation/beauty_adjustments_panel_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_chain_composition_test.dart`  
`flutter test test/beauty_engine/regression/beauty_engine_regression_test.dart`  
`flutter test test/beauty_engine/warp/v2/facial_warp_v2_eyebrow_end_field_test.dart`

## Sprint E

Não iniciada como sprint à parte. O export já chama o mesmo `applyFaceWarpChain`. Sem relatório E até o Leonardo pedir.
