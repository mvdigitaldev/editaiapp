# Estado atual da arquitetura — Beauty Engine e edição facial

> **17 ago 2026 — sucessor para planeamento:** [`31-sistema-facial-atual.md`](./31-sistema-facial-atual.md).  
> A H-Architecture foi **descartada** (código e testes apagados). Este ficheiro 30 permanece como arquivo da pesquisa A–G1.1 e do estado anterior.

**Data:** 17 de agosto de 2026  
**Escopo:** documento de leitura para um especialista externo. Não contém propostas, correções nem código novo.  
**Fonte:** código em `lib/features/editor/beauty_engine/`, relatórios em `.cursor/chin-mesh-field/`, ADRs em `docs/beauty/adr/`, plano H0 em `.cursor/plans/etapa_h0_target_field_501b30c4.plan.md`.

O **Beauty Engine** é o motor de retoque facial/corporal (sliders de queixo, mandíbula, afinar rosto, etc.). A tela em uso é `/face-retouch` (`BeautyEditorPage`). Os problemas abertos **agora** estão na ferramenta `chin` desse editor.

---

# 1. Objetivo

## 1.1 O que o SDK é

O **Beauty Engine** é um motor de edição facial e corporal open source, desacoplado da UI Flutter, destinado a substituir SDKs comerciais (Tencent, Banuba, FaceUnity, IMG.LY) no Editai. O app é nativo **somente iOS e Android**.

O motor expõe processamento de imagem estática (foto). Tempo real de câmera está no backlog (`processStream`), não está no produto.

## 1.2 O que ele faz hoje

1. Detecta um rosto (478 landmarks MediaPipe, dos quais 468 entram na tessellation e 10 são íris 468–477).
2. Detecta pose (33 landmarks) e silhueta (selfie segmenter / parsing).
3. Constrói uma malha triangular facial canônica (topologia MediaPipe).
4. Converte sliders 0..1 em um campo de deslocamento por vértice (`ConstrainedVertexField`).
5. Aplica constraints anatômicas (ACE) e um pipeline estrutural de jacobiano (Phase 9 + Safety Gate).
6. Rasteriza o warp (malha backward / GPU piecewise-affine / grade MLS legada).
7. Compõe passes de pele, LUT, makeup e export JPEG.

Há um segundo motor de **Body Reshape V2** (malha adaptativa + mapas de proteção de fundo), paralelo ao warp facial.

## 1.3 Tipos de deformação que o produto pretende suportar

**Face (warp geométrico), 22 ferramentas registradas em `FaceFilterPipeline`:**

| Família | IDs |
|---|---|
| Contorno / volume | `face_slim`, `narrow_face`, `v_face`, `jaw`, `chin`, `cheekbone`, `forehead`, `temple`, `head_size` |
| Nariz | `nose_slim`, `nose_length`, `nose_height`, `nose_tip`, `nose_bridge` |
| Olhos | `eye_scale`, `eye_distance`, `eye_height`, `eye_rotation`, `double_eyelid` |
| Boca | `lip_thickness`, `mouth_width`, `smile` |

Menu MVP Fase 15 (UI): `face_slim`, `narrow_face`, `v_face`, `jaw`, `chin`, `cheekbone`, `forehead`. Têmporas e `head_size` existem no código e foram retirados do menu.

**Pele / cor / makeup (shader, não warp):** `skin_smooth`, whitening, acne, wrinkles, dark circles, makeup layers (blush, contour, lips, etc.).

**Corpo:** `waist_slim`, `hip`, `leg_length`, `leg_slim`, `arm_slim`, `neck_slim`, `shoulder_width`, `body_slim`, mais estratégias V2 (peito, glúteo, barriga, altura).

**Algoritmos declarados na interface `WarpAlgorithm`:** `mls`, `thinPlateSpline`, `arap`, `meshWarp`. Em produção facial V3 o caminho ativo não é mais MLS por pixel: é deslocamento por vértice da malha MediaPipe + ACE + Phase 9. TPS e ARAP de produto estão como stub na factory. ARAP/LIM existem só em diagnósticos experimentais de queixo (G1 / G1.1), fora de produção.

## 1.4 Pipeline completo (produção facial V3)

```
Foto (RGBA / JPEG)
        ↓
MediaPipe Face Landmarker (packages/beauty_mediapipe)
        ↓
478 landmarks normalizados (FaceMeshResult)
        ↓
FaceMeshBuilder + topologia canônica (468 verts, triângulos MediaPipe)
        ↓
TriMesh (vértices em px, UVs 0..1, índices)
        ↓
Sliders (Map<String,double>) → AnatomicalIntentFactory
        ↓
PilotWarpDisplacement / PilotWarpContourNose  (delta por vértice, intenção)
        ↓
Anatomical Constraint Engine (pins, clamp FSE, anti-fold local, boca rigid)
        ↓
ConstrainedVertexField
        ↓
FaceWarpStructuralPipeline
   displacement → GlobalJacobianConstraint (ε=0.10) → GlobalJacobianSafetyGate
        ↓
Matte / influence map (FaceMatteRoi ± person mask)
        ↓
Rasterização
   • MVP contour (face_slim etc.): FaceMeshForwardWarp (backward por triângulo destino)
   • GPU: face_mesh_piecewise.frag / backend nativo Metal-GLES
   • Fallback: grade WarpField + remap (body_reshape_remap.frag ou CPU)
        ↓
Passes: skin → LUT → makeup → (inpaint pós-warp opcional)
        ↓
Preview RGBA (RawImage)  ou  export JPEG
```

Rollback explícito: `FaceWarpV3Config.useLegacyFaceMls = true` devolve o caminho MLS+grade (`FaceFilterPipeline.compose` + `MlsSolver`).

---

# 2. Arquitetura

## 2.1 Camadas do app

```
lib/
├── core/                 infraestrutura (config, theme, network, storage)
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── gallery/
│   ├── home/
│   ├── profile/
│   ├── subscription/
│   ├── support/
│   └── editor/
│       ├── beauty_engine/     motor de retoque (este documento)
│       ├── filter_presets/
│       └── presentation/      páginas IA, comparison, collage
└── packages/beauty_mediapipe/ plugin nativo Face/Pose/segmentação
```

## 2.2 Pipeline facial, etapa a etapa

### Imagem

Entrada é foto estática. Decode para RGBA. Preview interativo **não** reencoda JPEG a cada slider (`renderPreview` → `readPixels` → `RawImage`). Export usa JPEG full-res, com tiles se necessário.

### MediaPipe

Plugin local `beauty_mediapipe`: MethodChannel (não FFI puro como o ADR 002 original descrevia). Android: MediaPipe Tasks AAR + JNI. iOS: CocoaPods MediaPipeTasksVision. Modelos em `assets/mediapipe/`:

- `face_landmarker.task` — 478 pontos
- `pose_landmarker_lite.task` — 33 pontos
- `selfie_segmenter.tflite` / `selfie_multiclass_256x256.tflite` — máscara de pessoa

Emulador Android x86 não carrega o JNI; exige device ARM64.

### Landmarks

`FaceMeshResult.expectedLandmarkCount = 478`. Coordenadas normalizadas 0..1 + z. `FaceLandmarkMapper` rejeita contagem diferente. Íris 468–477 existem no resultado; a tessellation usada no warp tem `FaceMeshTopology.landmarkCount = 468`.

### Triangulação

Não há Delaunay em runtime para o rosto. A conectividade é a tessellation canônica MediaPipe gerada em `face_mesh_topology.generated.dart`. `MeshUtils.filterDegenerateTriangles` remove triângulos degenerados. A malha 2D projetada **não é sempre star-shaped**; D1 mediu anéis 1-hop com orientação mista (evidência para cotangente negativa).

### Mesh

`MeshEngineImpl.buildFaceMesh` cacheia por hash quantizado dos landmarks. `TriMesh`: `vertices` (x,y px), `uvs`, `indices`, `regionBuffers` por `MeshRegion`. Body tem malha legada 33-pose **e** malha adaptativa V2 (`AdaptiveMeshGenerator`) para Body Reshape.

