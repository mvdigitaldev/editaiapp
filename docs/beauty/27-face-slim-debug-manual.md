# Face Slim (`face_slim`) — Manual de Debug e Mapa Completo de Arquivos

> **Gerado:** 2026-08-10 · sessão debug `13c8af`  
> **Objetivo:** documentar **todos** os arquivos, o fluxo end-to-end e o estado atual dos bugs para debug manual.

---

## 1. Resumo executivo

**Ferramenta:** `face_slim` (UI: "Afinar rosto") — slider 0..1, chave interna `face_slim`.

**Sintoma atual (87%):** blocos retangulares de textura nas bochechas, smear lateral, orelha deformada. Malha/landmarks **corretos** na overlay; pixels **não** acompanham limpo.

**Backend ativo hoje:** `v3_mesh` (`FaceWarpV3Config.useForwardMeshWarpFaceSlim = true`).

**Evidência runtime (`.cursor/debug-13c8af.log`):**

| Métrica | Valor @ ~31px Δv | Interpretação |
|---------|------------------|---------------|
| `meshHitPx` | ~164–171k | Backward mesh cobre bbox da face |
| `holeFillPx` | **1938** (constante) | `_fillLateralDisocclusion` pinta ~2k px com cor **flat** de fundo |
| `vacCompositePx` (path antigo) | ~1948 | Mesmo padrão — **causa provável dos blocos** |
| `landmarkCount` vs `meshVertexCount` | 478 vs **468** | ACE tem 478 slots; malha triangulada usa 468 vértices |
| `peakDisp` | ~31 px @ 87% | Deslocamento ACE ok |

**Correções já aplicadas nesta sessão:**
- RangeError `936`: loop de deformação limitado a `min(landmarkCount, meshVertexCount)`.
- Troca forward-splat → backward mesh (`FaceMeshForwardWarp.apply`).
- Removido `FaceSlimWarp.postProcess` do path mesh.
- **Hole fill lateral desligado** (comentado) — reativar só com inpaint/NN, não bg flat.

---

## 2. Fluxo end-to-end (ordem de execução)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ UI: beauty_editor_page → slider face_slim (0..1)                        │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ BeautyEngineController.applyAdjustment / preview pipeline               │
│  • debounce slider (landmark_throttle)                                  │
│  • detectFace() → FaceMeshDetector (478 landmarks MediaPipe)            │
│  • personMask opcional → PersonMaskDetector                             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ composeFaceField() — ramo V3 se FaceWarpV3Config.enabled                │
│  1. meshEngine.buildFaceMesh() → TriMesh (468 vértices + índices)       │
│  2. FaceMeshDeformationEngine.composeVertexField()                      │
│       AnatomicalIntentFactory → ACE → ConstrainedVertexField            │
│       pilot_warp_displacement._faceSlim() para deslocamento horizontal  │
│  3. FaceMeshDeformationEngine.composeWarpField()                        │
│       FaceMeshWarpRasterizer → WarpField grade 160–192 (fallback CPU)   │
│  4. FaceMatteRoi.buildInfluenceMap(lateralRadiusExpand: 0.07)           │
│  5. FaceMeshForwardPayload(mesh, vertexField, influence, personMask)    │
│  6. lastFaceWarpBackend = 'v3_mesh' | 'v3_cpu' | 'v3_gpu'               │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ GpuRenderer / PassWarp.execute()                                        │
│  SE face_slim only + useForwardMeshWarpFaceSlim + payload:              │
│    → FaceMeshForwardWarp.apply()  [backward piecewise, badge V3_MESH]   │
│  SENÃO fallback:                                                        │
│    → GPU piecewise (desligado preview face_slim: allowGpuFaceSlim=false)│
│    → WarpCpuRemap + FaceSlimWarp.postProcess (path v3_cpu)              │
│    → MLS legado (useLegacyFaceMls)                                      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Pós-processamento (PassWarp continuação)                                │
│  • FaceWarpPostInpaint (export / flag postWarpInpaint)                  │
│  • FaceWarpHoleFill.imputeFromGhostMask (path CPU grid)                 │
│  • RenderStageCache para sliders de cor                                 │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
                         ProcessedFrame RGBA → UI
