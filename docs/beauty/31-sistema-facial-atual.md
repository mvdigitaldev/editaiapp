# Sistema facial actual — o que existe, o que se vê, e por que não é Meitu

**Data:** 17 de agosto de 2026  
**Audiência:** Leonardo (e quem for montar o plano seguinte).  
**Estado do código:** a H-Architecture foi **apagada** (módulo `warp/experimental/h_architecture/`, testes, flag `useHArchitecture`, wiring no engine/controller). Produção facial = V3 ACE + malha MediaPipe.  
**Isto não é um plano.** É o mapa do sistema **como está**, com evidência de por que o resultado visual não chega a Meitu / FaceTune / YouCam / FaceUnity.

Documentos relacionados (arquivo, não substituem este):

- [`30-estado-atual-arquitetura.md`](./30-estado-atual-arquitetura.md) — pesquisa A–G1.1, inventário experimental
- [`23-face-model-specification.md`](./23-face-model-specification.md) — zonas e dMax
- [`28-face-warp-engine.md`](./28-face-warp-engine.md) — contrato V3
- [`landmarks-regioes-anatomicas.md`](./landmarks-regioes-anatomicas.md) — IDs MediaPipe
- [`13-visual-quality-targets.md`](./13-visual-quality-targets.md) — invariantes B1–B4

---

## 0. Em uma página

O Beauty Engine deforma uma **foto estática** assim:

1. MediaPipe dá 478 pontos 2D na imagem (468 entram na malha).
2. Uma malha triangular **fixa** (topologia MediaPipe, ~851 triângulos) é colada nesses pontos. A malha **acaba no oval da cara**. Não tem pescoço, orelha externa completa, nem fundo.
3. Cada slider vira um **deslocamento 2D por vértice** (`ConstrainedVertexField`), gerado por funções-piloto heurísticas (ACE), não por um morph 3D nem por uma grelha densa tipo liquify.
4. O campo passa por um **portão de jacobiano** (Phase 9, ε=0.10) que corta folds — e com eles parte da amplitude.
5. O raster **só pinta pixels que caem dentro da malha já deformada**. O contorno antigo da foto (queixo, mandíbula contra o pescoço) fica lá, a menos que um “fantasma” o apague.
6. No preview, um `GeometricSupport` ainda **atenua vértices no oval** (feito para o Afinar não puxar orelha). Ferramentas cujo efeito **é** o oval (queixo, mandíbula) perdem o sinal no ecrã.

**Afinar rosto funciona** porque mexe bochecha **por dentro** do oval: o pixel da pele muda, e isso vê-se mesmo sem o silhueta do queixo se mexer.

**Queixo / estreitar / mandíbula falham como produto** porque o efeito que o utilizador quer é **a silhueta da cara mudar** (queixo sobe, cara estreita no maxilar). Isso exige deformar **a fronteira da foto** (pele + pescoço + fundo imediato) e **apagar o contorno antigo**. O motor actual não foi desenhado para isso.

Apps como Meitu não resolvem isto com 468 vértices e um jacobiano. Deformam uma **região 2D larga** (cara+pescoço), com amplitudes grandes e preenchimento do buraco. A H tentou o contrário (morph 3D canónico em 2–4 vértices) e foi descartada por invisível.

---

## 1. O que o produto é

- App nativo **iOS e Android** (Flutter). Sem webcam em tempo real no produto (`processStream` está no backlog).
- Ecrã: `/face-retouch` → `BeautyEditorPage`.
- Motor: `lib/features/editor/beauty_engine/`. Detecção: `packages/beauty_mediapipe/` (MethodChannel, MediaPipe Tasks).
- Objectivo declarado nos docs: substituir SDKs comerciais (Tencent, Banuba, FaceUnity) **neste app**, não publicar um SDK.

Há dois motores de deformação:

| Motor | Onde | Estado |
|---|---|---|
| **Face Warp V3** | malha MediaPipe + ACE + Phase 9 + raster backward | **produção facial** |
| **Body Reshape V2** | malha corporal adaptativa + protecção de fundo | produção corporal, paralelo |
| MLS facial legado | `FaceFilterPipeline.compose` + `MlsSolver` | só se `useLegacyFaceMls = true` (off) |

Este documento trata **só da cara**.

---

## 2. Pipeline de produção (foto → preview)