### Construção do target field (produção)

O campo **não** nasce de MLS no caminho V3. Nasce de geradores por ferramenta:

- `AnatomicalIntentFactory.build` — slider → `AnatomicalIntent` (easeOutCubic, modo `pilot` para as 22 tools).
- `PilotWarpDisplacement` / `PilotWarpContourNose` — para cada vértice, um `Offset` (ex.: `_chin`).
- ACE combina intents (prioridade / aditivo no MVP), aplica pins rigid, clamp `|Δv| ≤ dMax × FSE × effective`, anti-fold por área de triângulo < 35%, pin final de `oralCavity`.
- Phase 9 aplica escalas globais de vértice para tentar `det(J) ≥ 0.10`. Se o Safety Gate falhar, o campo **volta ao displacement original** (pré-constraint).

Unidade: fração de **FSE** (face short edge em pixels).

### Warp

Para cada pixel no espaço de destino, o renderer localiza o triângulo deformado, interpola baricêntrica, amostra a textura na posição origem correspondente (backward piecewise-affine). Influence map zera fundo. Há vacancy fill / ghost mask / inpaint para ferramentas laterais (`face_slim` etc.), não como núcleo do `chin`.

### Imagem final

Preview: RGBA. Export: JPEG, opcionalmente via backend nativo piecewise (Sprint 39) ou tiled CPU.

## 2.3 Dois caminhos de campo facial coexistentes

| Caminho | Quando | Onde nasce o campo |
|---|---|---|
| V3 malha + ACE | `FaceWarpV3Config.enabled && useMeshWarpV3 && !useLegacyFaceMls` (default em debug) | `PilotWarp*` → ACE → Phase 9 |
| MLS legado | flag de rollback ou V3 off em release remoto | `FaceWarpFilter.buildControlPoints` → `MlsSolver` → grade `WarpField` |

Os diagnósticos de queixo (G0+) medem o caminho V3 com `applyStructuralPipeline: false` (ACE cru, **sem** Phase 9) na coluna `current`.

## 2.4 Body Reshape (paralelo)

```
Foto → person matte → malha adaptativa densa
    → estratégias por região (waist, arm, leg, …)
    → mapas Edge/Line/Rigidity (proteger fundo)
    → WarpField → shader body_reshape_remap.frag
```

Não compartilha o ACE facial. MLS local ainda existe em `local_mls_pass.dart` como passe V2.

---

# 3. Estrutura do projeto

## 3.1 `lib/core/`

Infraestrutura do app: `config`, `constants`, `error`, `navigation`, `network`, `providers`, `services`, `storage`, `theme`, `utils`, `widgets`. Sem lógica de warp.

## 3.2 `lib/features/editor/beauty_engine/`

| Pasta | Responsabilidade |
|---|---|
| `face_mesh/` | detector + mapper 478 pts |
| `pose/` | detector + mapper 33 pts |
| `segment/` | person mask, face parsing, cache |
| `mesh/` | `FaceMeshBuilder`, body builders, cache, topologia gerada |
| `warp/` | motores de deformação, ACE, renderer, diagnósticos, `experimental/` |
| `warp/anatomy/` | spec, ACE, intents, roles, matte, vacancy |
| `warp/experimental/` | Phase 9 congelada + toda a pesquisa de queixo (A–G1.1) |
| `filters/face/` | 22 filtros warp + pele/makeup |
| `filters/body/` | filtros corporais legado MLS |
| `body_reshape/` | motor V2 (malha adaptativa, proteção, passes) |
| `rendering/` | `PassWarp`, GPU renderer, passes skin/LUT/makeup |
| `shaders/` | GLSL: remap corpo, piecewise face, inpaint, makeup |
| `controllers/` | `BeautyEngineController` — orquestração sem Widget |
| `presentation/` | `BeautyEditorPage`, hub, entry, presets UI |
| `config/` | `FaceWarpV3Config` e rollout |
| `di/` | Riverpod providers, MediaPipe init, feature flags |
| `presets/` | LUT engine, bundled presets, sync Supabase |
| `performance/` | isolate, tiles, hot path, device capability |
| `quality/` | parity checklist, métricas de imagem |
| `tools/` | Tool Gate (escala de intensidade por qualidade da foto) |
| `models/` | `TriMesh`, `WarpField`, `FaceMeshResult`, tune params |
| `color/` | color science |
| `l10n/` | labels |
| `debug/` | log de agente |

## 3.3 `packages/beauty_mediapipe/`

Bridge nativa Face Landmarker + Pose + segmentação. Dart: MethodChannel. Não contém warp.

## 3.4 `docs/beauty/`

Visão, ADRs, sprints 01–41, Face Model Spec, Face Warp Engine Fase 15, calibração MVP. Este arquivo é o 30º doc da série.

## 3.5 `.cursor/chin-mesh-field/`

Artefatos de pesquisa de queixo (não são produção):

| Pasta | Etapa |
|---|---|
| `audit/` | A — auditoria de landmarks |
| `harmonic-phi/` | B — φ harmônico |
| `stage-c/` | C — displacement φ × direção |
| `stage-d1/` | D1 — operadores Laplacianos |
| `stage-d2/` … `stage-d4*` | domínio B e gônio |
| `stage-e0/` | E0 — BBW multi-handle |
| `stage-f-domain/` | F — catálogo de Ω |
| `stage-g0/` `stage-g1/` `stage-g11/` | G0 / G1 / G1.1 |
| `stage-h0/` | **não existe** — H0 não foi implementado |

Dataset congelado nas etapas G: `real-p01` (man-5021469), `real-p05` (young-woman), `real-p12` (oval-man), em `test/beauty_engine/warp/fixtures/phase12/`. D4-validation também usou `p06` e `p21`.

## 3.6 Testes

`test/beauty_engine/warp/` contém os harnesses que geram os relatórios acima. Rodar o teste **escreve** PNG/JSON/MD em `.cursor/chin-mesh-field/`. Nenhum desses testes altera produção.

---

# 4. Engine de deformação

## 4.1 Como funciona hoje (produção, ferramenta `chin`)

1. Slider `chin` ∈ [0,1] permanece em `_params` na `BeautyEditorPage` (composição aditiva com outros sliders MVP).
2. `BeautyEngineController.composeFaceField` constrói `TriMesh` e chama `FaceMeshDeformationEngine`.
3. `AnatomicalIntentFactory` emite um `AnatomicalIntent` com `toolKey='chin'`, `magnitude = easeOutCubic(raw)`, `mode=pilot`.
4. ACE pede o gerador `PilotWarpContourNose._chin` para cada índice 0..477.
5. `_chin` devolve delta não-zero se o índice está em `VertexRoleMap.chin` **ou** em `_chinAdjacentJaw = {136, 172, 58, 377, 400, 378}`.
6. Fórmula (produção):

```
t = rawIntensity
lift   = imageHeight * 0.035 * t
narrow = imageWidth  * 0.04  * t
delta  = (sign(centerX - x) * narrow * ratio * narrowFactor,
          -lift * narrowFactor)
adjacent jaw: 0.65 * delta
```

`chinPivot` = landmark 152. `narrowFactor` cresce com distância vertical ao pivot (clamp 0.55..1.0).

7. ACE: clamp `maxDisplacementFse = 0.075`, rigid `lowerLip ∪ oralCavity`, anti-fold 35% área, pin `oralCavity` de novo.
8. Se `applyStructuralPipeline` (produção sim; diagnósticos G0 **não**): Phase 9 ε=0.10 + Safety Gate. FAIL → campo original.
9. Raster backward na malha + influence map.

**Spec de zonas (`face_model_specification.dart`, tool `chin`):**

- primary: `chin`
- free: `chin ∪ jawLeft ∪ jawRight`
- rigid: `lowerLip ∪ oralCavity`
- invariante de qualidade: B4 (`docs/beauty/13-visual-quality-targets.md`) — lábio inferior não estica; mandíbula conecta sem degrau; sem folding no vale queixo–pescoço.