```

### Diagrama de decisão de backend (`PassWarp`)

```
face_slim only?
  ├─ SIM + useForwardMeshWarpFaceSlim + FaceMeshForwardPayload
  │     → FaceMeshForwardWarp.apply  →  backend: v3_mesh
  ├─ GPU piecewise + changedPixels
  │     → FaceSlimWarp.postProcess(backend:'gpu')  →  v3_gpu
  ├─ WarpCpuRemap (grade WarpField)
  │     → FaceSlimWarp.apply / postProcess  →  v3_cpu
  └─ MLS (legado)
        → MlsWarpEngine  →  mls
```

---

## 3. Arquivos por camada (lista completa)

### 3.1 UI e entrada

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/presentation/beauty_editor_page.dart` | Tela principal; slider `face_slim`, toggles lab V3, overlay debug |
| `lib/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart` | Painel "Afinar rosto" na seção Face |
| `lib/features/editor/beauty_engine/presentation/widgets/beauty_accessible_slider.dart` | Widget slider acessível |
| `lib/features/editor/beauty_engine/presentation/face_retouch_entry_page.dart` | Entry retoque facial |
| `lib/features/editor/beauty_engine/presentation/beauty_retouch_hub_page.dart` | Hub de módulos |
| `lib/features/editor/beauty_engine/presentation/face_filters_demo_page.dart` | Demo filtros |
| `lib/features/editor/beauty_engine/presentation/preset_creator_page.dart` | Presets com faceSlim |
| `lib/features/editor/beauty_engine/presentation/widgets/face_selection_overlay.dart` | Multi-face |
| `lib/features/editor/beauty_engine/presentation/widgets/anatomy_debug_overlay.dart` | Overlay malha ACE |
| `lib/features/editor/beauty_engine/presentation/widgets/warp_debug_overlay.dart` | Overlay campo warp |
| `lib/features/editor/beauty_engine/presentation/widgets/parity_checklist_panel.dart` | Checklist paridade |
| `lib/features/editor/beauty_engine/presentation/preset_sync_bootstrap.dart` | Bootstrap presets |

### 3.2 Controller e DI

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/controllers/beauty_engine_controller.dart` | **Orquestrador central** — composeFaceField, payload mesh, badge backend |
| `lib/features/editor/beauty_engine/di/beauty_engine_providers.dart` | Providers Riverpod |
| `lib/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart` | Init MediaPipe |
| `lib/features/editor/beauty_engine/di/face_warp_v3_rollout_provider.dart` | Rollout remoto V3 |
| `lib/features/editor/beauty_engine/beauty_engine.dart` | Barrel export |

### 3.3 Parâmetros e presets

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/models/face_params.dart` | `faceSlim` 0..1 |
| `lib/features/editor/beauty_engine/models/beauty_preset.dart` | JSON `face_slim` |
| `lib/features/editor/beauty_engine/models/processing_pipeline.dart` | Pipeline preset+overrides |
| `lib/features/editor/beauty_engine/tools/beauty_tool_registry.dart` | Registro ferramenta `face_slim` |
| `lib/features/editor/beauty_engine/tools/tool_descriptor.dart` | Metadados ferramenta |
| `lib/features/editor/beauty_engine/tools/tool_gate_engine.dart` | Quality gating |
| `lib/features/editor/beauty_engine/tools/tool_gate_decision.dart` | Decisão gating |
| `lib/features/editor/beauty_engine/l10n/beauty_engine_labels.dart` | Label "Face Slim" |
| `lib/features/editor/beauty_engine/presets/bundled_preset_loader.dart` | Presets bundled |
| `lib/features/editor/beauty_engine/presets/adaptive_preset_engine.dart` | Preset adaptativo |
| `assets/beauty/presets/beauty.json` | faceSlim: 0.35 |
| `assets/beauty/presets/glam.json` | 0.28 |
| `assets/beauty/presets/influencer.json` | 0.32 |
| `assets/beauty/presets/instagram.json` | 0.18 |
| `assets/beauty/presets/soft.json` | 0.08 |
| `assets/beauty/presets/wedding.json` | 0.12 |

