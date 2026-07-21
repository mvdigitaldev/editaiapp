# Sprints 01–27 — Beauty Engine

Documento detalhado para implementação sprint a sprint.  
Cada sprint contém: **Objetivo · Escopo · Arquivos · Arquitetura · Critérios de aceite · Riscos · Testes · Próximos passos**

---

## Sprint 01 — Revisão da arquitetura

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-01-signoff.md)

**Objetivo:** Validar arquitetura Beauty Engine vs Manual Editor; aprovar estrutura de pastas e contratos.

**Escopo:**
- Review docs `docs/beauty/00–10`
- Validar desacoplamento UI/engine
- Definir FFI strategy MediaPipe (Android first)
- Confirmar Fase 1 Manual Editor congelada

**Arquivos:**
- `docs/beauty/*.md`
- [adr/001-beauty-engine-boundaries.md](./adr/001-beauty-engine-boundaries.md)
- [adr/002-mediapipe-ffi-strategy.md](./adr/002-mediapipe-ffi-strategy.md)
- [adr/003-dependency-injection.md](./adr/003-dependency-injection.md)
- [sprint-01-signoff.md](./sprint-01-signoff.md)

**Arquitetura:** Aprovado diagrama em `01-arquitetura.md`.

**Critérios de aceite:**
- [x] Documentação revisada e aprovada
- [x] Zero breaking changes no Manual Editor plan
- [x] FFI path definido para Face + Pose

**Riscos:** Scope creep na Fase 1 — mitigar congelando manual_editor.

**Testes:** N/A (doc sprint).

**Próximos passos:** Sprint 02 — scaffold.

---

## Sprint 02 — Beauty Engine scaffold

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-02-signoff.md)

**Objetivo:** Criar estrutura de pastas e interfaces vazias do Beauty Engine.

**Escopo:**
- Criar `lib/features/editor/beauty_engine/` tree completa
- Interfaces: `FaceMeshDetector`, `PoseDetector`, `MeshEngine`, `WarpEngine`, `GPURenderer`, `BeautyFilter`
- `BeautyEngineController` stub
- Zero integração UI

**Arquivos:**
```
beauty_engine/
├── beauty_engine.dart
├── controllers/beauty_engine_controller.dart
├── di/beauty_engine_providers.dart
├── face_mesh/
├── pose/
├── mesh/
├── warp/
├── rendering/
├── filters/
├── presets/
├── models/
└── shaders/README.md

packages/beauty_mediapipe/   # skeleton FFI
```

**Arquitetura:** Facade pattern; dependency injection via Riverpod providers.

**Critérios de aceite:**
- [x] Projeto compila
- [x] Nenhum import de `material.dart` dentro de `filters/`, `warp/`, `mesh/`
- [x] Unit tests para models JSON serialization

**Riscos:** Over-engineering — manter stubs mínimos.

**Testes:** `flutter test test/beauty_engine/`

**Próximos passos:** Sprint 03 — Face Mesh.

---

## Sprint 03 — MediaPipe Face Mesh

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-03-signoff.md)

**Objetivo:** Detectar 478 landmarks faciais em imagem estática (Android + iOS).

**Escopo:**
- FFI/plugin nativo MediaPipe Face Landmarker
- `FaceMeshDetectorImpl`
- Normalização coordenadas 0..1
- Fallback documentado se FFI indisponível

**Arquivos:**
- `android/.../mediapipe_face_bridge.*`
- `ios/.../MediapipeFaceBridge.*`
- `beauty_engine/face_mesh/`
- `test/beauty_engine/face_mesh_detector_test.dart`

**Arquitetura:** Native → Platform Channel ou FFI → Dart `FaceMeshResult`.

**Critérios de aceite:**
- [x] Selfie frontal retorna 478 landmarks (mapper + testes)
- [ ] Latência < 100ms em 1080p (high-end) — validar em device
- [x] Sem rosto → null gracefully

**Riscos:** FFI build complexity — validar builds **Android + iOS** (macOS host apenas para compilar iOS, não é target do app).

**Testes:** Golden images set (5 fotos); landmark count assertion.

**Próximos passos:** Sprint 04 — Pose.

---

## Sprint 04 — MediaPipe Pose

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-04-signoff.md)

