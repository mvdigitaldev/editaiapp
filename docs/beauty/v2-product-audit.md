# Auditoria de produto facial

**Estado:** evidência do código e dos ecrãs Meitu (Temple, Lift, Width, Smooth, Double chin, Jawline, Hairline, Jaw angle, V shape, V chin, Chin length, Cheekbones). Sem proposta de arquitectura nova.

**Adenda 2026-08-26.** `cheekbone` deixou de ser fantasma: Field H + slider bipolar + Geral/Esq/Dir em inspecção. Sem C. Ver [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). Pipeline: `applyJawWarp` → `applyChinWarp` → `applyCheekbonesWarp`. As tabelas abaixo são o snapshot da auditoria original (key ainda “fantasma”).


Até esta auditoria ser aprovada, [`v2-face-rig-migration-plan.md`](./v2-face-rig-migration-plan.md) fica congelado. As [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md) não se emendam aqui.

Contrato de render vivo (único):

```
EffectField.build(face, size, t) → DisplacementField
BackwardBilinearWarp.apply(WarpRequest) → WarpResult
```

Preview e export faciais: `applyJawWarp` depois `applyChinWarp` em [`beauty_engine_controller.dart`](../../lib/features/editor/beauty_engine/controllers/beauty_engine_controller.dart) (`_renderTexture`, linhas 1015–1028) e o mesmo par em [`tiled_export_engine.dart`](../../lib/features/editor/beauty_engine/performance/tiled_export_engine.dart).

---

## Definições de status

| Status | Critério usado neste documento |
|---|---|
| **vivo** | Key no painel Rosto **e** Field V2 **e** chamada no controller/export |
| **lab** | Field + testes + dumps; **sem** slider no painel e sem `apply*Warp` de produto |
| **fantasma** | Key em `FaceParams` / preset / l10n / gate; **sem** Field V2 e **sem** slider no painel |
| **legado** | Código ou golden de pipeline abandonada (MLS / V3 / ACE); não é o caminho `_renderTexture` |
| **shader** | Passa por pele/cor GPU, não por `DisplacementField` |
| **ausente** | Conceito Meitu sem key e sem Field |

---

## 1. Estado actual — sliders e keys

### 1.1 O que o utilizador vê

O painel Rosto lê **apenas** `FaceFilterPipeline.faceWarpParameterKeys`:

```5:5:lib/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart
  static const faceWarpParameterKeys = ['jaw', 'chin'];
```

O mesmo par está em [`beauty_tool_registry.dart`](../../lib/features/editor/beauty_engine/tools/beauty_tool_registry.dart) (`_face`) e em [`beauty_adjustments_panel.dart`](../../lib/features/editor/beauty_engine/presentation/widgets/beauty_adjustments_panel.dart) (categoria Rosto). Não há categorias Nariz / Olhos / Boca no painel: só Rosto, Corpo, Pele, Cor.

**Sliders faciais de warp no produto: 2.** `jaw` e `chin`.

---

### 1.2 Ficha — `jaw`

| | |
|---|---|
| **Key** | `jaw` |
| **Label** | Mandíbula ([`beauty_engine_labels.dart`](../../lib/features/editor/beauty_engine/l10n/beauty_engine_labels.dart)) |
| **Status** | **vivo** |
| **Field** | [`JawField`](../../lib/features/editor/beauty_engine/warp/v2/jaw_field.dart) — só Δx, amplitude `t * 0.04 * faceWidth`, handles/gônios via catálogo |
| **Renderer** | `BackwardBilinearWarp` via `applyJawWarp` |
| **Controller** | `BeautyEngineController.applyJawWarp` — `parameters['jaw']`; `t<=0` ou sem face → identidade, sem renderer |
| **Preview** | `_renderTexture`: primeiro passo facial |
| **Export** | não-tiled = `_renderTexture`; tiled = `applyJawWarp` no frame inteiro |
| **Testes** | [`facial_warp_v2_jaw_field_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_jaw_field_test.dart), [`facial_warp_v2_lab_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_lab_test.dart), contrato renderer/displacement; Device Lab jaw-only |
| **Dependências** | `DisplacementField`, `RegionMasks`, `V2RegionCatalog`, `FaceMeshResult` |
| **Não depende** | Chin, Face Slim, MLS |

---

### 1.3 Ficha — `chin`