### 3.4 Detecção e malha

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/face_mesh/face_mesh_detector.dart` | Interface detector |
| `lib/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart` | MediaPipe nativo |
| `lib/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart` | Stub desktop/test |
| `lib/features/editor/beauty_engine/face_mesh/face_landmark_mapper.dart` | Landmarks → FaceMeshResult |
| `lib/features/editor/beauty_engine/models/face_mesh_result.dart` | 478 landmarks |
| `lib/features/editor/beauty_engine/models/face_landmark.dart` | Landmark unitário |
| `lib/features/editor/beauty_engine/models/multi_face_detection.dart` | Multi-face |
| `lib/features/editor/beauty_engine/mesh/mesh_engine.dart` | Interface mesh |
| `lib/features/editor/beauty_engine/mesh/mesh_engine_impl.dart` | Facade + cache |
| `lib/features/editor/beauty_engine/mesh/mesh_engine_stub.dart` | Stub |
| `lib/features/editor/beauty_engine/mesh/face_mesh_builder.dart` | FaceMeshResult → TriMesh |
| `lib/features/editor/beauty_engine/mesh/mesh_topology.dart` | Topologia |
| `lib/features/editor/beauty_engine/mesh/face_mesh_topology.generated.dart` | **GERADO** — triângulos 468pt |
| `lib/features/editor/beauty_engine/mesh/mesh_cache.dart` | Cache malha |
| `lib/features/editor/beauty_engine/mesh/mesh_utils.dart` | Utils geométricos |
| `lib/features/editor/beauty_engine/models/tri_mesh.dart` | Malha (vertices, indices) |
| `lib/features/editor/beauty_engine/mesh/tri_mesh_spatial_index.dart` | Lookup baricêntrico O(k) |
| `lib/features/editor/beauty_engine/models/mesh_region.dart` | Regiões (jaw, etc.) |
| `scripts/download_mediapipe_models.sh` | Download modelos |
| `scripts/download_mediapipe_models.ps1` | Windows |

### 3.5 ACE / deformação V3

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart` | **Orquestrador V3** — vertex field + warp field + GPU payload |
| `lib/features/editor/beauty_engine/warp/anatomy/anatomical_constraint_engine.dart` | ACE — pins, clamp, anti-fold |
| `lib/features/editor/beauty_engine/warp/anatomy/anatomical_intent_factory.dart` | Sliders → intents |
| `lib/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart` | Modelo intent |
| `lib/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart` | Zonas anatômicas |
| `lib/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart` | Limites normativos `face_slim` |
| `lib/features/editor/beauty_engine/warp/anatomy/pilot_warp_displacement.dart` | **`_faceSlim()`** — deslocamento horizontal, zoneWeight orelha/barba |
| `lib/features/editor/beauty_engine/warp/anatomy/pilot_warp_contour_nose.dart` | Contorno/nariz (família lateral) |
| `lib/features/editor/beauty_engine/warp/anatomy/constrained_vertex_field.dart` | Δv por vértice pós-ACE |
| `lib/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart` | Papéis vértice (pin/free) |
| `lib/features/editor/beauty_engine/warp/anatomy/face_warp_debug_stats.dart` | Stats Δv, folds |
| `lib/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart` | ROI oval + influence map |

