# Plano — Face Rig (regiões + receitas)

**Estado:** análise. Sem código nesta etapa. Não altera Jaw, Chin, Face Slim, renderer nem o produto.

**Hipótese:** o módulo `FaceSlim` modela uma feature que o produto de referência não expõe. Os sliders comerciais (Jawline, Chin Length, V Chin, Cheekbones, Temple) são **receitas** sobre um rig anatómico, não operadores 1:1.

Este documento não substitui [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Qualquer migração **exige emenda explícita** das regras (secção 0). Até essa emenda, o plano é inválido como implementação.

---

## 0. Conflito com o contrato V2 vigente

Hoje o produto é:

```
slider 'jaw'  → JawField(t)  → BackwardBilinearWarp
slider 'chin' → ChinField(t) → BackwardBilinearWarp
```

Ordem no preview/export: RGBA → Jaw → Chin → Body → Skin → Color.

As regras proíbem, hoje:

- mixer / `CompositeField` / orquestrador extra (§2.4, §8)
- somar campos (§2.4)
- um Field importar outro Field (§3)
- alterar `DisplacementField` (§7.2)
- Face Slim deslocar gônios `{58, 288}` (plano Face Slim = PARADA)

O rig comercial precisa de **blend em espaço de campo** (não de um warp por slider):

```
d = Σ recipe[region] * Region.build(face, size, t=1)
BackwardBilinearWarp.apply(d)   // um remap
```

Isso não cabe nas regras actuais. **Fase 0 = decidir se as regras mudam.** Sem isso, não há código.

Composição sequencial (Jaw depois Chin, como agora) **não** reproduz `60% Jaw + 20% Chin`: o segundo warp vê a imagem já deformada, a mistura não é linear, e cada passe reamostra. Receitas Meitu-like exigem soma ponderada de campos-base, depois **um** remap.

---

## 1. O que o Face Slim pode reaproveitar como região

O Face Slim actual **não** é uma região Cheek. É um operador de silhueta mandibular com Cheek no nome.

| Peça no `face_slim/` | O que realmente é | Destino no rig |
|---|---|---|
| Catmull-Rom zigoma→mento (`leftJawChain` / `rightJawChain`) | geometria da **mandíbula desta cara** | **Jaw** (direcção / spline) |
| projecção no segmento + normal interior da tangente | direcção do warp da silhueta | **Jaw** |
| envelope C¹ em arc-length (`sin²`) | fade ao longo da curva, não em Y | **Jaw** (e padrão para Cheek/Temple) |
| oval só como domínio `slimActive` | recorte da região | padrão de máscara de qualquer região |
| onion fade na fronteira | C⁰/C¹ na borda da máscara | padrão de região |
| handles 123/411, hulls de bochecha | miolo da face, longe do gônio | **Cheek** |
| protecções olhos/nariz/boca/orelhas | hard-zero de features | protecções **globais do rig**, não de um slider |
| hard-zero de `{58,288,132,361}` + domínio Chin | anti-região: o Face Slim existe para **não** ser Jaw/Chin | **apagar no modelo de regiões** — a quina de ~20° nasceu daqui |
| métricas `faceSlimNarrows` / primários 123–411 | gate de um slider que não deve existir | lab de **Cheek**, não produto |
| dumps de continuidade / silhueta | ferramenta de lab | reutilizar no lab de regiões |

Conclusão: a spline mandibular do Face Slim é o candidato a **evolução geométrica do Jaw**, não a um “Face Slim”. O Jaw aprovado hoje é Lorentziano nos gônios, só Δx. O Face Slim já faz Δx+Δy pela normal da spline. Fundir isso no Jaw **quebraria** o Jaw aprovado se for feito no sítio. O caminho incremental é uma região `jaw` **nova** (ou `jaw_v2` no módulo, sem editar `jaw_field.dart`) até a Sprint C da região substituir o slider.

O que **não** reaproveitar como Jaw: o hard-zero nos gônios, o `lateralGate`, o DT do oval como direcção, o kernel Lorentziano das bochechas (já abandonado no Field).

---

## 2. O que está acoplado e deve virar independente

```
hoje                          alvo
─────────────────────────────────────────────────────
slider = Field = warp         slider = receita
                              região = Field(t=1)
                              blend = Σ w·região
                              warp = 1× renderer

FaceSlim contém               Jaw contém spline
  spline mandibular             mandibular
  máscara de bochecha         Cheek contém hull 123/411
  anti-gônio                  nenhuma região “protege”
  anti-mento                    as outras: o blend é que
                                limita o peso

Chin hard-zero nos gônios     Chin morre no próprio
                              envelope, perto da boca

Jaw / Chin / FaceSlim         regiões não se importam
  duplicam IDs e máscaras     umas às outras
```

Acoplamentos concretos a partir:

1. **Produto 1:1** — `parameters['jaw']` chama só `JawField`. `FaceFilterPipeline.faceWarpParameterKeys = ['jaw','chin']`. Keys órfãs já existem na UI/l10n (`face_slim`, `v_face`, `narrow_face`, `cheekbone`, `temple`) sem Field V2.
2. **Anti-domínio** — Chin e Face Slim copiam `{58,288,132,361}` para forçar zero. Isso é o substituto pobre de “esta região não é aquela”.
3. **Isolamento de módulos** — correcto para não um Field editar o outro; incorrecto se impede um **blend** acima dos Fields.
4. **Pipeline sequencial** — `applyJawWarp` depois `applyChinWarp` no controller e no export tiled. Dois remaps. O rig quer um.
5. **Contrato Jaw congelado** — `jaw_field.dart` + testes de contrato. Não se “organiza” Jaw para caber o rig. O slider `jaw` continua a chamar o Field aprovado até uma C da região nova.

Independentes no alvo:

```
warp/v2/rig/          # novo, só depois da emenda
  recipes.dart        # slider → pesos de região (dados)
  blend.dart          # Σ w_i * field_i  (lê DisplacementField; não o altera)

warp/v2/jaw/          # já existe na raiz: jaw_field.dart (não mover agora)
warp/v2/chin/         # já existe
warp/v2/cheek/        # nascer da geometria de bochecha do Face Slim
warp/v2/temple/       # depois
warp/v2/neck/         # depois (body/face boundary — risco: regra §7.9)
```

Cada região: `build(face, size, t)` como hoje. O blend chama `t=1` e escala. Os Fields **continuam sem se importar**.

---

## 3. O que pode sair sem quebrar o pipeline de produto

O preview e o export **não ligam** Face Slim. `applyFaceSlimWarp` não existe. Pipeline viva: Jaw → Chin → Body → Skin → Color.

Pode parar já, sem `rm -rf` e sem tocar em Jaw/Chin:

| Remover / congelar | Impacto no produto |
|---|---|
| Sprints C/D/E do Face Slim | nenhum — ainda não há slider V2 |
| Lab extra de continuidade (isolines, silhueta) | nenhum — só testes |
| Key `'face_slim'` no Device Lab (`blockingKeys`) | Device Lab já ignora o efeito; manter o block |
| MLS / `FaceWarpV3Config` / labels `face_slim` | **não mexer nesta migração** (resíduos V1, regra §9.10) |

Não apagar `warp/v2/face_slim/` nesta fase. É estoque de geometria (spline, envelope, máscara oval). Apagar só depois de Cheek (e eventualmente Jaw-spline) terem copiado o que precisam, com testes verdes.

Não desligar Jaw nem Chin.

---

## 4. Migração incremental (compatível com sliders actuais)

Princípio: **receitas identidade** até C visual de cada receita nova.

```
'jaw'  → { jaw: 1.0 }     # comportamento byte-igual ao actual
'chin' → { chin: 1.0 }     # idem
```

Sliders novos (`v_face`, `cheekbone`, `temple`) só entram com receita + regiões já com C. O slider `face_slim` **não se promove**. Se um dia o painel precisar de “afinar rosto”, vira receita (`cheek + jaw + temple`), não o módulo actual.

### Fase 0 — Decisão (zero código)

Emenda às regras V2, ou o plano para. Texto mínimo a aprovar:

1. Um **slider de produto** pode mapear-se a uma receita de regiões.
2. Regiões continuam Fields autocontidos (`build(face, size, t)`).
3. Blend = soma ponderada de `DisplacementField` **sem** alterar a classe `DisplacementField`; o loop vive num ficheiro novo que só lê `dx`/`dy`.
4. Um único `BackwardBilinearWarp.apply` por frame facial (em vez de um por slider).
5. Jaw e Chin aprovados ficam o fallback 1:1 até a receita identidade ser verificada no lab (t=0 identidade; t>0 hash de `v2Raw` igual ao Jaw-then-Chin actual, ou delta documentado).
6. Continua proibido: Field importar Field; fill/Telea; segunda pipeline; MLS facial.

Se 4) (um remap) falhar o teste de paridade com Jaw-then-Chin, a Fase 1 documenta PARADA e não se inventa um mixer no controller.