| | |
|---|---|
| **Key** | `chin` |
| **Label** | Queixo |
| **Status** | **vivo** (Sprints A–E fechadas; relatório E) |
| **Field** | [`ChinField`](../../lib/features/editor/beauty_engine/warp/v2/chin/chin_field.dart) — Δy no mento; hard-zero local nos IDs Jaw `{58,288,132,361}+{172,136,365,397}` |
| **Renderer** | `BackwardBilinearWarp` via `applyChinWarp` |
| **Controller** | `applyChinWarp` — `parameters['chin']` |
| **Preview** | `_renderTexture`: segundo passo (entrada = RGBA já do Jaw) |
| **Export** | igual ao preview; tiled no frame inteiro a seguir ao Jaw |
| **Testes** | [`facial_warp_v2_chin_field_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_chin_field_test.dart), [`facial_warp_v2_chin_lab_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_chin_lab_test.dart) |
| **Dependências** | módulo `chin/` (máscaras/métricas próprias); IDs Jaw **duplicados**, sem importar `jaw_field.dart` |

---

### 1.4 Ficha — `face_slim`

| | |
|---|---|
| **Key** | `face_slim` |
| **Label** | Afinar rosto (l10n) |
| **Status** | **lab** (módulo A/B). Também **fantasma** no modelo/preset e **legado** no MLS |
| **Field** | [`FaceSlimField`](../../lib/features/editor/beauty_engine/warp/v2/face_slim/face_slim_field.dart) + máscaras/métricas no mesmo módulo |
| **Renderer** | só nos testes de lab; **não** há `applyFaceSlimWarp` |
| **Controller / Preview / Export** | não ligado. `_renderTexture` não lê `face_slim` |
| **Testes** | [`facial_warp_v2_face_slim_field_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_face_slim_field_test.dart), [`facial_warp_v2_face_slim_lab_test.dart`](../../test/beauty_engine/warp/v2/facial_warp_v2_face_slim_lab_test.dart) |
| **UI** | **não** está em `faceWarpParameterKeys` |
| **Outras referências** | `FaceParams.faceSlim`, `BeautyPreset.toParameterMap()['face_slim']`, `ToolGateEngine` cases `face_slim`, Device Lab `blockingKeys`, `MlsWarpEngine._resolveIntensity` default `'face_slim'` |
| **Contrato do Field** | não desloca domínio Jaw/Chin (hard-zero em 58/288/152). Sprint C/D/E **não** feitas |

---

### 1.5 Fichas — keys fantasma (modelo sem pipeline V2)

Todas existem em [`face_params.dart`](../../lib/features/editor/beauty_engine/models/face_params.dart) e entram no mapa de preset. **Nenhuma** está no painel. **Nenhum** Field V2. **Nenhuma** chamada em `_renderTexture`.

| Key | Label | Gate / outro | Status |
|---|---|---|---|
| `narrow_face` | Estreitar rosto | `ToolGateEngine` + Device Lab block | fantasma |
| `v_face` | Rosto em V | idem | fantasma |
| `cheekbone` | Maçãs do rosto | `FaceWarpUtils.cheekboneLeft/Right`; `PassCheekboneContour` é shader de contorno, não este slider | fantasma |
| `forehead` | Testa | — | fantasma |
| `temple` | Têmporas | — | fantasma |
| `head_size` | Tamanho da cabeça | label; excluído do body pipeline (teste) | fantasma / ausente no painel |
| `nose_slim`, `nose_length`, `nose_height`, `nose_tip`, `nose_bridge` | nariz | gate parcial | fantasma |
| `eye_scale`, `eye_distance`, `eye_height`, `eye_rotation`, `double_eyelid` | olhos | gate; parity checklist ainda cita `eye_scale` | fantasma |
| `mouth_width`, `lip_thickness`, `smile` | boca | gate lábios | fantasma |

Docs [`07-face-filters.md`](./07-face-filters.md) e [`30-estado-atual-arquitetura.md`](./30-estado-atual-arquitetura.md) listam estas keys como filtros implementados. Em `filters/face/` **não há** `jaw.dart` / `cheekbone.dart` / etc. — só pipeline mínima + pele/máscaras. Esses docs descrevem o sistema **abandonado**, não o `_renderTexture` actual.

---

### 1.6 Ficha — `skin_smooth` (e pele)

| | |
|---|---|
| **Key** | `skin_smooth` |
| **Status** | **shader** (vivo na secção Pele) |
| **Field** | nenhum |
| **Renderer** | `SkinFilterPipeline` → `RenderShaders.skinEngine` |
| **Preview / Export** | depois do warp facial, no ramo GPU |
| **Não é** | reshape de silhueta |

---

### 1.7 Legado que ainda menciona sliders mortos

| Sítio | O que prova |
|---|---|
| [`mls_warp_engine.dart`](../../lib/features/editor/beauty_engine/warp/mls_warp_engine.dart) `_resolveIntensity('face_slim'…)` | MLS ainda trata `face_slim` como intensidade default |
| `test/golden/goldens/v3_jaw.png`, `v3_chin.png`, `v3_pilot_face_slim.png` | goldens V3, não V2 |
| [`tool_gate_engine.dart`](../../lib/features/editor/beauty_engine/tools/tool_gate_engine.dart) cases `face_slim` / `narrow_face` / `v_face` | gate para keys que o registry **não** lista em `_face` |
| [`parity_checklist_engine.dart`](../../lib/features/editor/beauty_engine/quality/parity_checklist_engine.dart) | B3 jaw, B4 chin, B5 `eye_scale` (eye_scale não é vivo) |
| [`FaceWarpUtils`](../../lib/features/editor/beauty_engine/filters/face/face_warp_utils.dart) | conjuntos cheekbone/lábios da era Sprint 10–13; pele ainda lê cheekbone para máscara |

---

## 2. Comparação com o Meitu

Evidência Meitu: ecrãs do produto (ícones com **traço tracejado / setas = área de influência**). Não há “Face Slim” nesses ecrãs.

| Slider Meitu | Ícone (área marcada) | Existe hoje? | Região principal (pelo ícone) | Pode reaproveitar algo? | Observações |
|---|---|---|---|---|---|
| **Jawline** | Perfil; tracejado no contorno da mandíbula **até ao pescoço** | `jaw` **vivo**, mas só Δx no domínio Jaw V2; pescoço não entra | Jaw (+ pescoço no Meitu) | **Sim — `JawField`** | O nosso slider chama-se Mandíbula, não Jawline. Não há Neck Field. |
| **Chin Length** | Frente; dois traços horizontais **na base do mento** | `chin` **vivo** (Δy) | Chin | **Sim — `ChinField`** | Correspondência mais directa da auditoria. |
| **V Chin** | Frente; ponta do mento a tracejado, mais aguda | `v_face` **fantasma**; Chin vivo é length, não ponta em V | Chin | Parcial: geometria Chin; não há Field de “ponta” | Não está no painel. |
| **V shape** | Setas longas da bochecha ao queixo | ausente (`v_face` é o nome mais próximo, sem Field) | Cheek + Jaw + Chin (ícone atravessa as três) | Não há Field que cubra este arco | Distinto de V Chin no Meitu (dois ícones). |
| **Cheekbones** | Setas **para dentro** à altura das maçãs | `cheekbone` **fantasma**; hulls 123/411 no Face Slim e em `FaceWarpUtils` | Cheek | Geometria de landmarks, não um Field de produto | Face Slim **não** é este slider (protege gônios e não é cheek-only). |
| **Width** | Setas/suportes na **base da mandíbula** (estreitar largura) | **ausente** | Jaw (largura inferior) | `JawField` é Δx nos gônios — o mais próximo | Não há key `width`. |
| **Temple** | Tracejado nas têmporas (alto, lateral) | `temple` **fantasma** | Temple | Landmarks oval/forehead no catálogo; sem Field | Fora do domínio Jaw/Chin. |
| **Hairline** | Tracejado no **topo** da testa | **ausente** (`forehead` é fantasma, sem Field) | Forehead / hairline | Catálogo `forehead` em `MeshTopology` | Não há key `hairline`. |
| **Jaw Angle** | Setas para dentro nos **cantos** da mandíbula (gônio) | **ausente** como slider; o `JawField` **já mexe gônios** | Jaw (gônio) | Parte do Jaw actual, não um produto separado | Separar Jawline vs Jaw Angle é decisão de produto, não de código existente. |
| **Lift** | Setas para **fora/baixo** nos cantos do maxilar | **ausente** | Jaw / cheek inferior | Nada dedicado | Aparece no Meitu ao lado de Width/Temple. |
| **Narrow Face** | (não está nestes ecrãs) | `narrow_face` **fantasma** | — | Não | Nome interno; overlap conceptual com Width / V shape. |
| **Face Slim** | **não aparece** nos ecrãs | `face_slim` **lab** + fantasma + legado MLS | — | Não como slider | Ver secção 5. |
| **Double Chin** | Perfil; traços **debaixo** do queixo/pescoço | **ausente** | Chin + Neck | Chin não trata papada; sem Neck | |
| **Smooth** | Silhueta esquerda a tracejado; badge premium | `skin_smooth` é **shader de pele**, outra família | (Meitu: contorno/pele; incerto se é o nosso smooth) | Não mapear 1:1 sem mais ecrãs | O nosso Smooth de produto é Pele, não Rosto. |
| **Whole Pro** | (parcial nos ecrãs; badge Free) | **ausente** | preset / combo | Presets existem; não é um Field | Fora do reshape regional. |
| **Geral** | dropdown ao lado do slider | n/a | UI | Painel já tem categorias | Não é warp. |

---

## 3. Região × slider

**Região** = sítio anatómico (Jaw, Chin, Cheek, Temple, Forehead, Neck).  
**Slider** = controlo que o Meitu expõe. Um slider marca uma área no ícone; isso **não** implica um algoritmo com o mesmo nome.

O que os ícones Meitu marcam (só o desenho, sem inferir pesos):

| Slider Meitu | Áreas no ícone |
|---|---|
| Jawline | Mandíbula + transição para o pescoço (perfil) |
| Chin Length | Base do mento, eixo vertical |
| V Chin | Ponta / arco inferior do mento |
| V shape | Faixa da mid-face até ao queixo (bochecha + mandíbula + mento) |
| Cheekbones | Mid-face lateral, à altura das maçãs |
| Width | Largura da base da cara / gônios |
| Temple | Terço superior lateral (têmpora) |
| Hairline | Limite cabelo / testa no topo |
| Jaw Angle | Canto da mandíbula (gônio), sob a orelha |
| Lift | Cantos inferiores da cara, para fora |
| Double Chin | Submento / pescoço (perfil) |
| Smooth | Bordo da silhueta (ícone não nomeia osso) |
| Face Slim | — (não está no menu fotografado) |
| Narrow Face | — (não está no menu fotografado) |

O que **nós** temos, no mesmo vocabulário:

| Região | Slider nosso que a pisa | Notas |
|---|---|---|
| Jaw | `jaw` | Gônios no Field; Chin e Face Slim forçam zero nesse domínio |
| Chin | `chin` | Mento; não é V Chin nem Double Chin |
| Cheek | nenhum vivo | Landmarks em Face Slim / `FaceWarpUtils`; key `cheekbone` morta |
| Temple | nenhum vivo | key `temple` morta |
| Forehead / hairline | nenhum vivo | key `forehead` morta |
| Neck | nenhum | Jawline e Double Chin Meitu passam aqui; body tem `neck_slim` (corpo, não face V2) |

`jaw` e `chin` no produto **não se misturam no Field**: cada um zera o domínio do outro. No Meitu, Jawline e Chin Length são sliders **distintos** com áreas **adjacentes** no ícone — não um único “Face Slim”.

---

## 4. Reaproveitamento

### Reaproveitar exactamente como está

| Peça | Porquê |
|---|---|
| `JawField` + `applyJawWarp` + testes de contrato | Único reshape de mandíbula no produto. Preview e export já o usam. |
| `ChinField` + `applyChinWarp` + testes A–E | Único reshape de mento no produto. Δy corresponde ao ícone Chin Length. |
| `BackwardBilinearWarp` / `DisplacementField` | Contrato V2 estável; os dois sliders vivos já passam por aqui. |
| Painel Rosto com duas keys | O catálogo de produto **já** é curto; não é o menu fantasma do `FaceParams`. |
| Lab p01/p05/p12 | Mesmas fotos para qualquer slider novo. |

### Só nomenclatura (produto, não código nesta etapa)

| Hoje | Nome Meitu mais próximo | Porquê não é rename no código ainda |
|---|---|---|
| label “Mandíbula” / key `jaw` | Jawline | O Field não cobre o pescoço do ícone Jawline. Renomear a key quebraria presets/`parameters['jaw']`. |
| label “Queixo” / key `chin` | Chin Length | O Field é shortening vertical. O nome Meitu é o correcto para o que o código faz. |

Qualquer rename de **key** é breaking de preset. Só label de UI, se for caso.

### Arquivar (deixar de tratar como feature)

| Peça | Porquê |
|---|---|
| `face_slim` como slider / Sprint C–E | Não está no Meitu fotografado; não está no painel; o Field foi desenhado para **não** ser Jaw nem Chin (hard-zero nos gônios). Ver §5. |
| `narrow_face` como slider | Sem Field, sem UI, sem ícone Meitu nestes ecrãs. |
| Docs 07 / 30 / 31 como mapa do sistema actual | Descrevem MLS/ACE/22 tools. O painel tem 2. |
| Promover goldens `v3_pilot_face_slim` | Pipeline morta. |

Arquivar **não** exige `rm` nesta auditoria. Significa: não Sprint C, não slider, não export.

### Nunca deveria virar slider próprio (com o código actual)

| Conceito | Porquê |
|---|---|
| **Face Slim** | Não está no Meitu. O módulo tenta o mid-face **e** a silhueta mandibular **sem** gônio — isso é o contrário de Jawline + Cheekbones + Width, que o Meitu separa. |
| **Narrow Face** (key actual) | Duplica o papel de Width / V shape sem implementação. |
| **Jaw Angle** como terceiro Field **antes** de Jawline estar estável | Os gônios **já** são o alvo do `JawField`. Um segundo slider no mesmo sítio sem produto aceite = dois operadores no mesmo domínio (o problema do Face Slim). |
| Qualquer key fantasma de nariz/olho/boca **como “já existe”** | Só há struct + label. Não há Field V2. |

---

## 5. Face Slim — conclusão

**B) Face Slim deve ser arquivado definitivamente e tratado apenas como experimento de laboratório.**

Motivos técnicos (evidência):

1. **Produto:** o painel e o `_renderTexture` não o chamam. Não há `applyFaceSlimWarp`.
2. **Meitu:** os ecrãs de reshape mostram Jawline, Width, Jaw angle, V shape, V chin, Chin length, Cheekbones, Temple, Hairline, Lift, Double chin, Smooth. **Face Slim não está nessa fila.**
3. **Geometria:** o Field actual é um operador de silhueta (spline mandibular + máscara de anel) com **hard-zero em 58/288/152**. Jawline no Meitu **marca** a mandíbula (e o pescoço). Cheekbones marca o mid-face. Face Slim tenta os dois e proíbe o gônio — por isso a quina no término do envelope (lab de silhueta, p05/p12 direita: pico de Δθ onde o campo é forçado a zero).
4. **Contrato:** o plano Face Slim declara PARADA se o efeito só funcionar mexendo gônios. O Meitu Jawline/Width/Jaw angle **existem para mexer nessa zona**. Continuar o Face Slim é optimizar um slider que o produto de referência não expõe.
5. **Estoque:** spline, envelope em arco e hulls 123/411 podem informar **outros** sliders no futuro. Isso não justifica C/D/E nem o nome `face_slim` no painel.

---

## 6. Roadmap de produto

Ordem justificada pelo que **já está vivo** e pelo que o Meitu **separa nos ícones**. Cada item = um slider de produto com Field próprio, no contrato V2 actual (um Field, um remap, sprints A–E). Sem mudar regras nesta etapa.

1. **Manter Jaw** — já é o reshape de mandíbula/gônio. Alinhar o entendimento de produto a **Jawline** (área do ícone), sem pedir pescoço ainda.
2. **Manter Chin** — já é **Chin Length** (Δy no mento). Não o esticar para V Chin ou Double Chin.
3. **Arquivar Face Slim como feature** — lab pode ficar no disco; sem C/D/E; sem key no painel.
4. **Cheek / Cheekbones** — único buraco mid-face com landmarks já nomeados (123/411, `FaceWarpUtils`). O Meitu isola esta área das têmporas e do gônio.
5. **Temple** — ícone Meitu distinto, acima das maçãs; Jaw/Chin não chegam lá.
6. **Hairline** — ícone no topo; `forehead` é só um nome morto.
7. **Width** — ícone na base da cara; decidir se é o mesmo domínio do Jaw (aí é calibração do slider Jaw, não um terceiro anti-gônio) ou um Field à parte **depois** de Jawline estar aceite visualmente.
8. **Jaw Angle** — só se o produto quiser o canto **separado** da Jawline; hoje o `JawField` já vive nos gônios.
9. **V Chin** — ponta do mento; não reutilizar Chin Length sem C visual próprio (o ícone é outro).
10. **V shape** — atravessa cheek+jaw+chin no ícone; só depois das três regiões existirem como sliders, senão vira outro monolito tipo Face Slim.
11. **Lift / Double Chin** — Double Chin pede pescoço/submento (não temos). Lift é direcção oposta à Width no mesmo andar.

Parar e rever o menu depois de 4–6. Não avançar V shape / Face Slim / Narrow Face como nomes de produto.

Arquitectura de como vários sliders passam a coexistir no mesmo frame **fica para depois** desta lista de produto estar aceite.