### 3.6 Filtros MLS legados (fallback)

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/filters/face/face_slim.dart` | **FaceSlimFilter** — control points MLS mandíbula |
| `lib/features/editor/beauty_engine/filters/face/jaw.dart` | `jaw` (disjunto de face_slim) |
| `lib/features/editor/beauty_engine/filters/face/narrow_face.dart` | narrow_face |
| `lib/features/editor/beauty_engine/filters/face/v_face.dart` | v_face |
| `lib/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart` | Pipeline composável |
| `lib/features/editor/beauty_engine/filters/face/face_warp_filter.dart` | Interface filtro |
| `lib/features/editor/beauty_engine/filters/face/face_warp_context.dart` | Contexto filtro |
| `lib/features/editor/beauty_engine/filters/face/face_warp_utils.dart` | Âncoras, índices região |
| `lib/features/editor/beauty_engine/filters/face/face_warp_region.dart` | Regiões face_slim |
| `lib/features/editor/beauty_engine/filters/face/face_influence_map_builder.dart` | Influence map builder |
| `lib/features/editor/beauty_engine/warp/models/control_point.dart` | Control point MLS |
| `lib/features/editor/beauty_engine/warp/control_point_builder.dart` | Builder control points |
| `lib/features/editor/beauty_engine/warp/warp_field_builder.dart` | Grade WarpField; **`forFaceSlimInteractive`** 160–192 |
| `lib/features/editor/beauty_engine/models/warp_field.dart` | Campo dx/dy |
| `lib/features/editor/beauty_engine/models/warp_algorithm.dart` | Enum algoritmo |

### 3.7 Renderização warp (CRÍTICO para face_slim)

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/rendering/pass_warp.dart` | **PassWarp** — escolhe mesh/GPU/CPU/MLS |
| `lib/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart` | **FaceMeshForwardWarp** — backward piecewise mesh (nome histórico "forward") |
| `lib/features/editor/beauty_engine/warp/face_slim_warp.dart` | **FaceSlimWarp** — liquify CPU + vac composite lateral |
| `lib/features/editor/beauty_engine/warp/face_mesh_warp_rasterizer.dart` | Malha ACE → WarpField grade |
| `lib/features/editor/beauty_engine/warp/warp_cpu_remap.dart` | Remap bilinear grade + anti-ghost |
| `lib/features/editor/beauty_engine/warp/face_mesh_export_warp.dart` | Export tiled alta res |
| `lib/features/editor/beauty_engine/warp/face_mesh_gpu_payload.dart` | Atlas GPU |
| `lib/features/editor/beauty_engine/warp/face_mesh_cell_index.dart` | Índice células GPU |
| `lib/features/editor/beauty_engine/warp/fragment_program_face_mesh_backend.dart` | Backend GPU piecewise |
| `lib/features/editor/beauty_engine/warp/fragment_program_face_inpaint_backend.dart` | Backend GPU inpaint |
| `lib/features/editor/beauty_engine/warp/native_face_mesh_payload.dart` | Payload MethodChannel |
| `lib/features/editor/beauty_engine/warp/face_mesh_native_export_backend.dart` | Interface export nativo |
| `lib/features/editor/beauty_engine/warp/method_channel_native_face_mesh_backend.dart` | MethodChannel Metal/GLES |
| `lib/features/editor/beauty_engine/warp/mls_warp_engine.dart` | Fallback MLS |
| `lib/features/editor/beauty_engine/warp/mls_solver.dart` | Solver MLS |
| `lib/features/editor/beauty_engine/warp/warp_engine.dart` | Interface warp |
| `lib/features/editor/beauty_engine/warp/warp_engine_factory.dart` | Factory |
| `lib/features/editor/beauty_engine/warp/warp_engine_stub.dart` | Stub |
| `lib/features/editor/beauty_engine/body_reshape/rendering/fragment_program_warp_backend.dart` | Shader MLS/body fallback |
| `lib/features/editor/beauty_engine/rendering/fragment_program_backend.dart` | Interface backend |
| `lib/features/editor/beauty_engine/rendering/gpu_renderer.dart` | Interface GPU |
| `lib/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart` | Impl GPU |
| `lib/features/editor/beauty_engine/rendering/render_pass.dart` | Interface pass |
| `lib/features/editor/beauty_engine/rendering/render_target.dart` | Alvos + RenderShaders |
| `lib/features/editor/beauty_engine/rendering/render_stage_cache.dart` | Cache pós-warp |
| `lib/features/editor/beauty_engine/rendering/texture_handle.dart` | Handle textura |
| `lib/features/editor/beauty_engine/rendering/texture_pool.dart` | Pool |
| `lib/features/editor/beauty_engine/rendering/shader_program_cache.dart` | Cache shaders |
| `lib/features/editor/beauty_engine/body_reshape/rendering/export_warp.dart` | Export tiles |
| `lib/features/editor/beauty_engine/body_reshape/rendering/native_export_backend.dart` | Export nativo base |
| `lib/features/editor/beauty_engine/body_reshape/rendering/warp_texture.dart` | Utils textura |
| `lib/features/editor/beauty_engine/body_reshape/rendering/render_plan.dart` | Plano multi-pass |