```
Foto RGBA
    → MediaPipe Face Landmarker
    → FaceMeshResult (478 landmarks normalizados 0..1)
    → FaceMeshBuilder → TriMesh (468 verts em px, UVs, ~851 tris)
    → sliders Map<String,double>
    → AnatomicalIntentFactory          (easeOutCubic, mode=pilot)
    → AnatomicalConstraintEngine       (piloto + pins + clamp FSE + anti-fold local)
    → ConstrainedVertexField           (478 slots; 468 usados na malha)
    → FaceWarpStructuralPipeline       (Phase 9 jacobian ε=0.10 + Safety Gate)
    → FaceMatteRoi                     (elipse do oval ± person mask)
    → BeautyEngineController.composeFaceField
         ├─ WarpField (grade, barycentric; muitas vezes identidade no preview directo)
         └─ FaceMeshForwardPayload (malha + campo + influence + personMask)
    → PassWarp
         → se payload MVP: FaceMeshForwardWarp
              FaceWarpRenderer: GeometricSupport × delta → malha deformada
              backward piecewise-affine por triângulo destino
              hole fill lateral (+ inferior se o vértice 152/175 sobe > 2 px)
         → senão GPU piecewise / remap CPU da grade
    → skin / LUT / makeup (depois do warp)
    → RawImage no editor
```

Ficheiros âncora:

| Papel | Ficheiro |
|---|---|
| UI sliders | `presentation/widgets/beauty_adjustments_panel.dart` |
| Labels PT | `l10n/beauty_engine_labels.dart` |
| Orquestração | `controllers/beauty_engine_controller.dart` |
| Autor do campo | `warp/anatomy/face_mesh_deformation_engine.dart` |
| Intents | `warp/anatomy/anatomical_intent_factory.dart` |
| ACE | `warp/anatomy/anatomical_constraint_engine.dart` |
| Deltas piloto | `warp/anatomy/pilot_warp_displacement.dart`, `pilot_warp_contour_nose.dart` |
| Spec zonas/dMax | `warp/anatomy/face_model_specification.dart` |
| Phase 9 | `warp/face_warp_structural_pipeline.dart` → `experimental/global_jacobian_*` |
| Raster malha | `warp/face_warp_renderer.dart`, `warp/face_mesh_forward_warp.dart` |
| Pass GPU/CPU | `rendering/pass_warp.dart` |
| Flags | `config/face_warp_v3_config.dart` |

Flags relevantes (debug/pré-prod ligadas por omissão):

```
enabled, useMeshWarpV3, useDirectMeshRender, useGpuPiecewiseAffine,
usePostWarpInpaint, useForwardMeshWarpFaceSlim = true
useLegacyFaceMls = false
```

O preview interativo **não** usa o isolate MLS. `composeFaceFieldAsync` chama `composeFaceField` no mesmo isolate quando V3 está on.

---

## 3. Dados: o que a malha é (e o que não é)

### 3.1 Landmarks

- **478** pontos MediaPipe Face Landmarker: 468 da tessellation + 10 de íris (468–477).
- A malha de warp usa **468** vértices (`FaceMeshTopology.landmarkCount`).
- Coordenadas: normalizadas no retrato; o builder multiplica por `imageSize` → pixels.

Não há reconstrução 3D de produção. Os `z` do MediaPipe **não** alimentam o warp V3. Tudo é 2D na imagem.

### 3.2 Topologia

- Gerada de `face_model_landmarks_triangles.txt` (MediaPipe).
- ~851 triângulos. Fixa para todas as caras. Só as **posições** mudam com a foto.
- A fronteira da malha é o **oval facial** (landmarks do contorno). **Não inclui pescoço, clavícula, fundo, cabelo fora do crânio.**

Isto é a restrição mais importante do sistema. Qualquer morph cujo “produto” é o queixo contra o pescoço está a tentar mover uma fronteira que, na foto, continua desenhada **fora** da malha.

### 3.3 Person mask

Há selfie-segmenter / parsing. Usados para matte e para o fill de fantasma **lateral** (Afinar). O queixo antigo é pele (`person ≈ 1`); o fill lateral foi escrito para o halo `person ∈ [0.22, 0.52]` (buraco entre cara e fundo). Por isso **não apagava o queixo velho**.