**Conjunto `VertexRoleMap.chin`:** `{152, 175, 199, 200, 17, 18, 148, 176, 149, 150}`.  
Inclui 17 e 18 (próximos da boca / sulco). Não inclui o contorno G0 `{377, 378, 379, 400}` como zona chin — esses entram só via `_chinAdjacentJaw` (377, 400, 378) ou via `jawLeft/jawRight` na spec free (mas o gerador `_chin` **não** itera a spec: itera `VertexRoleMap.chin` + `_chinAdjacentJaw`). 365 e 397 (jaw transition G0) **não** estão em `_chinAdjacentJaw`. 58 (gônio) **está**.

Filtro MLS legado `filters/face/chin.dart` usa outro conjunto: `{152, 175, 199, 200, 18, 313, 421, 428}` como control points móveis + âncoras e estabilizadores de lábio. Esse caminho não é o default V3.

## 4.2 Algoritmos em uso

### Produção

| Algoritmo | Onde |
|---|---|
| Deslocamento heurístico por landmark (pilot) | `PilotWarpContourNose`, `PilotWarpDisplacement` |
| ACE (pins, clamp FSE, anti-fold área) | `anatomical_constraint_engine.dart` |
| Jacobi global de escalas (Phase 9) | `global_jacobian_constraint.dart` — **congelado** |
| Safety Gate Phase 14 | `global_jacobian_safety_gate.dart` |
| Piecewise-affine backward | `FaceMeshForwardWarp` / `FaceWarpRenderer` |
| MLS similarity 2D | `MlsSolver.forward` — caminho legado e G0 experimental |
| GPU remap | `body_reshape_remap.frag`, `face_mesh_piecewise.frag` |

O comentário em `mls_solver.dart` diz “MLS rígido”. A álgebra implementada (acumuladores `a`, `b`, `mu` e a matriz de similaridade) é **similarity MLS, Schaefer 2006 §2.2**, não rigid MLS §2.3. G0 documentou essa distinção. Pesos: `w = 1 / (‖x−p_i‖² + ε)`, `ε=1e-8`.

### Pesquisa de queixo (não produção)

| Algoritmo | Etapa |
|---|---|
| Dijkstra geodésico na malha 2D | A, F, plano H0 |
| Laplaciano uniforme / MVC simetrizado / cotangente clamp≥0 | B, D1 |
| Harmonic φ Dirichlet (T=1, D=0, B=0) | B–D4 |
| BBW geométrico `Q = L M⁻¹ L` + QP active-set | E0 |
| Similarity MLS nos 13 handles + pins orais | G0 |
| Local-global / Gauss-Newton ARAP + barreira LIM + LM, handles hard | G1 |
| Idem, handles soft LIM §3.3/§3.4, `w_soft` único | G1.1 |

## 4.3 Onde nasce o target field

**Produção `chin`:** função `_chin` (heurística de lift/narrow em torno do 152), depois ACE e Phase 9. Não há campo-alvo espacial separado do displacement final.

**G0:** sementes explícitas nos 13 handles; o campo em **todos** os vértices é `MlsSolver.forward(controls, x) − x`. Pins orais são control points com `target = source`.

**G1 / G1.1:** o alvo posicional é `X_MLS = X0 + δ_MLS` (campo G0). G1/G1.1 não constroem um alvo novo; projetam a malha para um conjunto localmente injetivo.

**Harmonic/BBW (B–E0):** o objeto resolvido é um **peso** φ ou pesos de handle, não um vetor-alvo. Displacement diagnóstico = `φ × amplitude × direção do chin`.

**H0 (plano, sem código):** nasceria de sementes G0 + kernels geodésicos compactos + partition of unity + rampa oral. Sem solver.

## 4.4 Como os pesos são calculados

### Produção

Não há φ. Há pesos geométricos locais em `_chin` (`ratio`, `narrowFactor`, 0.65 no jaw adjacente) e pesos de papel no ACE (`semiRigidWeight = 0.5`). Influence map da matte pondera o remap no pixel.

### MLS (`MlsSolver`)

`w_i = 1 / (d² + 1e-8)`, normalizado no cálculo de `p*` / `q*`.

### Harmonic (B–D)

Dirichlet: tip 152 → φ=1; oral D → φ=0; fronteira B → φ=0. Livres resolvidos por CG em `L_ff`. Operador default nas etapas B/C: `uniform_fallback`, porque cotangente clássica tem ~111–119 arestas com peso negativo na malha MediaPipe projetada.

### G1.1

`w_soft` único global, atualizado para dominar o resto da energia (`r_dominance = 1000`, cap `1e16`). Boca hard. Não há pesos separados tip/contour/jaw.

## 4.5 Como acontece o warp (pixel)

Dado `ConstrainedVertexField` (dx, dy por vértice):

1. Vértices destino = origem + delta.
2. Para cada pixel `p` da imagem de saída (ou da ROI):
   - localizar triângulo destino que contém `p` (índice espacial / cell index);
   - coordenadas baricêntricas no destino;
   - posição origem = combinação baricêntrica dos três vértices origem;
   - amostrar RGBA na origem (bilinear).
3. Pixels fora da malha / influence 0 permanecem a fonte.
4. `GeometricSupport` pode ainda modular magnitude no render.
5. Ferramentas laterais: vacancy fill, ghost mask, inpaint (`face_warp_inpaint.frag`).

G0/G1/G1.1 usam o mesmo `FaceMeshForwardWarp.apply` para gerar warps de diagnóstico, com o campo experimental no lugar do ACE.

---

# 5. Histórico técnico

Ordem cronológica da pesquisa de queixo (agosto 2026), depois G0–H0. Nenhuma etapa foi integrada em produção. Todas declaram `declaredWinner: false` / `productionUnchanged: true`.

## 5.1 Etapa A — auditoria de landmarks

Arquivos: `chin_landmark_audit.dart`, `.cursor/chin-mesh-field/audit/anatomy-report.md`.

Pergunta: quem é o tip, quem é oral, quem é fronteira, se a malha conecta tip→jaw.

Achados (3 fotos):

- **T = {152}** apenas. 152 e 175 **não** são co-tip. 175 é submental, mais perto da oral.
- Corredor estreito tip→oral, 5 verts `{175, 199, 200, 377, 396}`, nas 3 fotos. `narrowNeckDetected: true`.
- **D (oral protegida), 43 verts:** lábios + cavidade + cantos + `{18, 313, 421, 428}`.
- **B (Dirichlet 0):** gônio e 1-hop, percentil 95 de geoDist ao tip, fronteira do ROI. 199/200 nunca entram em B nem T.
- Domínio válido, F conexo, tip alcança todos os livres.
- Distâncias (px geodésicos na malha 2D), ordem de grandeza: 152→oral ~50–67; 152→175 ~9–12; 172/397 (jaw) ~125–207; gônio ~150–300.

## 5.2 Etapa B — φ harmônico

Arquivos: `chin_mesh_constrained_field.dart`, `chin_mesh_laplacian.dart`, `harmonic-phi-report.md`.

Pergunta: a malha permite influência contínua tip→contour→jaw sem invadir a boca?

- Cotangente FEM clássica **não** é usável: 111–119 arestas negativas. Fallback `uniform_fallback`.
- φ ∈ [0,1], tip > contour > jaw(F) nas 3 fotos. D=0. CG converge, SPD no livre.
- φ contour ~0.23, φ jaw livre ~0.04, φ175 ~0.42. Hierarquia existe; jaw é pequeno porque 172/397 estão em B (φ=0).

## 5.3 Etapa C — displacement diagnóstico

`current` (produção ACE) vs `harmonic_phi` (φ × amplitude, **sem** `maxDisplacementFse` para favorecer o harmonic).

- Harmonic: boca 0, hierarquia tip≥contour≥jaw, p95 vizinho ~1.3 px.
- Current: boca **~10–18 px** neste harness C (amplitude/medição diferentes das colunas G0), aPad/tip ~8, p95 vizinho ~16–23 px, `mouthProtected: false`.
- Harmonic **não** foi declarado vencedor. Amplitude absoluta do harmonic ficou pequena (~2 px de max) neste setup.