### 3.8 Máscaras e proteção

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/body_reshape/maps/influence_map.dart` | Mapa influência 0–1 |
| `lib/features/editor/beauty_engine/segment/person_mask.dart` | Person mask |
| `lib/features/editor/beauty_engine/segment/person_mask_detector_impl.dart` | Detector segmentação |
| `lib/features/editor/beauty_engine/segment/person_mask_detector_stub.dart` | Stub |
| `lib/features/editor/beauty_engine/body_reshape/maps/person_mask_bridge.dart` | Ponte segmentação |
| `lib/features/editor/beauty_engine/body_reshape/maps/matte_preprocessor.dart` | Pré-process matte |
| `lib/features/editor/beauty_engine/body_reshape/protection/rigidity_map.dart` | Rigidity / proteção bordas |
| `lib/features/editor/beauty_engine/filters/face/mask_factory.dart` | Factory máscaras |
| `lib/features/editor/beauty_engine/filters/face/derived_masks.dart` | Máscaras derivadas parsing |
| `lib/features/editor/beauty_engine/filters/face/skin_soft_region.dart` | Regiões pele |
| `lib/features/editor/beauty_engine/filters/face/skin_mask_utils.dart` | Utils pele |
| `lib/features/editor/beauty_engine/segment/face_parsing_detector.dart` | Face parsing |
| `lib/features/editor/beauty_engine/segment/face_parsing_result.dart` | Resultado parsing |
| `lib/features/editor/beauty_engine/segment/face_parsing_mapper.dart` | Mapper parsing |
| `lib/features/editor/beauty_engine/segment/parsing_fallback_policy.dart` | Fallback parsing |
| `lib/features/editor/beauty_engine/segment/parsing_mask_cache.dart` | Cache parsing |
| `lib/features/editor/beauty_engine/segment/face_parts_detector.dart` | Partes faciais |
| `lib/features/editor/beauty_engine/segment/face_parts_segmentation.dart` | Segmentação partes |
| `lib/features/editor/beauty_engine/warp/face_warp_ghost_mask.dart` | Máscara fantasma inpaint |

### 3.9 Pós-processamento

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/warp/anatomy/face_warp_vacancy_fill.dart` | Vacancy fill na **grade** WarpField |
| `lib/features/editor/beauty_engine/warp/face_warp_post_inpaint.dart` | Inpaint leve pós-warp |
| `lib/features/editor/beauty_engine/warp/face_warp_hole_fill.dart` | Imputação NN buracos (path CPU grid) |

### 3.10 Config, flags, rollout

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/config/face_warp_v3_config.dart` | **`useForwardMeshWarpFaceSlim`**, GPU, inpaint, native |
| `lib/features/editor/beauty_engine/config/face_warp_v3_rollout.dart` | Chaves rollout Supabase |
| `lib/features/editor/beauty_engine/config/face_warp_v3_rollout_applier.dart` | Aplica rollout → config |
| `lib/features/editor/beauty_engine/config/beauty_engine_rollout.dart` | Rollout genérico |
| `lib/features/editor/beauty_engine/debug/agent_debug_log.dart` | Log NDJSON sessão debug |
| `supabase/migrations/20260807180000_face_warp_v3_rollout.sql` | Migration rollout |
| `supabase/migrations/20260807193000_face_warp_v3_sprint41_rollout.sql` | Sprint 41 |
| `supabase/migrations/20260807220000_face_warp_v3_full_enable.sql` | Enable total |
| `pubspec.yaml` | Declara shaders `face_mesh_piecewise.frag`, `face_warp_inpaint.frag` |

### 3.11 Performance

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/performance/face_warp_isolate.dart` | MLS em isolate |
| `lib/features/editor/beauty_engine/performance/tiled_export_engine.dart` | Export >8MP |
| `lib/features/editor/beauty_engine/performance/shader_prewarm_service.dart` | Prewarm shaders |
| `lib/features/editor/beauty_engine/performance/device_capability.dart` | Capabilities device |
| `lib/features/editor/beauty_engine/performance/adaptive_preview_policy.dart` | Preview adaptativo |
| `lib/features/editor/beauty_engine/performance/landmark_throttle.dart` | Throttle re-detecção |
| `lib/features/editor/beauty_engine/performance/beauty_profiler.dart` | Profiler latência |

### 3.12 Shaders