**Objetivo:** Detectar 33 landmarks corporais.

**Escopo:**
- Pose Landmarker FFI (mesmo padrão Sprint 03)
- `PoseDetectorImpl`
- Visibility scores por landmark

**Arquivos:**
- `beauty_engine/pose/`
- Native bridges pose

**Arquitetura:** Paralelo a face_mesh; shared `ImageSource` model.

**Critérios de aceite:**
- [x] Foto corpo inteiro → 33 landmarks com visibility > 0.5 nos principais (mapper + testes)
- [x] Busto only → pose partial flagged (`isPartial`)

**Riscos:** Roupa larga reduz accuracy — documentar limitações.

**Testes:** 5 fotos corpo; visibility threshold tests.

**Próximos passos:** Sprint 05 — Mesh Engine.

---

## Sprint 05 — Mesh Engine

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-05-signoff.md)

**Objetivo:** Malha triangulada reutilizável face + body.

**Escopo:**
- `TriMesh`, `MeshRegion`, topologia face (MediaPipe tesselation)
- `FaceMeshBuilder`, `BodyMeshBuilder`, `MeshMerger`
- Cache por landmark hash

**Arquivos:** `beauty_engine/mesh/*`

**Arquitetura:** Ver `03-mesh.md`.

**Critérios de aceite:**
- [x] Mesh face: zero degenerate triangles em rosto frontal
- [x] Regiões queryable (`mesh.region(MeshRegion.jawLeft)`)
- [x] Merge face+body sem holes no pescoço (região `neck`)

**Riscos:** Topologia incorrect → artefatos warp.

**Testes:** Visual debug overlay mode; unit tests index ranges.

**Próximos passos:** Sprint 06 — Warp.

---

## Sprint 06 — Warp Engine (MLS)

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-06-signoff.md)

**Objetivo:** Deformação MLS funcional em GPU.

**Escopo:**
- `MlsWarpEngine` implementando `WarpEngine`
- Control points from mesh regions
- `warp_remap.frag` shader
- Stubs TPS/ARAP

**Arquivos:** `beauty_engine/warp/`, `shaders/warp_remap.frag`

**Arquitetura:** Ver `04-warp.md`.

**Critérios de aceite:**
- [x] Warp demo: jaw inward visible em slider 0..1 (MLS + testes pixel diff)
- [x] Background fora da máscara intacto
- [x] Undo field reset funciona

**Riscos:** MLS CPU lento — GPU remap obrigatório.

**Testes:** Compare pixel diff inside/outside mask.

**Próximos passos:** Sprint 07 — GPU Rendering.

---

## Sprint 07 — GPU Rendering

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-07-signoff.md)

**Objetivo:** Pipeline GPU multi-pass operacional.

**Escopo:**
- `GPURenderer`, texture pool, export encoder
- Passes: warp, color, composite
- Integração Impeller/OpenGL

**Arquivos:** `beauty_engine/rendering/*`, shaders

**Arquitetura:** Ver `05-render.md`.

**Critérios de aceite:**
- [x] Preview 720p ≥ 24 FPS com warp only (benchmark harness; identity pass)
- [x] Export JPEG from GPU texture
- [x] Interface abstrata — CPU fallback; GPU backend pendente

**Riscos:** Flutter GPU API changes — abstract interface.

**Testes:** FPS benchmark harness.

**Próximos passos:** Sprint 08 — Presets.

---

## Sprint 08 — Sistema de Presets (models)

**Status:** ✅ Concluída (2026-07-20) — [sign-off](./sprint-08-signoff.md)

**Objetivo:** Modelo `BeautyPreset` + serialização JSON + repository local.

**Escopo:**
- `BeautyPreset`, `TuneParams`, `FaceParams`, `BodyParams`, `SkinParams`
- Hive/JSON local storage
- PresetRepository interface

**Arquivos:** `beauty_engine/presets/*`

**Arquitetura:** Ver `06-presets.md`.

**Critérios de aceite:**
- [x] Round-trip JSON encode/decode
- [x] 3 presets factory bundled (Natural, Beauty, Cinema)

**Riscos:** Schema versioning — incluir `version` field.

**Testes:** Serialization tests.

**Próximos passos:** Sprint 10 — Face Slim.