## 5.4 Etapa D1 — operadores

Três Laplacianos: `uniform_fallback`, `mean_value_sym` (Floater MVC nativo assimétrico, simetrizado para CG), `cot_clamp0` (positivo modificado, **não** FEM clássico; `isClassicalCotangentFem: false`; ~23–25% das arestas clampadas).

Todos resolvem φ válido. `cot_clamp0` concentra ainda mais φ no 175 e reduz jaw. Sem vencedor. Sem integração.

## 5.5 Etapas D2–D4 — fronteira B / gônio

- **D2:** 172 e 397 estão em B pela regra `gonion_or_1hop` (vizinhos do gônio 58/288), não porque sejam gônio. Tirá-los de B aumenta φ jaw (0.0417→0.050 uniform p01). 175/199/200 altos são decaimento harmônico esperado (estão 5–15× mais perto do tip que o jaw).
- **D3:** relaxar também 215/435 dá ganho residual de φ jaw (~0.003). Gonion {58,288,132,361} permanece B.
- **D4:** classificação anatômica da fronteira. 172/397 = `mandibular_transition_zeroed` (candidatos a sair de B). Gônio verdadeiro = `true_external_boundary` (permanecer B). Variante D (gônio livre) é **diagnóstica**, não candidata de produção.
- **D4-validation:** B→C→D no displacement diagnóstico, 5 fotos. Pass numérico relativo. Δ B→D máximo ~0.33 px. Jacobiano rest→δ do campo bruto continua negativo (folds no campo sem Phase 9).
- **D4-sensitivity:** diferença B vs D ao longo do pipeline de produção. Após `mesh_final` (Phase 9 + GeometricSupport) resta ~28% da diferença L2. O sinal de gônio livre é comprimido pelo pipeline estrutural.

## 5.6 Etapa E0 — multi-handle BBW

`chin_multi_handle_field.dart` + QP active-set. REST é extensão de engenharia, **não** Jacobson literal.

- Q/H SPD, KKT 0, convergiu.
- Leitura: **resolve_parcialmente**.
- minJ negativo (−3 a −4), 4–17 invertidos @ 100%.
- Domínio usado tinha **|F|=3** (degenerado). Gônio em REST com w=1, δ=0.
- Sem vencedor. Sem integração. E1 (próximo passo BBW) foi **pausado** no G0.

## 5.7 Etapa F — catálogo de Ω

Só domínio, sem BBW/QP.

- **A** INELIGIBLE (`engineeringMinFree`, |F|=3) — é o Ω do E0.
- **C** INELIGIBLE (`forbiddenInvasion` até brow/eye/nose/forehead).
- **B_2hop, B_3hop, B_4hop, D** GEOMETRICALLY_USABLE.
- `|F| ≥ 12` é mínimo operacional de engenharia para rejeitar o Ω degenerado do E0; não é verdade anatômica.

## 5.8 G0 — similarity MLS

**O que é:** 13 handles móveis + pins orais; `MlsSolver.forward` em todos os vértices. Receita de semente (constantes públicas):

```
u = height * 0.035 * t
tip     {152}:              lift=1.00 u, inward=0.015 width
contour {148,149,150,176,377,378,379,400}: lift=0.60 u, inward=0.015 width
jaw     {136,172,365,397}:  lift=0.30 u, inward=0.040 width
observacionais {175,199,200} e gônio {58,288,132,361}: não são handles
```

Hu et al. Facial Reshaping Operator citado só como contexto; **não** está implementado.

**Por que evoluiu a partir de harmonic/BBW:** harmonic/BBW definem suporte/pesos, não um alvo vetorial de “queixo sobe e afina”. G0 testa o interpolante MLS que o próprio `MlsSolver` de produção já contém.

**Por que não fechou o problema:**

| | current (ACE, sem Phase 9) | G0-MLS |
|---|---|---|
| p01 tip px | 19.95 | 37.33 |
| p05 tip | 14.61 | 28.18 |
| p12 tip | 24.41 | 52.42 |
| boca | 0.50–0.66 | **0** |
| minJ | −8.3 / n/a / −8.7 | −0.23 / −3.54 / −4.35 |
| folds | 18 / n/a / 19 | **2 / 7 / 12** |

Leitura visual G0: tip/contour/jaw acompanham, boca protegida, perceptível nas 3, **bolha/pinçamento = não**. Campo MLS **vaza** para temple (~23–31 px), forehead (~23–30), eye (~13–18), nose (~4.5–6.2) — mesma ordem de grandeza do tip. Sem vencedor. E1 pausado. Sem integração.

## 5.9 G1 — projeção injetiva hard-handle

**O que é:** não é um deformador facial novo. É uma projeção corretiva de `δ_MLS` no conjunto localmente injetivo. Local-global / Gauss-Newton: SVD 2×2 com R congelado, energia data + ARAP + barreira LIM, damping Levenberg–Marquardt. Handles e boca **hard**. Grade de α ∈ {0.1,…,1.0}. ε_J = 10⁻³.

**Por que existiu:** G0 tem a intenção nos handles mas folds. A hipótese era “projetar no conjunto injetivo preserva a intenção”.

**Por que falhou como produto (conjunto G1_FAIL):**

| foto | classe | α_max | tip G1 vs G0 | stop |
|---|---|---|---|---|
| p01 | G1_PARTIAL | 0.20 | 7.47 vs 37.33 | `no_feasible_descent_direction_lm=1e7` |
| p05 | G1_PARTIAL | 0.18 | 5.12 vs 28.18 | `handle_snap_infeasible` |
| p12 | G1_FAIL | 0.07 | 3.67 vs 52.42 | `handle_snap_infeasible`, blocker tri 409 (jaw) |

Injetivo (folds=0, minJ>ε) **somente** com α ≪ 1. O campo útil do MLS é cortado. MLS_error no chin p95 ~20–30 px. Não é Hessiana exata do ARAP. Sem E2. Sem integração.

## 5.10 G1.1 — soft-handle

**O que é:** o mesmo local-global do G1, com handles **soft** (LIM §3.3 alvos intermediários `t_i`, §3.4 um `w_soft` global). Boca continua hard. Partida `X0`. `δ_MLS` **não** é reduzido a priori. max 80 iters.

**Por que existiu:** G1 prova que snap hard dos 13 handles a `X_MLS` é infeasible com injetividade. Soft-handle testa se o mesmo solver alcança o alvo com folga.

**Resultado (conjunto G1.1_PARTIAL):**

| foto | classe | tip G1.1 | handles no X_MLS | minJ | folds |
|---|---|---|---|---|---|
| p01 | G1.1_SUCCESS | 37.33 (= G0) | 13/13, erro 0 | 0.0024 | 0 |
| p05 | G1.1_SUCCESS | 28.18 (= G0) | 13/13, erro 0 | 0.0012 | 0 |
| p12 | G1.1_PARTIAL | 47.50 (~91% tip) | fração média 0.89 | ≈ε | 0 |

p01/p05: residual de handle 0, mas `targetFinalReached=false` porque o local-global parou sem direção de descida (LM no teto) ao tentar reduzir data/ARAP/barreira. p12: parou em `max_iters`; sacrifício em 377 e 400; tri 409 continua na zona de risco (o mesmo blocker do G1).

**O que G1.1 não resolveu:** o suporte espacial continua o do MLS. Temple/forehead/eye ainda se movem (G1.1 herda via `E_data`). G1.1 não é um deformador localizado. Sem vencedor. Sem integração. G0/G1/`MlsSolver`/produção intocados.

## 5.11 H0 — localized target field

**Estado:** plano escrito (17 ago 2026, ~00:15–00:40). **Zero arquivos de implementação.** Não há `chin_localized_target_field.dart`, nem diagnostic, nem `stage-h0/`, nem teste.