| Arquivo | Papel |
|---------|-------|
| `lib/features/editor/beauty_engine/shaders/face_mesh_piecewise.frag` | Piecewise-affine GPU V3 |
| `lib/features/editor/beauty_engine/shaders/face_warp_inpaint.frag` | Inpaint pós-warp GPU |
| `lib/features/editor/beauty_engine/shaders/warp_remap.frag` | MLS/body remap fallback |
| `lib/features/editor/beauty_engine/shaders/README.md` | Doc shaders |

### 3.13 Native (MediaPipe + export Metal/GLES)

| Arquivo | Papel |
|---------|-------|
| `packages/beauty_mediapipe/lib/beauty_mediapipe.dart` | Export plugin |
| `packages/beauty_mediapipe/lib/src/beauty_mediapipe_bindings.dart` | Bindings Dart |
| `packages/beauty_mediapipe/lib/src/beauty_mediapipe_method_channel.dart` | MethodChannel |
| `packages/beauty_mediapipe/lib/src/native_image_buffer.dart` | Buffer imagem |
| `packages/beauty_mediapipe/lib/src/mediapipe_model_loader.dart` | Loader modelos |
| `packages/beauty_mediapipe/ios/Classes/BeautyMediapipePlugin.swift` | Plugin iOS |
| `packages/beauty_mediapipe/ios/Classes/FaceMeshMetalBackend.swift` | Export Metal piecewise |
| `packages/beauty_mediapipe/ios/Classes/FaceLandmarkerBridge.swift` | Face Landmarker iOS |
| `packages/beauty_mediapipe/ios/Classes/ImageSegmenterBridge.swift` | Segmentação iOS |
| `packages/beauty_mediapipe/ios/beauty_mediapipe.podspec` | Podspec |
| `packages/beauty_mediapipe/android/.../BeautyMediapipePlugin.kt` | Plugin Android |
| `packages/beauty_mediapipe/android/.../FaceMeshGlesBackend.kt` | Export GLES |
| `packages/beauty_mediapipe/android/.../FaceLandmarkerBridge.kt` | Landmarker Android |
| `packages/beauty_mediapipe/android/.../ImageSegmenterBridge.kt` | Segmentação Android |
| `packages/beauty_mediapipe/android/.../ImageBitmapDecoder.kt` | Decoder bitmap |
| `packages/beauty_mediapipe/pubspec.yaml` | Pacote plugin |

### 3.14 Testes

| Arquivo | Papel |
|---------|-------|
| `test/beauty_engine/warp/face_v3_cpu_remap_integration_test.dart` | Integração CPU remap + face_slim |
| `test/beauty_engine/warp/face_warp_v3_pilot_test.dart` | Piloto V3 face_slim |
| `test/beauty_engine/warp/face_mesh_deformation_engine_test.dart` | Deformation engine |
| `test/beauty_engine/warp/anatomical_constraint_engine_test.dart` | ACE |
| `test/beauty_engine/warp/face_model_spec_test.dart` | Spec face_slim |
| `test/beauty_engine/warp/face_warp_vacancy_fill_test.dart` | Vacancy fill |
| `test/beauty_engine/warp/face_warp_v3_gpu_inpaint_test.dart` | Inpaint GPU |
| `test/beauty_engine/warp/face_warp_v3_sprint38_test.dart` | Sprint 38 |
| `test/beauty_engine/warp/face_warp_v3_sprint39_test.dart` | Sprint 39 native |
| `test/beauty_engine/warp/face_warp_v3_sprint41_test.dart` | Sprint 41 rollout |
| `test/beauty_engine/warp/face_warp_v3_contour_nose_test.dart` | Contorno/nariz |
| `test/beauty_engine/warp/face_warp_v3_eye_mouth_test.dart` | Olhos/boca |
| `test/beauty_engine/rendering/pass_warp_test.dart` | PassWarp |
| `test/beauty_engine/filters/face_filter_pipeline_test.dart` | FaceSlimFilter |
| `test/beauty_engine/controllers/beauty_engine_controller_test.dart` | Controller |
| `test/beauty_engine/warp_engine_test.dart` | Warp engine |
| `test/golden/face_warp_v3_pilot_golden_test.dart` | Golden face_slim |
| `test/golden/goldens/v3_pilot_face_slim.png` | Imagem referência |
| `test/golden/goldens/v3_narrow_face.png` | Golden narrow_face |
| (+ demais goldens contorno/olhos — ver `test/golden/`) |