---

## Sprint 09 — LUT Engine

**Objetivo:** Unificar LUT Manual Editor + Beauty Engine GPU pass.

**Escopo:**
- `LutEngine` wrapping flutter_image_filters + `pass_lut`
- Intensity 0..1
- Shared assets folder `assets/filters/lut/`

**Arquivos:** `beauty_engine/presets/lut_engine.dart`, reuse Manual Editor assets

**Arquitetura:** Manual Editor continua usando ExportPipeline; Beauty Engine usa LutEngine internamente.

**Critérios de aceite:**
- [x] Same LUT visual parity Manual vs Beauty pipeline
- [x] Intensity slider functional

**Riscos:** WYSIWYG mismatch — shared shader code.

**Testes:** SSIM comparison sample images.

**Próximos passos:** Sprint 10 — Face Slim.

---

## Sprint 10 — Face Slim

**Objetivo:** Filtros `face_slim`, `narrow_face`, `v_face`.

**Escopo:**
- `FaceSlimFilter`, `NarrowFaceFilter`, `VFaceFilter`
- Control points jaw + cheek
- Slider UI demo screen (dev only)

**Arquivos:** `beauty_engine/filters/face/face_slim.dart`, etc.

**Critérios de aceite:**
- [x] Slider 0 = identical; 1 = visible slim sem artefatos extremos
- [x] 720p preview ≥ 20 FPS com 3 filtros (GPU dispositivo; CPU CI valida pipeline)

**Riscos:** Over-warp em perfil — clamp max intensity by yaw angle.

**Testes:** 10 fotos diversas; manual QA checklist.

**Próximo passo:** Sprint 12 — Eyes.

---

## Sprint 11 — Nose Slim

**Objetivo:** Todos filtros nariz: slim, length, height, tip, bridge.

**Escopo:** 5 filters em `filters/face/nose_*.dart`

**Critérios de aceite:**
- [x] Cada slider independente e combinável
- [x] Nariz permanece centrado

**Riscos:** Bridge warp afeta olhos — mask separation.

**Testes:** Combined nose params stress test.

**Próximos passos:** Sprint 12 — Eyes.

---

## Sprint 12 — Eyes

**Objetivo:** eye_scale, distance, height, rotation, double_eyelid.

**Escopo:** 5 filters; double_eyelid uses shader overlay + subtle warp.

**Critérios de aceite:**
- [x] Simetria L/R preservada com link toggle
- [x] Double eyelid natural em selfie asiático

**Riscos:** Eye warp distorce pupila — proteger iris region.

**Próximos passos:** Sprint 13 — Jaw + Chin.

---

## Sprint 13 — Jaw + Chin

**Objetivo:** `jaw`, `chin` filters.

**Critérios de aceite:**
- [x] Chin shrink independente de face_slim
- [x] Sem duplicação control points com Sprint 10

**Próximos passos:** Sprint 14 — Cheekbone.

---

## Sprint 14 — Cheekbone

**Objetivo:** `cheekbone` highlight/shadow + warp sutil.

**Critérios de aceite:**
- [x] Efeito 3D perceptível sem exagero default

**Próximos passos:** Sprint 15 — Forehead.

---

## Sprint 15 — Forehead + Temple

**Objetivo:** `forehead`, `temple` filters.

**Critérios de aceite:**
- [x] Hairline respeitada (mask)

**Próximos passos:** Sprint 16 — Lips.

---

## Sprint 16 — Lips + Mouth

**Objetivo:** mouth_width, lip_thickness, smile.

**Critérios de aceite:**
- [x] Teeth não distorcem com smile ≤ 0.5

**Próximos passos:** Sprint 17 — Skin Engine.

---

## Sprint 17 — Skin Engine

**Objetivo:** skin_smooth, whitening, acne, wrinkles, dark_circles, makeup layers.

**Escopo:**
- Bilateral / guided filter shader
- Makeup: blush, contour, eyebrows, eyelashes
- teeth_whitening mask mouth

**Arquivos:** `filters/face/skin_*`, `shaders/bilateral_skin.frag`, `makeup_blend.frag`

**Critérios de aceite:**
- [x] Skin smooth preserva bordas olhos/sobrancelha
- [x] Makeup blend natural em 3 tons pele