Foi acrescentado um fill **inferior** em `FaceMeshForwardWarp` (pixels abaixo da malha nova, sem exigir person baixa), disparado se `‖Δy‖` em 152 ou 175 > 2 px. Está no código; **não foi validado visualmente** como produto.

---

## 4. Ferramentas no menu (MVP)

UI categoria Rosto:

| Label | Key | Intenção de produto | O que o piloto faz de facto |
|---|---|---|---|
| Afinar rosto | `face_slim` | Cara mais estreita (bochecha/contorno) | Pull **horizontal** para o eixo, peso no **bordo** da bochecha/mandíbula/têmpora. dMax ≈ 0.08 FSE. |
| Estreitar rosto | `narrow_face` | Cara mais estreita (mais local?) | Pull horizontal em bochecha **e** jaw (jaw × 0.70). Mesma família que afinar, amplitude via FSE. |
| Rosto em V | `v_face` | Maxilar em V | Jaw entra (até 14% da largura da **imagem**) + queixo sobe 2.5% da altura. |
| Mandíbula | `jaw` | Afina maxilar | Só `jawLeft`/`jawRight`. Shift até min(9% width, 0.07 FSE). **Só Δx.** |
| Queixo | `chin` | Encurta / afina queixo | `VertexRoleMap.chin` ∪ `{136,172,58,377,400,378}`. Lift = **3.5% da altura da imagem**; narrow = 4% da largura. Adjacent jaw × 0.65. |
| Maçãs do rosto | `cheekbone` | Volume malar | Outward + lift nos anéis de cheekbone. |
| Testa | `forehead` | Altura da testa | Lift vertical ~2.2% da altura da imagem. |

Há mais 15 tools no pipeline (`nose_*`, olhos, boca, `temple`, `head_size`) com o mesmo ACE, **fora do menu MVP**.

Composição MVP é **aditiva** no ACE (`FaceWarpMvpOperations.usesAdditiveComposition`). Vários sliders no mesmo vértice somam.

Slider → magnitude: `easeOutCubic(raw)` no intent; vários pilotos usam `rawIntensity` linear à mesma. Há um segundo ease `pow(m, 1.35)` em `_effectiveMag` no piloto de contorno.

---

## 5. Como nasce o deslocamento (ACE)

Para cada landmark 0..477, se a spec diz que a zona é free/semi-rigid:

```
delta = PilotWarp(tool, index, posição 2D, FSE, magnitude)
depois: clamp ‖delta‖ ≤ maxDisplacementFse × FSE
depois: pins rígidos (olhos, boca, etc. conforme spec)
depois: anti-fold local (área mínima de triângulo)
depois: pins outra vez
```

FSE = menor lado da bounding box do oval na imagem.

Não há:

- morph 3D / blendshape
- MLS no caminho V3 (excepto rollback)
- handles explícitos tipo “agarra o queixo e puxa”
- domínio extra além dos 468 vértices

O “algoritmo” de queixo é literalmente:

```
lift   = imageHeight * 0.035 * t
narrow = imageWidth  * 0.04  * t
delta  = (sign(centro - x) * narrow * ratio * narrowFactor,
          -lift * narrowFactor)
```

Isto **é** a escola Meitu no papel (2D, % da imagem). A diferença está no **suporte** (10–16 pontos vs. cadeia inteira do maxilar+pescoço) e no **raster** (só malha vs. grelha que inclui pescoço).

`VertexRoleMap.chin` = `{152, 175, 199, 200, 17, 18, 148, 176, 149, 150}` — dez pontos, sem 377/400 no set (esses entram só pelo jaw adjacente).

---

## 6. O que o pipeline tira ao campo antes de se ver

### 6.1 Phase 9 (obrigatória)

`FaceWarpStructuralPipeline`: `GlobalJacobianConstraint` ε=**0.10** + Safety Gate.

Qualquer triângulo que invertiria é comprimido. Em ferramentas localizadas no queixo isto **corta ponta** e, em mandíbula, corta mais.

Medição em `real-p01` (695×1024), slider 1.0, ACE:

| Tool | raw ACE (px) | depois Phase 9 (px) | depois GeometricSupport (px efectivos) |
|---|---|---|---|
| `face_slim` | 30.0 | 26.3 | **22.7** (bochecha) |
| `chin` | 28.4 | 26.3 | **22.8** (queixo) |
| `narrow_face` | 28.5 | 26.3 | **21.6** (bochecha) |
| `jaw` | 26.5 | 18.7 | **5.4** (jaw) |