### 3.15 Documentação existente

| Arquivo | Papel |
|---------|-------|
| `docs/beauty/04-warp.md` | Arquitetura warp |
| `docs/beauty/07-face-filters.md` | Filtros faciais |
| `docs/beauty/23-face-model-specification.md` | Spec normativa V3 |
| `docs/beauty/13-visual-quality-targets.md` | Metas qualidade |
| `docs/beauty/22-sprint36-contour-direct.md` | Sprint 36 malha direta |
| `docs/beauty/23-sprint37-gpu-inpaint.md` | Sprint 37 GPU |
| `docs/beauty/24-sprint38-export-inpaint-rollout.md` | Sprint 38 |
| `docs/beauty/25-sprint39-native-parity-swap.md` | Sprint 39 |
| `docs/beauty/26-sprint41-production-rollout.md` | Sprint 41 |
| `docs/beauty/03-mesh.md` | Malha 478pt |
| `docs/beauty/05-render.md` | Pipeline render |
| `docs/beauty/01-arquitetura.md` | Arquitetura geral |

---

## 4. Constantes e thresholds importantes

### `pilot_warp_displacement._faceSlim()`
- `effectiveMag = magnitude^1.35`
- `maxPx = 0.08 * fse * effectiveMag`
- `zoneWeight` orelha (ny<0.40): 0.42–1.0
- `zoneWeight` barba (ny>0.66): fade até 0.30
- `edgeWeight = (lateral/halfFace)^0.72`

### `FaceMeshForwardWarp` (backward mesh)
- Deforma só `min(landmarkCount, meshVertexCount)` vértices
- Bbox malha deformada + margin 3px
- `_fillLateralDisocclusion`: **DESLIGADO** (causava 1938 px flat bg)
  - `_lateralNormMin = 0.38`
  - `_personOuterMax = 0.52`
  - `_lateralInfluenceMin = 0.05`

### `FaceSlimWarp` (path v3_cpu)
- `_lateralNormMin = 0.38`
- `_personOuterMax = 0.54`
- `_maxBgDistancePx = 36`
- `inwardBlend = 0.22` no composite
- `postProcess` **pulado** quando `backend == 'mesh'`

### `WarpFieldBuilder.forFaceSlimInteractive`
- Grade 160–192 (~4 px/célula)
- `outerRingPx = 10`

### `PassWarp`
- `allowGpuFaceSlimPreview = false` (GPU desligado preview face_slim)

---

## 5. Como debugar manualmente

### 5.1 Toggles rápidos (`face_warp_v3_config.dart`)

```dart
FaceWarpV3Config.useForwardMeshWarpFaceSlim = true;  // v3_mesh (atual)
FaceWarpV3Config.useForwardMeshWarpFaceSlim = false; // cai em v3_cpu (WarpCpuRemap + FaceSlimWarp)
FaceWarpV3Config.useLegacyFaceMls = true;            // MLS legado
FaceWarpV3Config.useGpuPiecewiseAffine = true;       // + allowGpuFaceSlimPreview em pass_warp.dart
```

### 5.2 Badge no overlay
| Badge | Caminho |
|-------|---------|
| `V3_MESH` | FaceMeshForwardWarp.apply |
| `V3_CPU` | WarpCpuRemap + FaceSlimWarp |
| `V3_GPU` | FragmentProgramFaceMeshBackend |
| `V3` / `V3_DIRECT` | Rasterizer direto |
| `MLS` | Legado |

### 5.3 Logs debug (instrumentação ativa)
- **Arquivo:** `.cursor/debug-13c8af.log` (NDJSON)
- **Writer:** `lib/features/editor/beauty_engine/debug/agent_debug_log.dart`
- **Hipóteses:** `B0` path mesh, `B2` mesh backward stats, `D1` vac composite (path cpu), `G1/G2` GPU

Exemplo linha B2:
```json
{"hypothesisId":"B2","data":{"meshHitPx":164526,"holeFillPx":1938,"peakDisp":31.38,"vertexCount":468,"landmarkCount":478}}
```

### 5.4 Comandos úteis

