# PROJECT_CONTEXT — Facial Warp V2

**Fonte oficial do estado do projeto.**  
Última actualização: 2026-09-02 (distância euclidiana partilhada nos seis Fields; geometria e calibrações intactas)

Todo chat novo começa aqui. Segue **somente** o estado deste ficheiro.  
Hipóteses antigas que não estejam neste documento **não existem**.

Contrato permanente (não substitui este ficheiro): [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md).

---

## Como usar

1. Ler este ficheiro primeiro.
2. Tratar o conteúdo como a memória canónica: decisões, estado, proibições, sprint actual.
3. Ignorar relatórios históricos, planos congelados e conversas anteriores quando contradisserem este documento.
4. Qualquer decisão nova, mudança de sprint, aprovação ou arquivo **actualiza este ficheiro no mesmo turno**. Sem memória só no chat.

---

## Papel da IA

A IA actua como **arquitecto** do Facial Warp V2.

- Sempre **criticar antes de implementar**.
- Sempre **propor documentação antes de código**.
- Sempre **entregar prompts em Markdown** para o Leonardo encaminhar ao Cursor (implementação noutro chat, se necessário).
- Não avançar sprint sem aprovação explícita escrita.
- Não “resolver em silêncio” uma contradição com este documento ou com as regras V2.

---

## Estado actual

| Peça | Estado |
|---|---|
| **Jaw** | Aprovado. Vivo no produto (`jaw`). Reaberto 2026-09-02 **só** para a crista em polilinha (serrilhado); amplitude e gônios intactos. Pendente assinatura visual. Depois disso, encerrado outra vez. **Intacto** no Jaw Angle. |
| **Jaw Angle** | Em inspecção. Key `jaw_angle` («Ângulo da mandíbula»). Sem C. Relatório [`v2-jaw-angle.md`](./v2-jaw-angle.md). |
| **Chin** | Reaberto **só** para calibração bipolar Chin Length e, em 2026-09-02, para a crista contínua, que tirou a dobra a t=1 (`minDetJ` −0,046 → +0,31). Vivo (`chin`, «Tamanho do queixo»). Não assinado no editor. Relatórios [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md) e [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md). **Intacto** no Jaw Angle. |
| **V Chin** | Aprovado. Vivo no produto (`v_chin`, «V do queixo»). Reaberto 2026-09-02 **só** para a crista contínua, que tirou a dobra do extremo positivo (`minDetJ` −0,40 → +0,30); amplitude e aspecto intactos (pico do peso 1,0000 → 0,9994). Pendente assinatura visual; depois disso encerrado outra vez. Relatórios [`v2-v-chin.md`](./v2-v-chin.md) e [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md). |
| **V Shape** | Em inspecção. Key `v_shape` («Formato V»). Sem C. Relatório [`v2-v-shape.md`](./v2-v-shape.md). **Intacto** no Jaw Angle. |
| **Face Slim** | Arquivado. Lab A/B no disco. Sem C/D/E. Sem slider. Não promover. Não renomear para Cheekbones. |
| **Roadmap de produto** | Aprovado. Adenda: V Shape em inspecção. Face Rig congelado. |
| **Cheekbones** | Em desenvolvimento. Hipótese H vigente (crista oval). Inspecção no editor. Sem C. Relatório [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). **Intacto** no Jaw Angle. |

Pipeline viva no produto:

```
RGBA → applyFaceWarpChain → Body → Skin → Color
```

`applyFaceWarpChain` percorre, nesta ordem, `jaw → jaw_angle → chin → v_chin → v_shape → cheekbone`. Etapa com slider em identidade é saltada. Preview (`_renderTexture`) e export (`TiledExportEngine`) usam o **mesmo** método, para não existirem duas ordens possíveis. As seis `applyXWarp` continuam públicas e inalteradas, para uso isolado e testes.

Entre etapas os landmarks são **advectados** para a geometria já deformada (`warp/v2/landmark_advection.dart`). Sem isso o efeito a jusante recebia o RGBA deformado mas media a geometria da origem, e a crista caía 6–10 px fora da silhueta. Ver [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md).