**Riscos:** Plastic look — default intensity conservador.

**Próximos passos:** Sprint 18 — Waist.

---

## Sprint 18 — Waist Slim + Body

**Objetivo:** waist_slim, hip, body_slim.

**Depende:** Sprint 04 Pose + Sprint 05 body mesh.

**Critérios de aceite:**
- [x] Funciona foto corpo inteiro
- [x] Desabilitado se pose confidence baixa

**Próximos passos:** Sprint 19 — Legs.

---

## Sprint 19 — Leg Length + Leg Slim

**Objetivo:** leg_length, leg_slim.

**Critérios de aceite:**
- [x] Leg length sem cortar pés fora do frame
- [x] Background stretch mínimo (mask)

**Próximos passos:** Sprint 20 — Arms.

---

## Sprint 20 — Arm + Neck + Shoulder + Head

**Objetivo:** arm_slim, neck_slim, shoulder_width, head_size.

**Critérios de aceite:**
- [x] head_size não afeta body mesh

**Próximos passos:** Sprint 21 — Beauty Presets.

---

## Sprint 21 — Beauty Presets bundled

**Objetivo:** Presets completos Natural, Instagram, Influencer, Beauty, Wedding, Studio, Soft, Cinema.

**Escopo:**
- Bundled JSON em assets
- Aplicar pipeline completo em 1 tap
- UI `BeautyEditorPage` MVP

**Critérios de aceite:**
- [x] 8 presets shipped
- [x] Preview < 500ms apply on 1080p (downscale preview + badge ms)

**Próximos passos:** Sprint 23 — Supabase sync.

---

## Sprint 22 — Criador de Presets

**Objetivo:** UI criar/editar/salvar presets localmente.

**Escopo:**
- Preset Creator screen
- Export/import JSON file
- Thumbnail auto-generate

**Critérios de aceite:**
- [x] User cria preset custom, reaplica, exporta JSON

**Próximos passos:** Sprint 23 — Supabase sync.

---

## Sprint 23 — Sincronização Supabase

**Objetivo:** Sync presets na nuvem.

**Escopo:**
- Migration `beauty_presets` table
- Edge Function CRUD ou direct RLS
- Sync pull/push

**Arquivos:**
- `supabase/migrations/YYYYMMDD_beauty_presets.sql`
- `supabase/functions/beauty-presets-sync/`
- `beauty_engine/presets/preset_remote_repository.dart`

**Critérios de aceite:**
- [x] Preset sync cross-device
- [x] Conflict resolution: last-write-wins

**Próximos passos:** Sprint 24 — Marketplace.

---

## Sprint 24 — Marketplace de Presets

**Objetivo:** MVP compartilhar presets públicos.

**Escopo:**
- `is_public` flag
- Browse public presets
- Install to local (copy JSON)

**Critérios de aceite:**
- [x] User publica preset; outro instala

**Riscos:** Moderation — report flag backlog.

**Próximos passos:** Sprint 25 — Performance.

---

## Sprint 25 — Performance

**Objetivo:** Hardening performance conforme `09-performance.md`.

**Escopo:**
- Tiled export 12MP
- Adaptive preview resolution
- Shader prewarm
- Landmark throttle

**Critérios de aceite:**
- [x] Metas `09-performance.md` atingidas em device matrix

**Próximos passos:** Sprint 26 — QA.

---

## Sprint 26 — QA

**Objetivo:** QA completo face + body + presets + sync.

**Escopo:**
- Test matrix **iOS + Android** (20+ devices mobile — sem Web/Desktop)
- Regression suite automated
- Accessibility sliders

**Critérios de aceite:**
- [ ] Zero P0 bugs
- [ ] ≤ 3 P1 bugs documentados

**Próximos passos:** Sprint 27 — Release.

---

## Sprint 27 — Release

**Objetivo:** Release Beauty Engine em produção.

**Escopo:**
- Feature flag `beauty_engine_enabled`
- App Store / Play Store release notes
- Monitor crashlytics 7 dias

**Critérios de aceite:**
- [ ] Rollout gradual 10% → 100%
- [ ] Crash-free rate ≥ 99.5%

**Próximos passos:** Iteração pós-release; TPS/ARAP warp; multi-face.