Phase 9 quase não mata Afinar/Queixo/Estreitar. **Mata a mandíbula** (26 → 19, depois o support deixa 5 px).

### 6.2 GeometricSupport (preview mesh)

`effectiveDelta = coreDelta × supportWeight`.

O peso é radial em relação ao oval: interior ≈ 1, **contorno ≥ 0.85 é atenuado até ~0**. Foi desenhado para o Afinar não puxar orelha/fundo.

Consequência:

- Bochecha interior (Afinar, Estreitar) → peso alto → **vê-se**.
- Vértices do oval (queixo, gônio) → peso baixo → o campo “existe” e o ecrã **não muda**.

O renderer **sempre** aplica isto no caminho `FaceMeshForwardWarp` (não há bypass).

### 6.3 Matte (`FaceMatteRoi`)

Elipse do oval, feather 0.035, opcionalmente × person mask. `lateralRadiusExpand = 0.07` no caminho MVP. A expansão **vertical** é `× 0.35` — quase não cobre pescoço.

Pixels fora da elipse não são influenciados no remap de grade. No mesh backward, o domínio é a malha, não a elipse; a elipse entra no support e no ghost lateral.

---

## 7. Raster: por que o queixo antigo fica na foto

Caminho MVP (`usesMvpMeshPath`: só tools da lista `face_slim, narrow_face, v_face, jaw, chin, cheekbone, forehead`, sem `eye_distance`/`mouth_width`):

1. Constrói-se `FaceMeshForwardPayload`.
2. `FaceWarpRenderer` soma `effectiveDelta` aos 468 `mesh.vertices`.
3. Indexa a **malha destino** (já deformada).
4. Para cada pixel **dentro** dessa malha, amostra a foto na posição origem (backward).
5. Pixels **fora** da malha nova = foto original.

Se o queixo sobe 25 px:

- Dentro da malha nova: pele do queixo comprime (pouco visível).
- Onde estava o queixo velho: **ainda é a foto original** → linha do queixo duplicada ou “nada aconteceu”.

O Afinar escapa a isto porque o efeito visível é a **pele da bochecha** a deslocar-se para dentro, ainda coberta pela malha. O buraco lateral (orelha/fundo) tem fill específico (`_buildLateralSeamGhostMask`, `ny ∈ [0.16, 0.70]`, `lateral ≥ 0.38`, person 0.22–0.52). **O terço inferior da cara está excluído de propósito.**

Grade `WarpField`: com `useDirectMeshRender` o rasterizer **não** faz spread/vacancy (heurísticas de grade). A grade pode ficar esparsa/quase identidade mesmo com campo de vértices vivo. Havia um skip em `PassWarp` / `_renderTexture` que **não corria o mesh warp** se a grade fosse identidade. Isso foi corrigido: o payload da malha basta para entrar no pass. O Afinar voltou a funcionar depois desse restart.

Preview do Afinar: ~2–3 s no simulador (CPU backward em resolução cheia). Não é tempo real.

---

## 8. O que funciona hoje vs. o que não

### Funciona (validado no simulador)

- **Afinar rosto (`face_slim`)** no máximo: deformação visível nas bochechas. Pipeline V3 completo (ACE + Phase 9 + mesh backward + ghost lateral).

### Não funciona como produto (mesmo com campo ≠ 0)

- **Queixo:** o ACE gera ~25 px no tip; o utilizador não vê o contorno a subir. Causa: domínio = malha sem pescoço + ghost inferior historicamente ausente + suporte radial a matar o oval. O fill inferior acabou de ser ligado; **não substitui um domínio com pescoço**.
- **Mandíbula:** Phase 9 + GeometricSupport deixam ~5 px. Abaixo do limiar perceptivo numa foto 1k.
- **Estreitar rosto:** números parecidos ao Afinar (bochecha ~22 px). Se no ecrã “não faz nada”, ou o slider foi testado em conjunto com Afinar (mesmo eixo, saturação), ou a diferença visual face ao Afinar é pequena demais para contar como ferramenta distinta.

Nariz / olhos / boca: fora do foco desta crise, mas usam o **mesmo** raster. Ferramentas interiores (olhos, boca) tendem a ver-se melhor do que ferramentas de **silhueta**.