Cheekbones está na cadeia de preview/export como inspecção da hipótese H. **Não** é Sprint C/D aprovada. V Chin está na mesma cadeia, **aprovado**. V Shape e Jaw Angle estão na cadeia como inspecção.

---

## Arquitectura

Única pipeline facial:

```
Field
  ↓
DisplacementField
  ↓
BackwardBilinearWarp
```

- Cada efeito gera **apenas um** `DisplacementField`.
- O renderer é estável: `src = dest − displacement`.
- Sem clamp à borda. Sem Telea. Sem hole-fill.
- Nenhum Field importa outro Field V2.
- Infra congelada: `DisplacementField`, `WarpRequest`, `WarpResult`, `BackwardBilinearWarp`.
- Catálogo compartilhado é **append-only** relativamente a efeitos aprovados.
- Distância é **euclidiana exacta** e vive num só sítio: `warp/v2/distance_transform.dart` (`EuclideanDistanceTransform`). Rampa de fronteira e `RegionMaskRaster.dilate` usam-na. Não reintroduzir chamfer L1 (4 vizinhos, custo 1): mede em Manhattan, dá isolinhas em losango a 45° e imprime escada nas silhuetas oblíquas. Ver [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).
- A composição é **encadeamento de remaps com advecção de landmarks**, num só sítio: `warp/v2/landmark_advection.dart`. Cada efeito mede a geometria da imagem que recebe, não a da origem. Nunca somar os `DisplacementField` dos seis num campo único: com todos no extremo a soma inverte (`minDetJ ≈ −0,7`), enquanto encadear remaps injectivos preserva a garantia. Ver [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md).
- Peso de crista vive num só sítio: `warp/v2/ridge_weight.dart` (`RidgeWeight`). A distância é à polilinha, mas o peso **nunca** vem só do segmento vencedor: na medial axis dois segmentos empatam, as projecções caem em pontos de peso diferente e o peso dá um degrau — no `v_chin` isso punha `∂dx/∂x` em −1,4 e invertia o warp. O peso é a média dos segmentos ponderada por proximidade, e interpola ao longo da crista por smoothstep: com interpolação linear o pico num vértice interior sai em bico, o que no `v_shape` levava o gradiente de +0,33 a −0,45 num ponto. Os seis efeitos estão migrados.
- Rampa de fronteira vive num só sítio: `warp/v2/boundary_feather.dart` (`BoundaryFeather`). A rampa crua `min(1, dist / falloff)` herda o bico da medial axis do domínio, onde a distância tem máximo interior e o gradiente salta `2 / falloff`: era a linha diagonal a meio da bochecha com Mandíbula e Formato V no extremo. A rampa é borrada com três passagens de caixa, e perto da fronteira **mistura-se** de volta à rampa crua — o borrão sozinho desfaz o zero da borda (salto de 1,3 px, `minDetJ` −0,20) e uma porta multiplicativa aperta a rampa pelo factor 1,5 do smoothstep (`chin` a −0,007). Ver [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

---

## Nunca

É proibido:

- MLS no renderer
- Face Rig (plano congelado; inválido como implementação)
- Receitas (blend ponderado de regiões / sliders compostos)
- Slider composto
- Alterar Jaw
- Alterar V Chin
- Alterar Chin **fora** da calibração bipolar de Chin Length
- Alterar Cheekbones H
- Alterar o renderer / `DisplacementField` / `WarpRequest` / `WarpResult`
- Segunda pipeline, wrapper, adapter, facade, flag V1↔V2
- Promover Face Slim
- Ligar preview/export antes da Sprint C aprovada
- Corrigir um efeito “ajustando” outro

**Excepção autorizada (2026-09-02).** Leonardo autorizou por escrito, em dois passos:

1. Correcção transversal de **qualidade numérica** nos seis Fields, incluindo Jaw, V Chin e Cheekbones H: a distância passou de chamfer L1 para euclidiana exacta. Geometria, cristas, amplitudes, hard-zeros e valores de slider **não** mudaram.
2. **Reabertura do `jaw`** para trocar `max(gaussianas)` por crista em polilinha. Amplitude `0.04`, Δx e energia nos gônios intactos.

Nenhum efeito mudou de estado. Isto **não** revoga as proibições acima nem abre
os outros efeitos. Ver [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

---

## Fluxo obrigatório (todo efeito)

Nunca saltar. Nunca fundir sprints no mesmo PR.

| Sprint | Objectivo | Código de produto? |
|---|---|---|
| **A** | Field (`dx`/`dy`). Sem RGBA. Sem renderer. | Não |
| **B** | Lab offline: Field + `BackwardBilinearWarp` → `v2Raw` | Não |
| **C** | Aprovação visual humana das fotos lab | Não |
| **D** | Preview no editor (controller / slider da key) | Sim |
| **E** | Export = mesmo grafo do preview | Sim |

Aprovação de C é escrita. Sem ela, D não existe.

---

## Efeitos

### Jaw — encerrado

- Key: `jaw` (Mandíbula).
- Só Δx, para a midline. Energia nos gônios 58–288.
- Amplitude: `t * 0.04 * faceWidth`.
- Módulo: `warp/v2/jaw_field.dart`.
- Papel de produto: estreitar mandíbula nos gônios. Não é o Jawline completo do Meitu (falta pescoço). Suficiente. Não reabrir.
- Crista em polilinha **234→93→132→58→172→136** / **454→323→361→288→397→365**, pesos `0.05 → 0.20 → 0.85 → 1.00 → 0.90 → 0.65`, σ⊥ `0.08 × faceWidth`. `weight` = distância à crista, **não** `max(gaussianas)`: o máximo de gaussianas por landmark cavava ~30% do peso no vão 132→58 e serrilhava o ramo orelha→gónio. Ordem de cima para baixo; não inverter.
- **Cauda leve** em 234/93 (e 454/323): peso baixo de propósito. `taperLandmarks` entram no hull, senão o peso não tem domínio onde actuar. Sem ela o campo caía de 8.5 px para 0 entre o 132 e o 93 e a silhueta ficava pontuda na lateral. Não é Cheekbones.
- **323/454 não são pina**, são a lateral do rosto (espelho de 93/234). Pina travada deslocada `0.05 × faceWidth` para fora, raio `0.022`, com rampa própria `0.035` fora da rampa longa. Disco de `0.06` centrado nesses IDs comia a silhueta e cortava a cauda de um só lado. Mesmo padrão do Cheekbones.
- Reaberto 2026-09-02 **só** para estas correcções de qualidade de campo, com autorização escrita. Amplitude `0.04`, Δx e energia nos gônios intactos. Pendente assinatura visual no editor. Não reabrir para mais nada. Ver [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

### Jaw Angle — em inspecção

- Key: `jaw_angle` («Ângulo da mandíbula»). **Não** é o `jaw`. Não é Chin Length.
- Só Δy. `dx = 0`. Cunha oval **58→172→136** / **288→397→365**. Ponta 152 com sangria (chão 0.22), não trava dura. Maçã 123/352 hard-zero.
- Crista: pesos 1.00 → 0.72 → 0.48. Pico no gônio; lados do queixo seguem (Meitu).
- Slider bipolar; Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight`.
- Amplitude: `0.052 × faceWidth`. σ⊥ `0.14 × faceWidth`. Hull pad `0.16 × faceWidth`. Rampa `0.15 × faceWidth`. Rampa midline `0.045 × faceWidth`.
- **Direita = sobe** (`t > 0`, `dy < 0` no gônio); esquerda = desce.
- Preview: cache do peso; métricas de lab fora do preview.
- Documento: [`v2-jaw-angle.md`](./v2-jaw-angle.md). Sem C.
- Módulo: `warp/v2/jaw_angle/`. Não importa Jaw/Chin/V Chin/V Shape/Cheekbones.

### Chin — reaberto (Chin Length bipolar)

- Key: `chin` («Tamanho do queixo»). Não é V Chin nem Double Chin.
- Só Δy. `dx = 0`. Crista no oval mento→172/397 (peso a descer até 0.08). Gônios **fora** da crista. 132/361 hard-zero. Hull/crista vigentes em [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md).
- `t ∈ [-1, 1]`. Centro = identidade. Esquerda alonga (`dy > 0` no 152); direita encurta (`dy < 0`).
- Amplitude: `0.07 × faceWidth`. σ⊥ `0.08 × faceWidth`.
- Preview: slider não bloqueia; o peso unitário da crista cacheia-se (t só escala `dy`). Métricas de lab não correm no preview.
- Módulo: `warp/v2/chin/`.
- Não é Sprint A–E nova. Pendente assinatura visual no editor.
- Fora deste passo: Double Chin, pescoço, Δx no gônio, alterar Jaw, Cheekbones, V Chin (encerrado).

### V Chin — encerrado

- Key: `v_chin` («V do queixo»). **Não** é `v_face`. Não é Chin Length nem V shape.
- Aprovado no editor (2026-08-26). Vivo em preview/export. Não reabrir.
- Só Δx para a midline. `dy = 0`. 152 ≈ 0 por simetria (função ímpar), sem ilha/entalhe. Gônios e 132/361 hard-zero.
- Crista: **148 → 176 → 149 → 150 → 136** / **377 → 400 → 378 → 379 → 365**. Pesos 1.00 → 0.14. Para antes de 172/58.
- Slider bipolar; Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight`.
- Amplitude: `0.080 × faceWidth`. σ⊥ `0.11 × faceWidth`. Rampa midline `0.11 × faceWidth` (fixa).
- **Esquerda = V** (Meitu, para a midline); direita = quadrado. `t < 0` puxa para dentro.
- Preview: cache do peso; métricas de lab fora do preview.
- Documento: [`v2-v-chin.md`](./v2-v-chin.md).
- Módulo: `warp/v2/v_chin/`. Não importa Chin/Jaw/Cheekbones.

### V Shape — em inspecção

- Key: `v_shape` («Formato V»). **Não** é `v_face`. Não é V Chin nem Jaw.
- Só Δx. `dy = 0`. Interior 148/176/149 hard-zero. 152 hard-zero. **132/361 já não é hard-zero**: leva cauda de peso 0.28, limitada por teste a menos de 55% do pico (adenda 2026-09-02, bico na silhueta).
- Crista no oval: **93 → 132 → 58 → 172 → 136 → 150** / **323 → 361 → 288 → 397 → 365 → 379** (cauda→gónio→pico→mento). Pesos 0.06 → 0.28 → 0.68 → 1.00 → 0.86 → 0.45. **Não** 172→136→58 (volta atrás e corta a silhueta). Era `58 → 172 → 136` com 0.20 → 1.00 → 0.62, que somado ao planalto do Jaw dava um bico de 1,66× na silhueta.
- Slider bipolar; Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight`.
- Amplitude: `0.055 × faceWidth`. σ⊥ `0.13 × faceWidth`. Hull pad `0.09`. Rampa de bordo `0.16 × faceWidth`. Rampa midline `0.10 × faceWidth` (fixa).
- **Direita = V** (Meitu, bordo para a midline); esquerda = quadrado. `t > 0` puxa para dentro.
- Preview: cache do peso; métricas de lab fora do preview.
- Documento: [`v2-v-shape.md`](./v2-v-shape.md). Sem C.
- Módulo: `warp/v2/v_shape/`. Não importa V Chin/Chin/Jaw/Cheekbones.

### Face Slim — arquivo

- Módulo `warp/v2/face_slim/` + testes A/B podem ficar no disco.
- Não é slider Meitu. Misturava mid-face + silhueta sem gônio.
- Sem Sprint C/D/E. Sem `applyFaceSlimWarp`. Sem key no painel.
- Código **não** se reutiliza como base do Cheekbones.

### Cheekbones — em desenvolvimento

- Key: `cheekbone` (“Maçãs do rosto”). Viva no painel como inspecção H. **Não** é C/D/E aprovada.
- Relatório vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).
- Contrato: **Δx** para a midline. `dy = 0`. Mento hard-zero. Gônio **não** é hard-zero (cauda na crista, peso 0.22). Não substitui Jaw.
- Slider bipolar Meitu: centro = 0, sem %. Flag Geral / Esquerda / Direita = lados da **foto**. `tPhotoLeft` / `tPhotoRight` no mesmo Field (não é receita).
- Crista: polilinha oval **234→93→132→58** / **454→323→361→288**. `weight` = distância à crista, não `max(gaussianas)`.
- 323 e 454 estão no oval: a pina da orelha trava **fora** da silhueta. Disco centrado nesses IDs fazia o “S” (tragus parado).
- Primário de métrica direito: **352** (espelho de 123). **Não** 411 (espelho de 187).
- Calibração: t ∈ [-1, 1] por lado; amplitude `0.022 × faceWidth`; σ⊥ `0.09 × faceWidth`; rampa `0.12 × faceWidth`; rampa orelha `0.035 × faceWidth` na pina. Pesos da crista 0.80→0.22.
- Preview: mesmo padrão do Chin — slider não bloqueia; peso unitário cacheado (t / L / R só escala `dx`). Métricas de lab não correm no preview. Geometria H intacta.
- Sprint A encerrada (A1 carimbo; A2 arco interrompido). Hull/losango e dumps B antigos **não** são o Field no disco.
- **Próximo passo (Cheekbones):** Sprint C quando Leonardo assinar as fotos lab. H **não** se altera. V Chin encerrado. V Shape e Jaw Angle não pisam H.
- Chin Length e V Chin são sliders distintos. Não “ajustar” um para compensar o outro.

---

## Roadmap de produto (aprovado)

**Adenda 2026-09-02 (bico na silhueta: Jaw + V Shape).** Leonardo, no mesmo cenário depois da correcção do vinco: «ainda existe essa curva muito forte, não deve haver esses cortes secos; se vai invadir a outra área, deve mexer na outra área também com menos intensidade, é o que o Meitu faz». Medido o deslocamento total ao longo do oval (p01, ambos no extremo): Jaw sozinho é um planalto (93:2,0 / 132:8,5 / 58:9,6 / 172:8,9 / 136:6,1), mas o V Shape punha-lhe em cima um pico isolado (0 / 0 / 1,9 / 11,6 / 6,9) e o total dava **23,5 px no 172 contra 14 px nos vizinhos, 1,66×** — a concavidade abrupta da foto. Duas causas: o peso da crista caía a 0,20 no gónio, e o **disco binário de 132/361** (raio `0.06 × faceWidth`, somado ao `protected`) apagava o efeito em todo o gónio, porque com a rampa de bordo de 60 px por cima o 58 ficava a 1,9 px enquanto o 172, a 75 px do disco, levava 11,6 px plenos. Corrigido: crista alargada para `93→132→58→172→136→150` com `0.06→0.28→0.68→1.00→0.86→0.45`, `taperLandmarks` no hull, e o disco de 132/361 fora do `protected` — passou a régua das métricas, e quem gradua a cauda é o peso da crista. Total em **1,10×**. **O hard-zero 132/361 do V Shape deixou de existir**, o que revoga «não sobe a 132/361» do documento do efeito; a cauda está limitada por teste a menos de 55% do pico. Consequência assumida: o efeito ganhou alcance e no gónio o campo passou de 1,9 a 8,0 px, com a amplitude de pico intacta (`0.055`). Relatório [`v2-v-shape.md`](./v2-v-shape.md) secção 5.

**Adenda 2026-09-02 (vinco na bochecha).** Leonardo, com Mandíbula e Formato V ambos a 100% à direita: «buga e fica tudo errado, olha a força dos cortes puxando apenas onde ele tem a maior área de atuação», com três setas paralelas sobre uma linha diagonal a meio da bochecha. **Não era dobra:** `minDetJ` estava a 0,53 e a cadeia passava os testes. Faltava medir **vinco** — uma quebra de gradiente passa o crivo do `detJ` e ainda assim imprime uma linha, porque o olho lê a derivada segunda. Causa: a rampa `min(1, dist / falloff)` herda o bico da medial axis do domínio; no `v_shape` de p01 o máximo da distância cai a 45 px da fronteira contra `falloff` de 60, logo a rampa nunca satura e o bico fica a meio da bochecha com peso 0,72, o que com 20,7 px de amplitude dá 0,69 px/px de salto. Existia nos seis efeitos. Corrigido com `warp/v2/boundary_feather.dart` (borrão da rampa, com mistura de volta ao cru junto à fronteira) e migração dos três Fields que faltavam para a crista contínua. Curvatura no núcleo: `jaw` 0,55→0,14, `jaw_angle` 0,88→0,15, `chin` 0,49→0,16, `cheekbone` 0,84→0,16, `v_shape` 0,77→0,20. `minDetJ` subiu em todos. Na cadeia reportada a curvatura interior ficou em 0,00–0,07. **Pendência:** o `v_chin` fica em 0,50 por causa do joelho do `midGate`, que vale `amplitude / midBlend` = 0,73 e é também o que lhe segura o `minDetJ` — suavizá-lo exige baixar a amplitude `0,080`, decisão de calibração ainda não pedida. Relatório [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

**Adenda 2026-09-02 (composição da cadeia).** Leonardo viu pontas na lateral com `jaw` a 100% + `jaw_angle`, e deformação grosseira ao juntar `v_shape`. Causa: a cadeia aplicava cada efeito sobre o RGBA já deformado mas passava a todos o `face` da detecção, logo o efeito a jusante media a geometria da origem e punha a crista 6–10 px fora da silhueta (medido nas oito âncoras 132/58/172/136 e espelhos, em p01/p05/p12). Corrigido com autorização escrita: advecção dos landmarks entre etapas (`warp/v2/landmark_advection.dart`, ponto fixo `q ← p + D(q)`, resíduo 0,03–0,065 px) e cadeia única `applyFaceWarpChain` partilhada por preview e export. Somar os seis campos num só foi rejeitado com medição: no extremo a soma inverte (`minDetJ ≈ −0,7`). Cada efeito activo sozinho continua byte a byte idêntico ao anterior. Relatório [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md).

**Adenda 2026-09-02 (dobra do queixo).** Os testes de composição revelaram que `v_chin` e `chin` **dobravam sozinhos**, sem cadeia, no extremo positivo (`v_chin` −0,40 em p01 e já negativo a t≈0,75; `chin` −0,046 a t=1). Leonardo autorizou reabrir os dois **só** para tirar a dobra, sem tocar na amplitude nem no aspecto. Causa: `_ridgeWeight` resolvia a distância pela polilinha mas tomava o peso **só do segmento vencedor**, e na medial axis da crista dois segmentos empatam com projecções de peso diferente — o peso saltava 0,080, que a amplitude de 30 px convertia em 1,4 px de `dx`; como o V Chin só escreve `dx`, `detJ = 1 + ∂dx/∂x` ficava negativo. Só se manifesta onde o raio de curvatura da crista é da ordem do sopro, que é o caso do queixo. Corrigido em `warp/v2/ridge_weight.dart`: peso é a média dos segmentos ponderada por proximidade (`ridgeBlendFaceWidth` 0,012). Medido contra o cálculo anterior: pico do peso 1,0000 → 0,9994, desvio médio 0,006, degrau máximo 0,046 → 0,015. `minDetJ` isolado passou a positivo em todos os seis efeitos, nas cinco faces, nos dois extremos (pior caso global: `jaw_angle` 0,142). **Pendente:** migrar `jaw`, `jaw_angle`, `v_shape` e `cheekbone`, que mantêm o argmin e o degrau latente — a começar pelo `jaw_angle`, que tem salto 0,858 e é o de menos margem.

**Adenda 2026-09-02 (serrilhado da silhueta).** Leonardo viu serrilhado no `jaw` a 99%, no ramo orelha→gónio. Duas causas, ambas corrigidas com autorização escrita. **Dominante:** o peso da silhueta era `max` de gaussianas em 8 landmarks e cavava ~30% no vão 132→58 (medido em p01/p05/p12) — passou a crista em polilinha 132→58→172→136, pesos 0.85→1.00→0.90→0.65, amplitude `0.04` intacta. **Secundária:** a distância era L1 (chamfer 4 vizinhos), copiada sete vezes, com isolinhas em losango e degraus de ~⅓ px na rampa — passou a `EuclideanDistanceTransform` exacta e partilhada, nos seis Fields e no `dilate`. **Terceira, vista na foto a 100%:** a silhueta ficava pontuda na lateral do rosto porque acima do 132 o pixel saía do hull e o campo caía de 8.5 px para 0 — resolvido com cauda de peso baixo em 234/93 (Leonardo: «100% da mandíbula e 5% dessa área de fora»), hull estendido, e a pina 323/454 tirada da rampa longa, que deixava o lado direito a um terço do esquerdo. Nenhum outro efeito mudou de geometria; 419 testes passam, `minDetJ` 0.36–0.47 em `t=1`, orelhas intactas. Falta assinatura visual. Relatório [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

**Adenda 2026-08-28 (Jaw Angle cunha).** Leonardo: o máximo inchava o gônio e havia **trava no queixo**. Riscas Meitu = cunha até aos lados do queixo, não ilha no 58. Calibração vigente: amplitude `0.052`, crista **58→172→136** (1.00→0.72→0.48), midline `0.045`, sangria no 152 (chão 0.22). Jaw e Chin Length intactos. C não assinada.

**Adenda 2026-08-27 (Jaw Angle calibração).** No máximo à esquerda o ângulo não se via: o 58 estava na rampa (pad 0.08 / falloff 0.14 ⇒ peso ~0.57) e o disco 132/361 travava o ramo. Superado pela cunha 2026-08-28.

**Adenda 2026-08-27 (Jaw Angle).** Leonardo abriu o Ângulo da mandíbula (`jaw_angle`): inclinação Δy dos gônios, sopro no 172/397, L/R da foto. Inspecção. Documento [`v2-jaw-angle.md`](./v2-jaw-angle.md). Jaw (Δx), Chin, V Chin, V Shape e Cheekbones H intactos. C não assinada.

**Adenda 2026-08-26 (V Shape).** Leonardo abriu o Formato V (`v_shape`): silhueta externa do queixo, sopro na curva da mandíbula, L/R da foto. Inspecção. Documento [`v2-v-shape.md`](./v2-v-shape.md). V Chin, Jaw e Cheekbones H intactos. Não é o arco maçã→mandíbula. C não assinada.

**Adenda 2026-08-26 (V Chin encerrado).** Leonardo fechou o V Chin no editor. Aprovado. Vivo (`v_chin`). Não alterar. Documento [`v2-v-chin.md`](./v2-v-chin.md).

**Adenda 2026-08-26 (V Chin aberto).** Leonardo abriu o menu V Chin (`v_chin`, «V do queixo»): forma da ponta, Δx, L/R da foto. Superado pelo fecho no mesmo dia.

**Adenda 2026-08-26 (Chin Length bipolar).** Leonardo reabriu o Chin **só** para slider bipolar (alongar + encurtar, rótulo «Tamanho do queixo»). Calibração vigente: amplitude `0.07 × faceWidth`, crista no oval até 172/397 (cauda 0.08, só Δy; gônios fora da crista). Preview de rosto sem debounce (coalesce). Documento [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md). Cheekbones H intacto.

Ordem seguinte **depois** de Cheekbones (C → D → E):

1. Temple
2. Hairline
3. Width — baixa prioridade (o Jaw já cobre o essencial em Δx)
4. Lift
5. Double Chin — bloqueado (falta pescoço)

V Chin: **feito** (aprovado 2026-08-26).  
V Shape: **em inspecção** (silhueta externa; não o arco maçã).  
Jaw Angle: **em inspecção** (inclinação Δy; não o Jaw).

Fora do roadmap: Face Slim, Narrow Face, Smooth (pele, não Rosto).

Face Rig (`v2-face-rig-migration-plan.md`): **congelado**. Não implementar.

---

## Documentos canónicos vs. ignorar

**Seguir**

- Este ficheiro (`PROJECT_CONTEXT.md`)
- [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md)
- Relatório da sprint **aberta** do efeito actual
- Roadmap / audit / spec só se este ficheiro os apontar como vigentes

**Vigente para todos os Fields (infra)**

- [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md) — distância euclidiana partilhada e crista do `jaw`; proíbe voltar ao chamfer L1 e ao `max(gaussianas)`

**Vigente para Jaw Angle**

- [`v2-jaw-angle.md`](./v2-jaw-angle.md) — **Field e UI no disco**; inspecção no editor (não é C)

**Vigente para V Shape**

- [`v2-v-shape.md`](./v2-v-shape.md) — **Field e UI no disco**; inspecção no editor (não é C)

**Vigente para V Chin**

- [`v2-v-chin.md`](./v2-v-chin.md) — **aprovado e encerrado** (Field e UI no disco)

**Vigente para Chin Length bipolar**

- [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md) — calibração do slider `chin` (não é sprint nova)

**Vigentes para Cheekbones**

- [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md) — **Field e UI no disco**
- [`v2-product-audit.md`](./v2-product-audit.md) — aprovado (adenda: `cheekbone` já não é fantasma)
- [`v2-product-roadmap.md`](./v2-product-roadmap.md) — aprovado
- [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md) — spec de região **A**; emendada por H (gônio/oval)
- [`v2-cheekbones-plan.md`](./v2-cheekbones-plan.md) — plano A–E; A encerrada; H em inspecção
- [`v2-cheekbones-product-analysis.md`](./v2-cheekbones-product-analysis.md) — pesquisa encerrada; L/R e cauda mandibular confirmados no editor
- [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md) — A1 (arquivo)
- [`v2-cheekbones-a2-report.md`](./v2-cheekbones-a2-report.md) — A2 interrompida (arquivo)
- [`v2-cheekbones-a-lessons-learned.md`](./v2-cheekbones-a-lessons-learned.md) — síntese A1 vs A2
- [`v2-cheekbones-field-model-analysis.md`](./v2-cheekbones-field-model-analysis.md) — A1/A2; H ainda é `dx = A · w`
- [`v2-cheekbones-model-validation.md`](./v2-cheekbones-model-validation.md) — A1 vs A2 no código antigo

**Não usar como mapa do sistema actual**

- `30-estado-atual-arquitetura.md`, `31-sistema-facial-atual.md`, `32-extended-roi.md`
- Relatórios ROI / Mesh / MLS / pipeline abandonada
- Plano Face Rig (congelado)
- Plano Face Slim (arquivo; não continuar C/D/E)

---

## Como actualizar este ficheiro

No mesmo turno em que ocorrer qualquer um destes factos:

- sprint A/B/C/D/E começa, termina ou é rejeitada
- um efeito é aprovado, arquivado ou encerrado
- o roadmap muda
- uma proibição ou decisão arquitectural nasce ou morre
- a calibração vigente do efeito aberto muda de forma material

Actualizar: **Estado actual**, a ficha do efeito, **Próximo passo**, data no topo.  
Não apagar decisões; marcar o estado novo.  
Não despejar hipóteses de chat. Só o que ficou oficial.