### Fase 1 — Blend mínimo, receitas identidade (lab only)

- `recipes.dart`: `'jaw' → jaw: t`, `'chin' → chin: t`.
- `blend.dart`: soma `JawField.build(..., t: wJ)` + `ChinField.build(..., t: wC)` **sem os Fields se conhecerem** (o lab/controller é que chama os dois, como hoje, mas soma campos em vez de warpar duas vezes).
- Lab: p01/p05/p12 × jaw/chin 0/25/50.
  - Controlo A: pipeline actual (dois remaps).
  - Controlo B: um remap da soma.
- Gate: se B ≠ A de forma visível, **não** se promove B. Ou aceita-se B como modelo novo (sign-off) ou aborta-se o rig.

Rollback: apagar `warp/v2/rig/`. Jaw/Chin/controller iguais.

### Fase 2 — Slider `jaw` / `chin` passam a 1 remap com receita identidade (produto)

Só se Fase 1 B for aceite.

- Controller: um `applyFaceRigWarp` que substitui `applyJawWarp`+`applyChinWarp` **com o mesmo resultado** das receitas `{jaw:1}` / `{chin:1}` (ou soma se ambos > 0).
- Export tiled: o mesmo grafo.
- Testes de contrato Jaw/Chin de **Field** não mudam. Muda só o wiring D/E.