```bash
# Teste integração face_slim
flutter test test/beauty_engine/warp/face_v3_cpu_remap_integration_test.dart

# Golden face_slim
flutter test test/golden/face_warp_v3_pilot_golden_test.dart --update-goldens

# Analisar arquivo crítico
dart analyze lib/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart
```

### 5.5 Hipóteses abertas (prioridade)

| # | Hipótese | Onde investigar |
|---|----------|-----------------|
| H1 | Hole fill / vac composite pinta bochecha com bg flat | `face_mesh_forward_warp.dart` `_fillLateralDisocclusion`, `face_slim_warp.dart` `_applyVacancyComposite` |
| H2 | 478 vs 468 vértices — íris (468–477) sem malha | `face_mesh_builder.dart`, ACE displacementAt > 467 |
| H3 | TriMeshSpatialIndex retorna triângulo errado em overlap | `tri_mesh_spatial_index.dart` — falta depth sort |
| H4 | Malha lateral fina demais → discontinuidade | `face_mesh_topology.generated.dart` triângulos contorno |
| H5 | GPU piecewise (export) pode ser melhor que CPU mesh | `face_mesh_piecewise.frag`, habilitar preview GPU |
| H6 | Seamless clone pós-warp (estilo FaceSlim OSS) | novo pass ou OpenCV Poisson — não implementado |

### 5.6 Referências externas
- [SysAdminDoc/FaceSlim](https://github.com/SysAdminDoc/FaceSlim) — TPS + ROI + seamless clone
- [facestudio](https://github.com/georgegach/facestudio) — WebGL2 piecewise-affine client-side
- OpenCV `seamlessClone` / remap — preenchimento de disocclusão

---

## 6. Estado do código nesta sessão (diff relevante)

| Arquivo | Mudança |
|---------|---------|
| `face_mesh_forward_warp.dart` | Forward splat → backward mesh; safe vertex count; hole fill off |
| `pass_warp.dart` | Path mesh sem FaceSlimWarp.postProcess |
| `face_slim_warp.dart` | postProcess skip se `backend == 'mesh'` |
| `beauty_engine_controller.dart` | Badge `v3_mesh` |
| `face_warp_v3_config.dart` | Comentário atualizado |

---

## 7. Próximos passos sugeridos

1. **Testar com hole fill off** — ver se blocos somem (só fantasma lateral residual).
2. Se fantasma lateral: usar `FaceWarpHoleFill.imputeFromGhostMask` (NN vizinho) em vez de bg flat outward.
3. Considerar **seamless clone** na faixa lateral (Opção A do plano original).
4. Habilitar **GPU piecewise preview** para comparar qualidade vs CPU mesh.
5. Unificar 478→468: garantir que ACE não desloca índices 468–477 ou expandir malha.

---

## 8. Sugestões implementadas (2026-08-10)

| Sugestão | Status | Onde |
|----------|--------|------|
| Warp triangular direto (`directMesh`) em preview/export | ✅ | `face_mesh_deformation_engine.dart` — `directMesh = useDirectMeshRender \|\| gpuPiecewise` |
| Remover blur/spread de grade para face_slim | ✅ | `face_mesh_warp_rasterizer.dart` — `skipGridHeuristics` quando directMesh ou mesh backward |
| ACE mais rígido (nariz, olhos, boca, sobrancelha, testa, queixo) | ✅ | `face_model_specification.dart` — `face_slim.rigidZones` expandido |
| VacancyFill só olhos/lábios; face_slim sem vacancy na grade | ✅ | `face_warp_vacancy_fill.dart` — `vacancySourceIndices()` |
| Testes regressão B1 (nariz, olhos, simetria mandíbula) | ✅ | `test/beauty_engine/warp/face_slim_quality_regression_test.dart` |
| GPU piecewise preview face_slim | ⏸ Pendente | Manter `V3_MESH` (CPU backward) até qualidade OK; toggle em `pass_warp.dart` |
| Laplaciano/ARAP na malha | ⏸ Pendente | Substituir `_spreadDisplacement` por smooth mesh-side no ACE |
| Seamless clone lateral | ⏸ Pendente | Opção A — ver H6 |

### Comando regressão B1

```bash
flutter test test/beauty_engine/warp/face_slim_quality_regression_test.dart
flutter test test/beauty_engine/warp/face_warp_v3_pilot_test.dart
```

---