---

## 9. Como os apps que “funcionam” fazem isto

Não há código Meitu no repo. O que se segue é o padrão da indústria (Meitu / FaceTune / YouCam / BeautyPlus / FaceUnity / Banuba / Tencent), confrontado com o nosso motor.

### 9.1 O produto é a silhueta da foto, não o vértice da malha

O utilizador julga **o bordo da cara contra o fundo**. Se a linha do queixo na imagem não se mexer, o morph “não existe”, mesmo com 30 px no landmark 152.

### 9.2 Domínio maior que a cara

SDKs comerciais deformam uma **ROI 2D** que inclui:

- oval + **faixa de pescoço** (2–8% da altura da imagem abaixo do 152)
- por vezes ombro interno / fundo imediato
- uma grelha densa (dezenas a centenas de células) **ou** uma malha 3D da cabeça que projecta no pescoço

Não recortam o warp aos 468 triângulos MediaPipe.

### 9.3 Amplitude e suporte largos

Receitas típicas de “chin” / “slim face” (ordem de grandeza, não um SDK específico):

- queixo: 4–10% da **altura da cara** (não 3.5% da **imagem** inteira, e não só 10 vértices)
- slim: cadeia **inteira** do oval inferior (de têmpora a têmpora no maxilar), falloff suave
- um único slider “V-shape” combina slim + chin + jaw, em vez de três tools fracas e sobrepostas

### 9.4 Preenchimento do buraco é parte do morph

Quando o queixo sobe, os pixels do queixo antigo **têm** de passar a pescoço/fundo. Isso é inpaint / clone / backward sample duma grelha que já inclui o pescoço. Sem isto, o morph interior é irrelevante.

### 9.5 3D, quando existe, não é o raster

Muitos SDKs usam 3DMM / malha de cabeça para **pose e morphs artísticos**, depois aplicam o resultado como **warp 2D da imagem** (ou reprojectam com textura). O utilizador nunca vê “468 deltas no oval”. Vê a foto reamostrada.

A nossa V3 saltou o 3D **e** saltou a grelha larga: ficou o pior dos dois para silhueta (malha curta, 2D heurístico, sem pescoço).

### 9.6 Não optimizam jacobiano até o efeito desaparecer

Injetividade é um meio. Meitu aceita distorção local e tapa com blur/inpaint. Nós cortamos o campo até minJ ≥ 0.10 **antes** do raster — correcto para não dobrar triângulos, letal para um queixo que só tem 10 vértices no bordo.

### 9.7 Tabela de fosso

| | Meitu / FaceTune / FaceUnity | Editai V3 actual |
|---|---|---|
| Unidade de deformação | ROI imagem (cara+pescoço) ou cabeça 3D projectada | 468 verts do oval MediaPipe |
| Autor do campo | morphs artísticos / handles 2D largos | piloto heurístico por landmark |
| Queixo | cadeia do oval inferior + pescoço | 10 verts + 6 jaw adjacentes |
| Amplitude visível | silhueta deslocada vários % da cara | 20–30 px no vértice, **0 px no bordo da foto** |
| Buraco | inpaint / domínio que já tem pescoço | ghost lateral (bochecha); inferior recém-chegado e frágil |
| Contorno | é o alvo | GeometricSupport **atenua** o contorno |
| Folding | tolerado + tapado | Phase 9 corta o campo |
| Tempo | GPU, preview 30–60 fps típico | CPU backward, 2–3 s no simulador |
| 3D | opcional, para pose/morph | não há |

---

## 10. O que já se tentou e foi descartado (para o próximo plano não repetir)

Nenhuma destas linhas está em produção. Código residual em `warp/experimental/chin_*` e relatórios em `.cursor/chin-mesh-field/`.

| Linha | Ideia | Por que não fechou |
|---|---|---|
| A–F | φ harmónico, domínio, BBW, Laplacianos no queixo | Definem **pesos**, não um alvo visual de “queixo sobe”. Ω degenerado (E0 com \|F\|=3). Sem integração. |
| G0 MLS | 13 handles + `MlsSolver` | Tip 2× o ACE, mas **vaza** para testa/têmpora/olho na mesma ordem de px. Folds. |
| G1 / G1.1 | Projectar MLS no conjunto injetivo (LIM/ARAP) | Injetivo só com α ≪ 1; o queixo útil desaparece. |
| **H-Architecture** | Malha canónica 3D → morph geodésico → projectar δ no ecrã | Campo real (~16 px no tip), **2 px efectivos** no oval por causa do GeometricSupport; 2–4 verts de core; sem pescoço. **Apagada em 17 ago 2026.** |