**Motivo declarado no plano:** G0 acerta handles e espalha o campo; G1/G1.1 mostram que o solver de injetividade **não localiza** — ele preserva detalhe/injetividade no suporte que recebeu. Harmonic/BBW definiram domínio/BCs, não o alvo. Hipótese: o alvo espacial ainda não foi construído.

H0, se implementado, **não** seria deformador nem solver: construção determinística `deltaTarget[v]` por geodésica + sementes G0 + PoU + rampa oral. Sem MLS na construção, sem ARAP/LIM/Phase 9. Gates quantitativos de leak (L1/L2), continuidade, intenção na ROI, proteção eye/nose/forehead/ear, boca 0, PoU=1.

Todo da implementação no plano: `pending`. Autorização de código **não** foi dada neste documento.

---

# 6. Arquivos importantes

## 6.1 Produção — orquestração e campo

| Arquivo | Responsabilidade | Funções principais | Dependências | Quem usa |
|---|---|---|---|---|
| `controllers/beauty_engine_controller.dart` | Orquestra detecção, campo, preview, export | `composeFaceField`, `renderPreview`, `exportJpeg` | MeshEngine, FaceMeshDeformationEngine, pipelines, GPU | `BeautyEditorPage`, tiled export, isolate |
| `warp/anatomy/face_mesh_deformation_engine.dart` | Intents → ACE → Phase 9 → WarpField/GPU payload | `composeVertexField`, `composeWarpField`, `composeGpuPayload` | ACE, IntentFactory, StructuralPipeline, Rasterizer | Controller |
| `warp/anatomy/anatomical_intent_factory.dart` | Sliders → intents | `build`, easeOutCubic | FaceFilterPipeline keys, FaceModelSpecification | DeformationEngine |
| `warp/anatomy/anatomical_constraint_engine.dart` | Constraints anatômicas | `compose`, `_applyIntent`, `_clampBySpec`, `_antiFold` | spec, VertexRoleMap, PilotWarp* | DeformationEngine |
| `warp/anatomy/pilot_warp_contour_nose.dart` | Geradores de delta contorno/nariz | `_chin`, `_jaw`, `_vFace`, `_cheekbone`, `_forehead`, … | VertexRoleMap, FaceWarpUtils | ACE via PilotWarpDisplacement |
| `warp/anatomy/pilot_warp_displacement.dart` | Roteamento pilot das 22 tools | `displacementFor` | contour_nose, filtros olhos/boca | ACE |
| `warp/anatomy/face_model_specification.dart` | Zonas, dMax FSE, rigid/free por tool | `forKey` | AnatomicalZone | ACE, MVP operations, H0 (leitura) |
| `warp/anatomy/vertex_role_map.dart` | Landmark → zona / papel | conjuntos estáticos | MeshTopology, FaceWarpUtils | ACE, `_chin`, diagnósticos |
| `warp/face_warp_structural_pipeline.dart` | Phase 9 + Safety Gate obrigatórios V3 | `apply` | global_jacobian_* , numeric contract | DeformationEngine |
| `warp/experimental/global_jacobian_constraint.dart` | Jacobi de escalas, ε=0.10 | `apply` | triangle_jacobian_math | StructuralPipeline **e** diagnósticos. Matemática **congelada** |
| `warp/experimental/global_jacobian_safety_gate.dart` | Aceita/rejeita Phase 9 | `validate` | constraint, numeric contract | StructuralPipeline |
| `config/face_warp_v3_config.dart` | Flags V3 / rollback MLS | `enabled`, `useMeshWarpV3`, `useLegacyFaceMls`, … | rollout remoto | Controller, PassWarp |

## 6.2 Produção — malha, MLS, render

| Arquivo | Responsabilidade | Funções principais | Dependências | Quem usa |
|---|---|---|---|---|
| `mesh/face_mesh_builder.dart` | 478 pts → TriMesh 468 | `build` | FaceMeshTopology | MeshEngineImpl |
| `mesh/face_mesh_topology.generated.dart` | Tessellation canônica | `landmarkCount=468`, `triangleIndices` | — | builder, roles |
| `mesh/mesh_engine_impl.dart` | Facade + cache | `buildFaceMesh`, `buildBodyMesh` | builders, MeshCache | Controller |
| `warp/mls_solver.dart` | Similarity MLS 2D | `forward`, `inverse` | ControlPoint | MlsWarpEngine, G0, ChinFilter legado |
| `warp/mls_warp_engine.dart` | WarpEngine MLS | `compute`, `applyGPU` | MlsSolver, WarpFieldBuilder | factory legado |
| `warp/face_mesh_forward_warp.dart` | Backward piecewise na malha | `apply` | FaceWarpRenderer | PassWarp, todos os diagnósticos G* |
| `warp/face_warp_renderer.dart` | Localização de triângulo + amostragem | `renderFromPayload` | cell index, hole fill | ForwardWarp |
| `rendering/pass_warp.dart` | Pass 1 GPU/CPU | roteamento V3 vs legado, inpaint | backends, ForwardWarp | GpuRendererImpl |
| `shaders/face_mesh_piecewise.frag` | Piecewise GPU | — | — | FragmentProgramFaceMeshBackend |
| `filters/face/face_filter_pipeline.dart` | 22 filtros MLS legado + keys | `compose`, `hasActiveWarp` | cada `*Filter` | IntentFactory, controller legado |
| `filters/face/chin.dart` | Chin MLS legado | `buildControlPoints` | FaceWarpUtils | FaceFilterPipeline |
| `presentation/beauty_editor_page.dart` | UI de retoque | sliders, `_params`, preview | Controller | rota `/face-retouch` |
| `packages/beauty_mediapipe/` | Detecção nativa | `detectFace`, `detectPose` | MediaPipe Tasks | FaceMeshDetectorImpl |

## 6.3 Pesquisa de queixo

| Arquivo | Responsabilidade | Funções principais | Dependências | Quem usa |
|---|---|---|---|---|
| `experimental/chin_landmark_audit.dart` | Etapa A | `analyze`, `protectedOral` | malha, roles | B–G, plano H0 |
| `experimental/chin_mesh_laplacian.dart` | L + `ChinMeshAdjacency` | `build`, `from`, `dijkstra` | TriMesh | B–F, E0, plano H0 |
| `experimental/chin_mesh_constrained_field.dart` | Harmonic φ | `run`, solve CG | laplacian, linear_solver | B, C, D* |
| `experimental/chin_mesh_linear_solver.dart` | CG | solve SPD | — | harmonic, BBW |
| `experimental/chin_deformation_field.dart` | Campo experimental antigo (Gaussian/Shepard/MLS); **tip={152,175}** — conjunto **diferente** do G0 | pesos por grupo | roles | diagnósticos pré-G0; **não** usar como fonte H0 |
| `experimental/chin_mesh_bbw_operator.dart` | Q=L M⁻¹ L | `assemble` | laplacian cotan sem clamp | E0 |
| `experimental/chin_mesh_active_set_qp.dart` | QP reduzido | active-set | — | E0 |
| `experimental/chin_multi_handle_field.dart` | Campo BBW multi-handle | — | BBW, QP | E0 diagnostic |
| `experimental/chin_mesh_domain_catalog.dart` | Variantes de Ω | A/B_khop/C/D | adjacency | F |
| `experimental/chin_g0_mls_field.dart` | Sementes + MLS | `compute`, constantes de handle | MlsSolver, audit | G0, G1, G1.1, plano H0 |
| `experimental/chin_g1_injective_projection.dart` | Projeção hard | `project` | G0 deltas, jacobian math | G1, G1.1 (não edita G1) |
| `experimental/chin_g11_soft_handle_projection.dart` | Projeção soft | `project` | G1 constantes, LIM t_i | G1.1 diagnostic |
| `face_warp_chin_g0_diagnostic.dart` etc. | Harness + MD/PNG | `run` | engine + experimental | testes `chin_g*_test.dart` |

## 6.4 Contratos e operação MVP