Rollback: repor as duas chamadas sequenciais.

### Fase 3 — Região Cheek (nasce do Face Slim, sem ser Face Slim)

- Módulo `warp/v2/cheek/` no template A–C.
- Geometria: hulls 123/411 + direcção para a midline. **Sem** spline mandibular completa. **Sem** hard-zero nos gônios (o envelope da própria máscara morre antes).
- Não entra no produto até C.
- Face Slim permanece no disco, não é chamado.

### Fase 4 — Receitas novas (produto)

Só depois de Cheek C:

| slider (já existe na l10n / preset) | receita inicial (calibrar no lab) |
|---|---|
| `v_face` | chin 0.5 + jaw 0.3 + cheek 0.2 |
| `cheekbone` | cheek 0.8 + jaw 0.1 + temple 0.1 (temple=0 até existir) |
| `temple` | espera região Temple |
| `face_slim` / `narrow_face` | **não expor**; se algum dia, cheek 0.6 + jaw 0.3 + temple 0.1 |

O slider `jaw` **não** passa a `0.6 Jaw + 0.2 Chin + …` nesta fase. Isso mudaria o Jaw que o utilizador já tem. Recalibrar receitas dos sliders antigos é um documento próprio, depois do rig estável.

### Fase 5 — Spline mandibular na região Jaw (opcional)

Copiar do Face Slim para um **novo** construtor no módulo Jaw, ou `jaw/jaw_spline_field.dart`, sem editar o `JawField` Lorentziano até C da alternativa.

Gate: gônios **podem** mover (é a região Jaw). A quina do Face Slim deixa de ser um problema desta região.

### Fase 6 — Arquivar Face Slim

Quando Cheek (e opcionalmente Jaw-spline) tiverem o que precisam:

```
# não fazer agora
# rm só após C das regiões sucessoras
```

Testes Face Slim saem do `flutter test test/beauty_engine/warp/v2/` ou ficam marcados como arquivo. Jaw/Chin/renderer intactos.

---

## 5. Fases pequenas e reversíveis (resumo)

```
0  emenda das regras          [decisão]     reversível: não fazer
1  blend lab, receita 1:1     [lab]         rm warp/v2/rig/
2  um remap no produto        [D/E]         repor applyJaw+applyChin
3  Cheek Field                [A–C]         rm warp/v2/cheek/
4  receitas v_face/cheekbone  [produto]     receitas identidade
5  Jaw spline (opcional)      [A–C]         não tocar Lorentziano
6  arquivar face_slim         [limpeza]     git revert do delete
```

Nenhuma fase funde a seguinte. Nenhuma edita o renderer. Nenhuma reabre MLS/ROI.

---

## 6. Mapa do que existe hoje (para não inventar)

**Produto vivo:** sliders `jaw`, `chin` na página do editor. Controller `applyJawWarp` / `applyChinWarp`. Export tiled igual.

**Keys sem Field V2:** `face_slim`, `narrow_face`, `v_face`, `cheekbone`, `temple`, `forehead`, nariz, olhos, boca (labels + presets). Device Lab bloqueia `chin`/`v_face`/`face_slim`/`narrow_face` quando o dump é jaw-only.

**Face Slim:** módulo + testes A/B. Não está no controller. Continuar C seria promover um slider que o rig torna obsoleto.

**Infra congelada a preservar:** `DisplacementField`, `WarpRequest`, `WarpResult`, `BackwardBilinearWarp`, testes de contrato Jaw/renderer.

---

## 7. O que este plano não faz

- Não implementa blend, receitas, Cheek nem UI.
- Não apaga `face_slim/`.
- Não muda o comportamento visual de `jaw` / `chin` sem paridade de lab.
- Não introduz Neck se isso forçar mexer em body (§7.9) — Neck é fase posterior com parada explícita se cruzar a fronteira.
- Não promete paridade Meitu (regra §9.9). Promete um rig em que os sliders deixam de ser campos monolíticos.

---

## 8. Veredicto

A quina de ~20° no Face Slim é o sintoma de um operador único a respeitar o gônio de outro operador. No rig, o Jaw move o gônio; o Cheek não chega lá; o slider “Jawline” mistura os dois com pesos. Não há hard-zero entre eles.

**Próximo passo único:** aprovar ou rejeitar a emenda da secção 0. Só depois existe Fase 1.