Lição já medida, duas vezes:

1. **Solver / 3D / geodésica não substituem um alvo espacial na foto** (silhueta + pescoço + amplitude).
2. **Injetividade primeiro** transforma um morph visível num morph nulo.

---

## 11. Inventário do que ficou no disco (não é o editor)

Ainda existem (pesquisa, **não** chamados pelo editor):

- `warp/experimental/chin_*.dart` — A–G1.1
- `warp/face_warp_chin_*_diagnostic.dart` e testes `test/beauty_engine/warp/chin_*`
- `.cursor/chin-mesh-field/`, `.cursor/stage8-chin/`, etc.

Produção **não** importa esses módulos no `FaceMeshDeformationEngine`.

---

## 12. Factos quantitativos para o próximo plano

Foto de referência interna `real-p01`, 695×1024, slider = 1, ACE + Phase 9 + GeometricSupport (caminho do preview):

- Afinar: **22.7 px** na bochecha → visível.
- Queixo: **22.8 px** no queixo no campo efectivo de vértice → **não se traduz em silhueta**.
- Mandíbula: **5.4 px** efectivos → abaixo do útil.
- Estreitar: **21.6 px** na bochecha → teoricamente visível; produto pouco diferenciado do Afinar.

Preview Afinar: `face_warp_v3` ~180–330 ms de composição; **render_texture p50 ~2–3 s** (raster CPU). Qualquer plano novo que mantenha backward CPU por pixel na resolução cheia herda isto.

---

## 13. Restrições que o sistema actual impõe (há que as quebrar ou as assumir)

1. **Domínio = oval MediaPipe.** Sem pescoço no grafo, o queixo na foto não sai.
2. **Raster = só malha destino.** Sem fill / domínio extra, o contorno antigo permanece.
3. **GeometricSupport anti-contorno.** Incompatível com tools cujo alvo **é** o oval.
4. **Phase 9 ε=0.10 em todo o morph.** Localizar o portão ou aceitar folds + inpaint.
5. **468 verts, topologia fixa.** Não há densificar o maxilar sem outra malha ou grelha.
6. **Um campo 2D por landmark, heurístico.** Não há biblioteca de morphs artísticos.
7. **Preview CPU lento.** Limita iteração visual e qualquer “slider 60 fps”.
8. **Afinar está vivo.** Um plano novo não pode partir o único morph que o utilizador já valida.

---

## 14. O que um plano novo tem de decidir (perguntas, não respostas)

1. O alvo de produto é **Meitu-like na foto** (silhueta) ou **malha anatomicamente correcta**? Os dois objectivos já colidiram durante um mês.
2. O domínio do warp passa a incluir **pescoço/fundo** (grelha 2D ou malha estendida) ou continua-se a 468?
3. GeometricSupport e Phase 9 aplicam-se a tools de silhueta, ou só a Afinar?
4. Queixo / mandíbula / estreitar são **três morphs** ou um “lower face” com eixos?
5. Quem é o autor do campo: piloto 2D (como agora, mas com suporte largo), grelha liquify, ou 3DMM? A H 3D canónica já foi rejeitada na prática.
6. O preenchimento do buraco é **obrigatório no mesmo pass** que o warp?
7. Qual o orçamento de preview (ms) e em que resolução se deforma?

Enquanto 1–3 não estiverem explícitos, o código vai continuar a gerar deltas de 20 px que o ecrã não mostra.

---

## 15. Mapa mental do código após o descarte da H

```
Slider (UI)
    → ACE piloto 2D          ← único autor em produção
    → Phase 9                ← corta folds e, no jaw, o efeito
    → GeometricSupport       ← corta o oval
    → Mesh backward          ← não pinta fora da malha
    → Foto com o queixo velho
```

O Afinar atravessa isto porque trabalha **dentro**. Queixo e mandíbula são um problema de **bordo da imagem**. Meitu resolve bordo. Nós ainda resolvemos vértice.