| Arquivo | Papel |
|---|---|
| `warp/face_warp_numeric_contract.dart` | `phase9Epsilon=0.10`, `numericTolerance=1e-6` |
| `warp/face_warp_mvp_operations.dart` | 7 tools do menu; contour tools no path mesh backward |
| `warp/face_warp_operation.dart` | id / spec / compositionMode |
| `docs/beauty/28-face-warp-engine.md` | contrato V3 congelado |
| `docs/beauty/23-face-model-specification.md` | normativa ACE |

---

# 7. Fluxo de dados

Cadeia completa de um movimento do slider **Queixo** até um pixel.

1. **UI.** `BeautyEditorPage` escreve `_params['chin'] = t` (0..1). Outros sliders MVP permanecem no mapa (composição aditiva).
2. **Debounce / preview.** Chama `BeautyEngineController.renderPreview` (sem JPEG).
3. **Detecção (cacheada).** Se a foto não mudou, `FaceMeshResult` reutiliza os 478 landmarks. Senão: RGBA → MethodChannel → MediaPipe → mapper Dart.
4. **Malha.** `MeshEngineImpl.buildFaceMesh`: landmark `i` → `vertices[2i] = nx * width`. Índices da tessellation 468. Cache por hash.
5. **Intent.** `AnatomicalIntentFactory`: `raw=t` → `magnitude=1-(1-t)³`, `toolKey=chin`, zonas da spec.
6. **Delta por vértice.** ACE chama o gerador `_chin`. Só índices em `VertexRoleMap.chin ∪ {136,172,58,377,400,378}` recebem vetor; o resto fica 0 **neste gerador**. (Outros intents ativos somam nos mesmos buffers.)
7. **ACE.** Clamp 7.5% FSE; zera `oralCavity`; reduz anti-fold se área de triângulo < 35%; zera oral de novo.
8. **Phase 9 (produção).** Escalas `s_i ∈ (0,1]` por vértice, Jacobi, objetivo `det(J_tri) ≥ 0.10`. Safety Gate: se falhar critérios Phase 14, **descarta** o campo escalado e devolve o delta do passo 7.
9. **Influence.** `FaceMatteRoi.buildInfluenceMap` (oval ± expansão 0.07 no path MVP). Person mask opcional.
10. **Payload.** `FaceMeshForwardPayload(mesh, vertexField, influenceMap)`.
11. **Pixel.** Para o pixel `(x,y)` no frame de saída:
    - se influence≈0: copia fonte;
    - senão: busca triângulo destino contendo `(x,y)`;
    - baricêntricas `λ`;
    - `src = λ·(v0) + λ·(v1) + λ·(v2)` com `vi` **antes** do delta;
    - `dst_color = sample(fonte, src)`.
12. **Composição.** Skin/LUT/makeup se ativos. Preview mostra RGBA.

No harness G0 a coluna `current` **para no passo 7** (`applyStructuralPipeline: false`) e rasteriza com o mesmo passo 11. Por isso minJ de `current` nos relatórios G* não é o minJ pós-Phase 9 da produção.

Um movimento de **landmark** (re-detecção) recomeça no passo 3: a malha muda, o mesmo slider gera outro campo.

---

# 8. Dependências

## 8.1 Runtime (`pubspec.yaml`)

| Pacote | Por que existe |
|---|---|
| `flutter` | UI e Impeller / FragmentProgram |
| `beauty_mediapipe` (path) | Face/Pose/máscara nativos |
| `flutter_riverpod` + `riverpod_annotation` | DI (ADR 003) |
| `supabase_flutter` / `postgrest` | auth, `edits`, `app_settings` (rollout V3), storage |
| `dio` | HTTP |
| `image` | decode/encode nos diagnósticos e pipelines CPU |
| `image_picker` / `image_cropper` | captura |
| `hive` / `shared_preferences` / `flutter_secure_storage` | cache e sessão |
| `firebase_core` / `firebase_messaging` / `flutter_local_notifications` | push |
| `app_links` | deep links |
| `google_mobile_ads` | ads |
| `cached_network_image`, `flutter_svg`, `lottie`, `google_fonts`, `flutter_animate` | UI |
| `saver_gallery` / `share_plus` / `file_picker` | export/share |
| `uuid`, `intl`, `freezed_annotation`, `json_annotation`, `dartz`, `equatable` | modelos / Either |
| `speech_to_text` | prompt por voz (fluxo IA, não warp) |
| `webview_flutter` | conteúdo legal / pagamentos |

Não há pacote de álgebra linear (Eigen, Ceres, libigl). CG, SVD 2×2, QP active-set e MLS estão em Dart puro em `warp/experimental/` e `mls_solver.dart`.

## 8.2 Nativo / assets

- MediaPipe Tasks Vision (Android AAR, iOS pod)
- Modelos `.task` / `.tflite` em `assets/mediapipe/`
- Shaders Flutter GPU listados em `pubspec.yaml` → `shaders/`
- Restos de **Banuba Photo Editor SDK** ainda aparecem em `ios/Pods/` no disco de build; **não** estão em `pubspec.yaml`. Banuba foi usado e depois removido do Dart. O gate de swap Banuba/nativo permanece nas flags de rollout (`docs/beauty/26-sprint41-production-rollout.md`).

## 8.3 Dev

