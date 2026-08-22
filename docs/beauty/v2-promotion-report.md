# Promoção Facial Warp V2 (só Jaw)

A pipeline facial do produto passou a ser exclusivamente:

```
JawField.build(face:, imageSize:, t: jaw)
BackwardBilinearWarp.apply(WarpRequest(...))
```

`t` = `parameters['jaw']` em `[0, 1]`. Se `face == null` ou `jaw == 0`, identidade facial. Sem wrappers, sem flag ROI/Mesh/MLS ↔ V2, sem fallback para `ExtendedRoiPipeline`.

Chin, V-face, face_slim, nariz, olhos e boca saíram da UI e deixam de deformar. Body, pele e cor ficaram intactos. O núcleo em `warp/v2/` não mudou de algoritmo.

## Gate (antes da remoção)

- Preview (`BeautyEngineController._renderTexture`) chama `applyJawWarp` no RGBA, depois body/pele/cor.
- Export não-tiled usa o mesmo `_renderTexture`.
- Export tiled aplica Jaw no frame inteiro e tiles só de body.
- Testes `test/beauty_engine/warp/v2/` passaram sem alteração de contrato (JawField / renderer / lab / displacement).
- `flutter analyze lib/features/editor/beauty_engine`: 0 erros.

## Ficheiros alterados

| Ficheiro | O quê |
|---|---|
| `controllers/beauty_engine_controller.dart` | `applyJawWarp`; preview/export sem `composeFaceField` / ROI / mesh ACE |
| `performance/tiled_export_engine.dart` | Jaw no frame; tiles só body |
| `rendering/pass_warp.dart` | Só remap de `WarpField` body |
| `rendering/render_stage_cache.dart` | Hash RGBA seguro em buffers < 4 bytes |
| `presentation/beauty_editor_page.dart` | Sem debug/dump ROI/Mesh; Lab p01/p05/p12 só carregam foto |
| `presentation/widgets/beauty_adjustments_panel.dart` | Rosto só `'jaw'` |
| `tools/beauty_tool_registry.dart` | Catálogo facial só jaw |
| `filters/face/face_filter_pipeline.dart` | `hasActiveWarp` / keys = só jaw |

## Remoção — evidência grep=0

Cada grupo abaixo foi removido só depois de as chamadas de produto terem sido cortadas e `grep` em `lib/` + `test/` (excepto o próprio ficheiro) ter ficado a 0.

### `warp/extended_roi/` (38 ficheiros)

Inclui `ExtendedRoiPipeline`, morphs ROI (`jaw_narrow`, `chin_shortening`, `v_face`, `face_slim_roi`), fills/Telea, dumps e `SilhouetteRouting`.

Evidência: `grep ExtendedRoiPipeline|extended_roi/` em `*.dart` = 0 (só menções negativas nos testes V2: “não importa extended_roi”).

### Mesh ACE / isolate / diagnósticos

`FaceMeshDeformationEngine`, `composeFaceField` / `composeFaceFieldAsync`, `face_warp_isolate`, `FaceWarpEngine`, diagnósticos `face_warp_*diagnostic*`, `face_warp_chin_*`, `face_warp_stage7/8`, `experimental/chin_*`, rasterizer/export mesh, inpaint pós-warp facial, `agent_debug_log`.

Evidência: `grep FaceMeshDeformationEngine|composeFaceField` em `*.dart` = 0.

### MLS facial (filtros de slider)

`FaceSlimFilter`, `JawFilter` (MLS), `ChinFilter`, nariz/olhos/boca e `FaceFilterPipeline.compose`. O `MlsWarpEngine` **não** foi apagado: o Body Reshape ainda o usa (`composeBodyMultiPass`, `local_mls_pass`).

Evidência: `grep FaceSlimFilter|JawFilter|pipeline.compose` em `lib/` = 0 para o compose facial.

### Testes órfãos

Apagados `test/beauty_engine/warp/extended_roi/`, diagnósticos chin/mesh/MVP/golden V3, `face_filter_pipeline_test`, `face_warp_regression_test`, goldens jaw/nose MLS.

## Excepção nos testes V2

`test/beauty_engine/warp/v2/facial_warp_v2_device_lab_test.dart` tinha um caso que renderizava a pipeline ROI (`_renderV1`) e lia `extended_roi_pipeline.dart`. Esse caso foi **removido** para o ficheiro continuar a compilar; os contratos de dump Device Lab (flag, jaw-only, foto aprovada, isolamento de imports) ficaram. Os testes de algoritmo (`jaw_field`, `renderer`, `displacement_field`, `lab`) **não** foram alterados.

## Dependências remanescentes (justificativa)

| Símbolo | Porquê ficou |
|---|---|
| `FaceMeshDetector` / `FaceMeshResult` / landmarks | JawField V2 lê landmarks |
| `MlsWarpEngine` / `mls_solver` / `WarpFieldBuilder` | Body Reshape |
| `PassWarp` | Remap GPU/CPU do **body** |
| `FaceWarpUtils` | Pele, quality, overlay de olhos, spatial index |
| `FaceWarpDebugStats` | Overlay/parity (sempre vazio na V2) |
| `FaceWarpV3Config` + `face_warp_v3_rollout_applier` | Rollout remoto ainda escreve flags; **não** escolhem pipeline facial. Apagá-los exigiria reescrever o rollout — fora de escopo |
| `FacialWarpV2DeviceLab` | Lab de dump; o produto **não** o chama no preview |

Não há selector V1/V2. Não há wrapper. `facialWarpCoreV2Lab` só controla o dump do Device Lab, não o renderer do editor.

## Testes

```
flutter analyze lib/features/editor/beauty_engine   # 0 erros
flutter test --exclude-tags golden                  # 413 passed
flutter test test/beauty_engine/warp/v2/            # passed (contratos intactos)
```

## Fora de escopo (como no plano)

Reimplementar chin/v_face/slim. Fill/Telea. Alterar matemática de `JawField` / renderer. GPU facial. Qualquer camada de escolha entre pipelines.