`build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `flutter_lints`, `flutter_test`.

---

# 9. Estado atual

## 9.1 Implementado e no produto (código de produção)

- Beauty hub: `/face-retouch`, `/body-reshape`.
- MediaPipe face + pose + person mask (iOS/Android).
- Mesh facial canônica + cache.
- 22 geradores warp V3 (pilot) + ACE + Phase 9 + Safety Gate.
- Renderer malha backward (MVP contour) e GPU piecewise.
- Skin engine, makeup blend, LUT beauty, presets bundled, sync.
- Body Reshape V2 (malha adaptativa, proteção de fundo, GPU remap).
- Feature flags V3 remotas (`app_settings`). Em **debug**, V3 default ON. Em **release**, o remoto pode estar `disable` — o editor facial então usa MLS legado até ligar o rollout.
- Tool Gate de qualidade da foto.
- Isolates / tiles de export.

## 9.2 Funcionando (com ressalvas medidas)

- Sliders MVP produzem deformação visível.
- Composição multi-slider aditiva no ACE.
- Boca `oralCavity` é pinada no ACE; nos diagnósticos G0 a boca de `current` ainda mede **0.5–0.7 px** (não é o conjunto D de 43 verts; 17/18 podem mover).
- Phase 9 + Safety Gate rodam; FAIL devolve o campo sem constraint.
- Preview sem JPEG.
- Dataset de regressão `phase12` existe.

## 9.3 Em desenvolvimento (pesquisa, fora de produção)

Toda a linha `.cursor/chin-mesh-field/` e `warp/experimental/chin_*`. Última etapa **executada**: G1.1 (16 ago 2026). Última etapa **planejada e não executada**: H0.

Calibração MVP Stage 1 (`docs/beauty/29-mvp-calibration-stage1.md`) é harness de leitura, não retune.

## 9.4 Não existe

- Integração de G0 / G1 / G1.1 / harmonic / BBW em produção.
- Código H0 (`chin_localized_target_field`, diagnostic, testes, pasta `stage-h0`).
- TPS / ARAP / meshWarp de produto (`WarpEngineFactory` stub).
- Campo-alvo espacial localizado (geodésico + PoU) em qualquer caminho de produção.
- Tempo real de câmera (`processStream`).
- Zona `AnatomicalZone.ear` (orelha só aparece como `{323,454}` no catálogo F).
- Solver de injetividade no pipeline V3 além do Jacobi de escalas Phase 9.
- FFI MediaPipe C++ direto (ADR 002); o bridge real é MethodChannel.
- Vencedor declarado para chin.

---

# 10. Hipóteses abertas

Nenhuma das hipóteses abaixo está comprovada por um vencedor integrado. As que têm evidência parcial estão marcadas.

1. **O problema do chin em 100% é o alvo espacial, não o solver de injetividade.** Evidência: G1/G1.1 injetivos sobre o suporte MLS ainda movem temple/forehead/eye. H0 existe para testar; **não foi corrido**.
2. **Similarity MLS (G0) é um interpolante global** (pesos 1/d² em todos os control points, inclusive pins orais) e por isso não pode ser o suporte de um queixo local. Evidência G0: temple/forehead ~ tip. Não testado um MLS com compact support.
3. **Hard-handle para `X_MLS` @ 100% é incompatível com injetividade local** nesta malha. Evidência G1: α_max 0.07–0.20. Soft-handle G1.1 relaxa isso nos handles, não no suporte.
4. **Triângulo 409** (região jaw / oral boundary) é um bloqueador estrutural em p12. Aparece em G1 e na zona de risco G1.1.
5. **Cotangente FEM clássica não é o Laplaciano correto** da Face Mesh projetada em 2D. Evidência D1: pesos negativos, `cot_clamp0` não é FEM. Uniforme foi o default B–C.
6. **172 e 397 em Dirichlet B matam a propagação harmônica para o jaw.** Evidência D2: φ jaw sobe ao libertá-los. Não integrado; D4-sensitivity mostra que Phase 9 apaga quase o ganho.
7. **Gônio {58,288,132,361} deve permanecer fronteira**, não handle. Usado em A–F e no plano H0. Produção `_chin` **move 58**.
8. **175 não é tip.** Evidência A. `chin_deformation_field.dart` ainda lista `tip={152,175}` — conjunto legado, divergente do G0.
9. **|F|≥12** é só operacional (F). Não é anatomia.
10. **Phase 9 (ε=0.10) comprime diferença anatômica B vs D** (~28% resta em `mesh_final`). Hipótese: o Safety Gate / Jacobi global é incompatível com um campo de queixo de suporte estreito — não isolada causalmente.
11. **Safety Gate PASS com folds no campo pré-Phase 9** (relatórios G0 `Safety Gate true` na coluna current/G0) não implica malha injetiva no campo medido pelos diagnósticos, porque G* medem ACE sem Phase 9 e ainda assim reportam o gate como métrica auxiliar.
12. **A malha MediaPipe 2D tem corredor estreito tip→oral** que qualquer campo compacto tem de atravessar sem puxar a boca (5 verts). Hipótese de que H0 com `R_oral` derivado de `d(200,oral)` resolve; não medida.
13. **V3 em release remoto pode estar desligado**, de modo que usuários veem MLS legado (`ChinFilter` CPs incluindo 313/421/428) enquanto o lab debug vê ACE `_chin`. Hipótese operacional, não geométrica.
14. **Injetividade local (minJ>10⁻³) não é qualidade visual.** G1.1 p01 minJ=0.0024 é injetivo e ainda herda o vazamento MLS.

---

# 11. Decisões de arquitetura já tomadas

| Decisão | Por que |
|---|---|
| ADR 001: Beauty Engine desacoplado da UI (controllers sem `material.dart` no core) | Engine testável; telas consomem via `BeautyEngineController` |
| ADR 002: MediaPipe Tasks nativo (não ML Kit 468, não FaceUnity como detector) | Paridade iOS+Android, 478 pts, open source |
| ADR 003: Riverpod, controllers sem `material.dart` | Testabilidade |
| Uma topologia: tessellation MediaPipe, não Delaunay por foto | Reprodutibilidade, regiões estáveis |
| Intenção via `AnatomicalIntent`, não delta solto no filtro | Composição multi-tool e pins |
| Unidades em FSE | Resolução-invariante |
| Composição MVP **aditiva** | Trocar de menu não apaga o slider anterior |
| Phase 9 + Safety Gate **obrigatórios** em V3; matemática congelada em `experimental/` | Não retunar jacobiano por ferramenta |
| FAIL do gate → campo **original**, não um meio-termo | Evitar deformação “quase constrained” indefinida |
| GPU-first, preview sem JPEG | Latência de slider |
| Rollback `useLegacyFaceMls` | Lab/prod podem voltar à grade MLS |
| Pesquisa de chin **fora** de produção, sem vencedor automático | Isolar evidência |
| G0/G1/G1.1 não se editam mutuamente | Comparabilidade das colunas |
| E1 BBW pausado no G0 | Ω degenerado (|F|=3) e F mostrou A inelegível |
| Handles G0 congelados (13 + oral pins); 175/199/200/gônio observacionais | Etapa A |
| H0, se existir, não executa solver | Diagnóstico G1/G1.1: solver não localiza |

---

# 12. Dívida técnica

1. **Dois geradores de chin** (`PilotWarpContourNose._chin` vs `ChinFilter.buildControlPoints`) com conjuntos de landmarks diferentes.
2. **Três dicionários de “tip”:** `VertexRoleMap.chin` (inclui 175, 17, 18); `ChinAnatomicalGroups.tip = {152,175}`; G0 `handleTip = {152}`.
3. **468 vs 478:** ACE aloca 478; tessellation e a maioria dos solves usam 468. Íris 468–477 são papéis de olho, não chin, mas o comprimento dos buffers diverge.
4. **`MlsSolver` documentado como rígido, implementado como similaridade.**
5. **ADR 002 descreve FFI C++;** o código é MethodChannel.
6. **`docs/beauty/04-warp.md` e `01-arquitetura.md` descrevem MLS+grade como o motor;** o default debug é V3 malha.
7. **Banuba:** flags de swap e Pods residuais vs ausência no `pubspec`.
8. **Phase 9 vive em `experimental/` mas é produção.** Risco de alguém “experimentar” o arquivo congelado.
9. **Dezenas de diagnostics** em `warp/` (AB, fold, jacobian, chin G*, mesh domain*) misturados com o renderer.
10. **Quantização RGBA8 do displacement** no remap de corpo (e reuso do shader) — erro que cresce com resolução; diagnóstico antigo de body reshape.
11. **Cotangente clampada** usada em D1 e **cotangente sem clamp** no BBW E0 — dois operadores com o mesmo nome informal.
12. **Anti-fold ACE (área 35%)** é local e distinto da injetividade Phase 9 (det J ≥ 0.10) e da barreira LIM (ε=10⁻³) dos G1*.
13. **Testes G* escrevem artefatos em caminhos absolutos** `/Users/leonardo/Documents/Projetos/editaiapp/.cursor/...` com fallback relativo — acoplados à máquina do autor.
14. **`FaceWarpV3Config` mutável estático** (`enabled = _defaultOn`) — estado global, rollout aplica por snapshot.

---

# 13. Problemas conhecidos

## 13.1 Produto — ferramenta `chin` (edição facial interativa)

Invariante B4: lábio inferior não estica; mandíbula sem degrau; sem folding no vale queixo–pescoço.

Medido nos harnesses G0/G1.1 @ 100%, coluna `current` = ACE **sem** Phase 9:

- **Folding:** p01 minJ −8.31, 18 folds; p12 minJ −8.67, 19 folds.
- **Boca não é zero:** 0.50–0.66 px (G0). Produção pin apenas `oralCavity`; `_chin` move 17 e 18 (`VertexRoleMap.chin`). Conjunto D da etapa A (43 verts) não é o rigid set da spec.
- **Gônio 58 é deslocado** por `_chinAdjacentJaw`; nas etapas A–F o gônio é fronteira Dirichlet.
- **Jaw assimétrico no gerador:** `_chinAdjacentJaw` tem 136, 172, 58 (esq.) e 377, 400, 378 (mistura contour/gônio); **não** tem 365, 397 (handles jaw G0 do lado direito).
- **Amplitude** do current é menor que G0 nos handles (tip 15–24 vs 28–52 px) e ainda folds.
- D4-sensitivity: qualquer ganho de gônio livre é **comprimido** por Phase 9 no path de produção.

Problemas visuais recorrentes da linha de pesquisa (não só chin): vazamento para região vizinha, pinçamento, descontinuidade de vizinhos, Safety Gate passando com geometria invertida no campo pré-constraint.

## 13.2 Matemáticos (pesquisa)

| Problema | Onde |
|---|---|
| Similarity MLS tem suporte global (1/d²); vaza temple/forehead/eye/nose | G0, herdado G1.1 `E_data` |
| Conjunto injetivo ∩ snap hard `X_MLS` vazio @ 100% (α≪1) | G1 |
| Barreira LIM + LM no teto (`1e7`) sem direção de descida mesmo com handles no alvo | G1.1 p01/p05 |
| p12 não atinge `X_MLS`; fração ~0.89; tri 409 | G1, G1.1 |
| `det J` rest da malha MediaPipe projetada pode ser o limite, não só o warp | G1 aborta se rest minJ ≤ ε (não ocorreu nas 3 fotos) |
| Cotangente 2D com ~24% arestas negativas | B, D1 |
| MVC nativo assimétrico; 1-anel não star-shaped | D1 `nonStar` 171–181 |
| `cot_clamp0` não é FEM; máximo princípio “elegível” não implica operador clássico | D1 |
| BBW em Ω com \|F\|=3 | E0 |
| Harmonic φ jaw ~0.04 com 172/397 em B | B, D2 |
| QP E0 injetivo? não — minJ −3..−4 | E0 |
| Phase 9 é escala isotrópica por vértice, não projeção no conjunto injetivo | produção vs G1 |
| Dois ε diferentes: Phase 9 0.10 vs LIM 10⁻³ | V3 vs G1* |
| PoU / REST de E0 não é Jacobson | E0 methodNote |

## 13.3 Render / engine geral

- Ghosting / seams em `face_slim` (vacancy, inpaint, heatmap de seams em `.cursor/debug-face-slim-triangle-seams-heatmap.png`).
- Tentativa anterior de anti-fantasma pixel-a-pixel ~7 s / frame; revertida. Inpaint atual é grade 80×80.
- Preview ainda pode enfileirar frames se o slider for mais rápido que o pipeline.
- Body: Displacement RGBA8 quantizado; tiles CPU com coordenadas globais já foram apontados como bug em auditorias antigas.
- MediaPipe x86 emulator.

---

# 14. Próximos passos planejados

O que está escrito no repositório / plano, não uma lista nova.

1. **H0** (plano `etapa_h0_target_field_501b30c4.plan.md`, todo `h0-impl-later` = pending). Quando autorizado: implementar `chin_localized_target_field.dart` + diagnostic + teste p01/p05/p12 @ 100%. Não editar G0/G1/G1.1/produção. Não correr ARAP/LIM/MLS/BBW/QP/Phase 9 na construção. Classificar H0_SUCCESS / PARTIAL / FAIL pelos gates L1–L2, C1, M1, P1–P4, O1, U1, G1g. Artefatos em `.cursor/chin-mesh-field/stage-h0/`. Se `structuralLeakBlocksNextSolver`, o plano manda **parar** — não G2/LIM/ARAP para esconder temple/forehead.

2. **E1 / E2** — pausados (G0 methodNote: “E1 pausado”). Não há spec nova.

3. **Integração em produção** — explicitamente fora de todas as etapas A–G1.1 e do plano H0 (`Sem vencedor. Sem integração.`).

4. **Calibração MVP** — Stage 1 é diagnóstico; stages seguintes de calibração de sliders existem como harness (`face_warp_mvp_calibration_*`) sem fechar chin.

5. **Rollout V3** — `docs/beauty/26-sprint41-production-rollout.md`: ligar flags remotas (`face_warp_v3_enabled`, percentuais GPU/inpaint/native) quando se quiser V3 em release. Independente da pesquisa H0.

6. **Roadmap histórico sprints 01–27** (`docs/beauty/10-roadmap.md`) está marcado concluído no papel; a linha viva é Face Warp V3 + pesquisa chin + Body Reshape V2.

7. **TPS/ARAP de produto** — stub; não há sprint ativo.

Não há autorização no plano H0 para escolher solver depois do H0. Isso só existiria após classificação H0.

---

# 15. Referências

Onde cada item **é usado** no projeto. Sem resumo do paper.

| Referência | Onde entra na arquitetura |
|---|---|
| **Schaefer, McPhail, Warren — Image Deformation Using Moving Least Squares (2006), §2.2 similarity** | Implementação real de `MlsSolver.forward`; G0 (`ChinG0MlsField`); caminho legado `MlsWarpEngine` / `ChinFilter`. §2.3 rigid **não** está implementado, apesar do comentário em `mls_solver.dart`. |
| **Schaefer 2006, pesos w=1/(d²+ε)** | `MlsSolver`, ε=1e-8; G0 methodNote |
| **Hu et al. — Facial Reshaping Operator** | Citado em `ChinG0MlsField.methodNote` como contexto. **Nenhuma função** implementa o operador. |
| **Jacobson, Baran, Popović, Sorkine — Bounded Biharmonic Weights (SIGGRAPH 2011)** | Motivação de E0. `ChinMeshBbwOperator` monta `Q=L M⁻¹ L`. O REST e o QP são extensão de engenharia; o diagnostic afirma **não** ser Jacobson literal. |
| **Floater — Mean Value Coordinates** | Operador `mean_value_sym` em D1 (`chin_mesh_laplacian.dart`). Nativo assimétrico; solve usa média simétrica. |
| **Pinkall / Polthier — cotangente discreta** | Pesos cotangentes em `ChinMeshLaplacian._cotangentWeights`; D1 `cot_clamp0` (modificado); E0 BBW usa cotan **sem** clamp. |
| **Sorkine, Alexa — As-Rigid-As-Possible (local-global)** | Esqueleto de G1/G1.1: passo local SVD 2×2, R congelado no global. G1 methodNote: **não** é a Hessiana exata do ARAP. Não está no `WarpAlgorithm.arap` de produto. |
| **Schüller, Kavan, Botsch, Panozzo — Locally Injective Mappings (LIM)** | Barreira de jacobiano em G1 (`mu`); G1.1 §3.3 alvos intermediários `t_i` e §3.4 peso soft `w_soft`. ε=10⁻³. Não usado em produção. |
| **Levenberg–Marquardt** | Damping no Newton de G1/G1.1 (`lmFloor`…`lmMax`). |
| **MediaPipe Face Landmarker / Face Mesh (Google)** | Detecção 478 pts; tessellation 468; índices de `VertexRoleMap` e `FaceMeshTopology`. |
| **MediaPipe Pose** | Body reshape / filtros de corpo. |
| **Contrato interno Phase 9 / Phase 14** (`face_warp_numeric_contract.dart`, `docs/beauty/28-face-warp-engine.md`) | Produção V3: Jacobi de escalas ε=0.10 + Safety Gate. Não é um paper; é o substituto de injetividade no produto. |
| **Face Model Spec / invariante B4** (`23-face-model-specification.md`, `13-visual-quality-targets.md`) | Zonas e critério de qualidade do `chin` de produção. |

Trabalhos lidos na pesquisa H0 (LivePortrait, FaceWarehouse, BBW de novo, sculpt falloff, cages, deformation graphs, TPS locality) **não** têm arquivo de implementação nem chamada no pipeline. Estão só no relatório de pesquisa da conversa de 17 ago 2026, 00:40, não neste código.

---

## Apêndice — mapa rápido “o que olhar primeiro”

Se o leitor só puder abrir dez arquivos:

1. `docs/beauty/28-face-warp-engine.md` — contrato V3  
2. `warp/anatomy/face_mesh_deformation_engine.dart` — orquestração do campo  
3. `warp/anatomy/pilot_warp_contour_nose.dart` — `_chin` de produção  
4. `warp/anatomy/anatomical_constraint_engine.dart` — ACE  
5. `warp/face_warp_structural_pipeline.dart` — Phase 9  
6. `warp/mls_solver.dart` — MLS real  
7. `warp/experimental/chin_g0_mls_field.dart` — sementes G0  
8. `.cursor/chin-mesh-field/stage-g11/g11-report.md` — último resultado experimental  
9. `.cursor/chin-mesh-field/audit/anatomy-report.md` — anatomia congelada  
10. Plano H0 — `~/.cursor/plans/etapa_h0_target_field_501b30c4.plan.md` (não implementado)
