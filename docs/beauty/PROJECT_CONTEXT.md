# PROJECT_CONTEXT — Facial Warp V2

**Fonte oficial do estado do projeto.**  
Última actualização: 2026-09-30 (Lip Angle)

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
| **Hairline** | Aprovado. Vivo (`hairline`, «Linha do cabelo»). C assinada 2026-09-03. A–E fechadas. B Δy-only rejeitada. Spec [`v2-hairline.md`](./v2-hairline.md). **Não** é `forehead`. **Não** é Temple. |
| **Head** | D no editor. Key `head` («Cabeça»). Tab Proporção. Sem E escrita. Spec [`v2-head.md`](./v2-head.md). D [`v2-head-d-report.md`](./v2-head-d-report.md). **Não** é `head_size`. **Não** é zoom de câmara. |
| **Eyebrow Height** | D no editor. Key `eyebrow_height` («Altura»). Tab Sobrancelha. **Não** é makeup `eyebrows`. Sem E escrita. Spec [`v2-eyebrow-height.md`](./v2-eyebrow-height.md). D [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md). **Intacto** no Width. |
| **Eyebrow Width** | D no editor. Key `eyebrow_width` («Largura»). Tab Sobrancelha. **Não** é makeup `eyebrows`. **Não** é Altura. Sem E escrita. Spec [`v2-eyebrow-width.md`](./v2-eyebrow-width.md). D [`v2-eyebrow-width-d-report.md`](./v2-eyebrow-width-d-report.md). **Intacto** no End. |
| **Eyebrow End** | D no editor. Key `eyebrow_end` («Ponta»; Meitu End = ponta interna / glabela). Tab Sobrancelha. **Não** é makeup `eyebrows`. **Não** é Altura nem Largura. Sem E escrita. Spec [`v2-eyebrow-end.md`](./v2-eyebrow-end.md). D [`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md). |
| **Eye Size** | No editor para aprovação visual. Key `eye_size` («Tamanho»). Tab Olhos. **Não** é `eye_scale`. **Não** é Height / Width / Length / Distance / Puffy. **Não** é makeup. Sem B/C/E. Spec [`v2-eye-size.md`](./v2-eye-size.md). **Intacto** na Altura do olho. |
| **Eye Height** | No editor para aprovação visual. Key `eye_height` («Altura»). Tab Olhos. **Não** é `eyebrow_height`. **Não** é Tamanho. Sem B/C/E. Spec [`v2-eye-height.md`](./v2-eye-height.md). **Intacto** na Largura do olho. |
| **Eye Width** | No editor para aprovação visual. Key `eye_width` («Largura»). Tab Olhos. **Não** é `eyebrow_width`. **Não** é Tamanho nem Altura. Sem B/C/E. Spec [`v2-eye-width.md`](./v2-eye-width.md). **Intacto** no Comprimento do olho. |
| **Eye Length** | No editor para aprovação visual. Key `eye_length` («Comprimento»). Tab Olhos. **Não** é `eye_width`. **Não** é Tamanho nem Altura. Sem B/C/E. Spec [`v2-eye-length.md`](./v2-eye-length.md). **Intacto** na Distância dos olhos. |
| **Eye Distance** | No editor para aprovação visual. Key `eye_distance` («Distância»). Tab Olhos. **Não** é Comprimento. **Não** é Tamanho. Sem B/C/E. Spec [`v2-eye-distance.md`](./v2-eye-distance.md). |
| **Eye Puffy** | No editor para aprovação visual. Key `eye_puffy` («Olheiras»). Tab Olhos. Um slider, os dois olhos. Clareia só a pele debaixo da pestana (sulco), em direção à pele vizinha; o poro fica. Interior do olho fica. **Não** é warp. Mesmo clareamento A3 de `remove_dark_circles`. Spec [`v2-eye-puffy.md`](./v2-eye-puffy.md). |
| **Nose Size** | No editor para aprovação visual. Key `nose_size` («Tamanho»). Tab Nariz. **Não** é `nose_slim` / `nose_length` / `nose_height` / `nose_tip` / `nose_bridge`. **Não** é Head. Sem B/C/E. Spec [`v2-nose-size.md`](./v2-nose-size.md). **Intacto** na Elevação. |
| **Nose Lift** | No editor para aprovação visual. Key `nose_lift` («Elevação»). Tab Nariz. **Não** é Tamanho. **Não** é Tip / Ala / Root / Bridge. Sem B/C/E. Spec [`v2-nose-lift.md`](./v2-nose-lift.md). **Intacto** na Largura. |
| **Nose Ala** | No editor para aprovação visual. Key `nose_ala` («Largura»). Tab Nariz. Geral / L / R da foto. **Não** é `nose_slim`. **Não** é Tamanho nem Elevação. Sem B/C/E. Spec [`v2-nose-ala.md`](./v2-nose-ala.md). **Intacto** na Ponte. |
| **Nose Bridge** | No editor para aprovação visual. Key `nose_bridge` («Ponte»). Tab Nariz. Um slider, sem L/R. **Não** é Ala nem Root nem Tip. Sem B/C/E. Spec [`v2-nose-bridge.md`](./v2-nose-bridge.md). **Intacto** no Tamanho dos lábios. |
| **Lip Size** | No editor para aprovação visual. Key `lip_size` («Tamanho»). Tab Lábios. Um slider, sem L/R. **Não** é `lip_thickness`. **Não** é Width / Height / Angle / Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-size.md`](./v2-lip-size.md). **Intacto** na Largura e na Altura. |
| **Lip Width** | No editor para aprovação visual. Key `lip_width` («Largura»). Tab Lábios. Um slider, sem L/R. **Não** é Tamanho. **Não** é Height / Angle / Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-width.md`](./v2-lip-width.md). **Intacto** na Altura. |
| **Lip Height** | No editor para aprovação visual. Key `lip_height` («Altura»). Tab Lábios. Um slider, sem L/R. **Não** é Tamanho nem Largura. **Não** é Angle / Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-height.md`](./v2-lip-height.md). **Intacto** no Ângulo. |
| **Lip Angle** | No editor para aprovação visual. Key `lip_angle` («Ângulo»). Tab Lábios. Um slider, sem L/R. **Não** é Tamanho, Largura nem Altura. **Não** é Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-angle.md`](./v2-lip-angle.md). |

Pipeline viva no produto:

```
RGBA → applyFaceWarpChain → Body → Skin → Color
```

`applyFaceWarpChain` percorre, nesta ordem, `head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → eye_height → eye_width → eye_length → eye_distance → nose_size → nose_lift → nose_ala → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone`. Olheiras (`eye_puffy`) não entra nesta cadeia: clareia a pele no passe de pele. Etapa com slider em identidade é saltada. Preview (`_renderTexture`) e export (`TiledExportEngine`) usam o **mesmo** método, para não existirem duas ordens possíveis. As `applyXWarp` continuam públicas e inalteradas, para uso isolado e testes.

Entre etapas os landmarks são **advectados** para a geometria já deformada (`warp/v2/landmark_advection.dart`). Sem isso o efeito a jusante recebia o RGBA deformado mas media a geometria da origem, e a crista caía 6–10 px fora da silhueta. Ver [`v2-composicao-cadeia.md`](./v2-composicao-cadeia.md).

Cheekbones está na cadeia de preview/export como inspecção da hipótese H. **Não** é Sprint C/D aprovada. V Chin, Hairline, Eyebrow Height, Eyebrow Width e Eyebrow End estão na mesma cadeia, **aprovados**. V Shape, Jaw Angle, Eye Size, Eye Height, Eye Width, Eye Length, Eye Distance, Nose Size, Nose Lift, Nose Ala, Nose Bridge, Lip Size, Lip Width, Lip Height e Lip Angle estão na cadeia como inspecção. Eye Puffy está no tab Olhos como clareamento de pele, não como warp. Esses menus de Olhos, os de Nariz e os de Lábios esperam a assinatura visual.

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
- O perfil da rampa é **smoothstep**, nunca linear: a rampa linear arranca com derivada `1 / falloff`, logo o primeiro pixel dentro do domínio vale já um passo inteiro (0,20 px no `jaw`, 0,23 px no `v_shape`). Como as máscaras são binárias e rasterizadas a pixel cheio, esse passo corre em dentes de um pixel ao longo da fronteira e serrilha a silhueta contra o cabelo. Pelo mesmo motivo a distância é alisada com σ fixo de 1,2 px antes da rampa, descontando `σ/√(2π)` para devolver o zero à fronteira, e quem está fora do domínio fica fora — sem essa guarda o borrão espalha distância para o exterior e a rampa deixa de valer zero lá.
- `minDetJ > 0` e núcleo liso não bastam: medir também o **degrau de entrada**, o maior deslocamento num pixel com vizinho parado. É a métrica do serrilhado, e vive no teste `nenhum efeito vinca o núcleo nem entra com degrau`.
- O slider **não** reconstrói o campo. Máscaras, distâncias, rampas e peso de crista dependem só dos landmarks e do tamanho; o slider entra no fim, em `dx = amplitude(t) · pesoUnitário`. Cada efeito guarda o peso unitário num `*FieldRuntime` com chave `identical(face) && width && height` e, no acerto, só reescala os pixels activos: 196 ms → 0,1 ms no `jaw`, que era o último sem esta separação. A cadeia pede `computeMetrics: false`, porque medir dez regiões na imagem inteira custava mais do que produzir o campo. Ver [`v2-latencia-preview.md`](./v2-latencia-preview.md).
- Nada corre na imagem inteira quando o efeito ocupa uma fracção dela, e **nenhum destes atalhos muda o resultado** — cada um tem um teste que o compara com a definição que substitui. O remap só visita o suporte do campo dilatado de um pixel (fora dele a jacobiana é a identidade e a bilinear lê um só tap, logo o destino é a origem já copiada; a dilatação existe porque a decisão de filtrar por área lê os vizinhos). A rampa de fronteira corre numa janela recortada (fora da caixa da região de interesse tudo é semente, logo a semente mais próxima de qualquer pixel de interesse está nessa caixa dilatada de um; a janela leva ainda o suporte dos borrões, para a replicação de borda replicar zeros). `fillPolygon` calcula as travessias uma vez por linha em vez de percorrer o anel em cada pixel. `dilate` mede a distância só na caixa do que está marcado. `RidgeWeight` prepara os segmentos em `Float64List` uma vez por efeito, com a mesma ordem de operações, e `stronger` descarta o lado que não pode ganhar por `maxWeight · exp(−dCaixa²/2σ²)`. O envelope malar do `cheekbone` tem `supportBox`. Ver [`v2-latencia-preview.md`](./v2-latencia-preview.md).
- Um campo liso não garante imagem lisa: onde o remap **comprime**, a bilinear 2×2 não chega e alia. O `BackwardBilinearWarp` filtra por área nesses pixels, com uma grelha de sub-amostras, e mantém a bilinear pura onde não há compressão. Nunca voltar a bilinear pura em todo o domínio: com um efeito no extremo mais de 40% dos pixels deslocados comprimem, até 1,43×, e o erro face ao filtro de área exacto era de 33 níveis de 255. Métrica no teste `facial_warp_v2_antialias_test.dart`.

---

## Nunca

É proibido:

- MLS no renderer
- Face Rig (plano congelado; inválido como implementação)
- Receitas (blend ponderado de regiões / sliders compostos)
- Slider composto
- Alterar Jaw
- Alterar V Chin
- Alterar Hairline
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

### Hairline — encerrado

- Key: `hairline` («Linha do cabelo»). **Não** é `forehead`. **Não** é Temple nem Lift.
- Aprovado no editor (2026-09-03). Vivo em preview/export. Não reabrir salvo calibração pedida por escrito.
- Campo a partir da **linha** L (`21→103→67→109→10→338→297→332→251`): `D = −sign(t) · |t| · 0.10 · w · (p − q)`, `q` = projecção em L. Em L, `D = 0`. Só o lado do cabelo (para lá de L, visto do 9). O 9 **não** é origem.
- Peso ao longo de L: `0.15→0.55→0.75→0.92→1.00` e espelho. Sem decaimento transversal (isso matava o cap). Sem crista no cume. 21/251 são cauda, **não** Temple.
- Slider bipolar, sem L/R. **Esquerda = infla** (`t < 0`, cresce a partir da linha); direita = desincha (volta até à linha).
- Escala `0.10`. Rampa `0.16`. Hull pad `0.10`. Banda = arco L + arco levantado (`crownExtend` `0.70`).
- Runtime cacheia `unitDx`/`unitDy` (`w · (p − q)`); o slider só reescala.
- Módulo: `warp/v2/hairline/`. Não importa Jaw/Chin/V Chin/V Shape/Cheekbones/Jaw Angle.
- Cadeia: a seguir ao Head (`head → hairline → jaw → …`). Painel Rosto: **último** ícone. Preview e export partilham `applyFaceWarpChain`.
- A primeira (Δy-only) **rejeitada**. C assinada. Reaberto 2026-09-03 **só** para esta equação (Leonardo: a linha tracejada não mexe; o cabelo cresce ou encolhe a partir dela, no arco todo, em todas as fotos). Spec: [`v2-hairline.md`](./v2-hairline.md).

### Head — D no editor

- Key: `head` («Cabeça»). **Não** é `head_size`. **Não** é Hairline nem zoom de câmara.
- D no editor (2026-09-04). C assinada. Sem E escrita. Os sete Fields vivos intactos.
- Campo: `D = w · (q − c) · (1 − 1/s) · min(1, R₊ / |q − c|)`, `s = 1 − 0.12 t`. `c` = bbox do oval. `w` = hull (oval + cap + orelhas + asas laterais `0.34 × faceWidth` ∪ enlarge extremo) × rampa. As asas entram também no `R₊`. Sem `PersonMask`. `k` 0,22 invertia na rampa (`|∇w| · |q−c| · α > 1`); vigente 0,12 / falloff 0,24 / pad 0,28. Sem crista. Sem hard-zero em olhos/boca. Sem buraco em `c`.
- `w` dilatado ao pior enlarge e **independente de t**. Sem dilatar no slider.
- Esquerda cresce; direita encolhe. Fundo longe ≈ 0. Anel do shrink não é identidade.
- Runtime: `unit = w · (q − c)`; o slider só multiplica por `α(t)`.
- Lab B: 15 `v2Raw`. Encolher em p01/p05 marca `invalidSource` no cap (crop); **não** se preenche. p12 tem margem e fica a 0. Relatório [`v2-head-b-report.md`](./v2-head-b-report.md). C [`v2-head-c-report.md`](./v2-head-c-report.md).
- Módulo: `warp/v2/head/`. Não importa Jaw/Chin/V Chin/V Shape/Cheekbones/Jaw Angle/Hairline.
- Cadeia: **primeiro** (`head → hairline → …`). Tab **Proporção**, ícone Cabeça. Slider bipolar sem L/R. Preview e export partilham `applyFaceWarpChain`. Pele/Body continuam no `face` da detecção.
- Spec: [`v2-head.md`](./v2-head.md). Plano: [`v2-head-plan.md`](./v2-head-plan.md). D: [`v2-head-d-report.md`](./v2-head-d-report.md).

### Eyebrow Height — Sprint D

- Key: `eyebrow_height` («Altura»). **Não** é `eyebrows` (makeup / tab Pele). **Não** é Hairline nem Head.
- Sprint D (2026-09-04). C assinada. Tab **Sobrancelha** à direita de Rosto. Slider bipolar com L/R da foto. Sem E escrita. Os Fields vivos intactos.
- Campo: só Δy. `dx = 0`. `dy = −t_lado · 0.035 · faceWidth · w`. Planalto no hull dos 10 IDs por lado × rampa × `lidGate`. `leftFrac` contínuo (porta binária invertia na glabela). Sem `RidgeWeight` (pico no arco seria Shape). Sem `PersonMask`.
- Convenção: **esquerda baixa** (`t < 0`, `dy > 0`); **direita sobe** (`t > 0`, `dy < 0`). Geral / L / R = lados da **foto**. `tPhotoLeft` / `tPhotoRight`. Foto esquerda = MP direita (105); foto direita = MP esquerda (334).
- Olhos não são buraco no domínio (comeria o planalto). `lidGate` zera a pálpebra (159/386) e a dobra externa: prateleira `0.026 × faceWidth` em 33/246/161 e 263/466/388, mais amostras a 30/45/58% do vão cauda→canto (70–33 / 300–263). A dobra `|D| ≤ 20%` do pico. Landmark 10 parado. Discos métricos em 21/251 sobrepõem o pad (têmpora); não se furam no campo.
- Runtime: `unitWeight` + `leftFrac`; o slider só escala `dy`.
- Lab B: 21 `v2Raw` refeitos após a dobra. `invalidCount = 0`. Pior `minDetJ` 0,333 (p05 t=−1). Relatório [`v2-eyebrow-height-b-report.md`](./v2-eyebrow-height-b-report.md).
- Módulo: `warp/v2/eyebrow_height/`. Não importa Jaw/Chin/V Chin/V Shape/Cheekbones/Jaw Angle/Hairline/Head.
- Cadeia: depois do Hairline (`head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → jaw → …`). Tab **Sobrancelha**, ícone Altura. Preview e export partilham `applyFaceWarpChain`.
- Spec: [`v2-eyebrow-height.md`](./v2-eyebrow-height.md). Plano: [`v2-eyebrow-height-plan.md`](./v2-eyebrow-height-plan.md). C: [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md). D: [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md).

### Eyebrow Width — Sprint D

- Key: `eyebrow_width` («Largura»). **Não** é `eyebrows`. **Não** é `eyebrow_height`.
- Sprint D (2026-09-04). C assinada. Tab **Sobrancelha**, ícone Largura à direita de Altura. Slider bipolar com L/R da foto. Sem E escrita. Os Fields vivos, incluindo Altura, intactos.
- Campo: só Δy. `dx = 0`. `dy = t_lado · 0.008 · faceWidth · w · s`. `s = tanh((y − y_eixo) / halfBand)`. `y_eixo` interpolado em X e misturado L/R com `leftFrac` (sem argmin de segmento). Engrossa a abrir: arco sobe, base desce. Amplitude leve (Leonardo: sem cara de edição). Mesmo `lidGate` da Altura (cópia, sem importar o Field). Sem `RidgeWeight`. Sem `PersonMask`.
- Convenção: **esquerda afina** (`t < 0`); **direita engrossa** (`t > 0`). L/R da foto. Foto esquerda = MP direita (105/52); foto direita = MP esquerda (334/282).
- Runtime: `unitWeight` = `w · s`; o slider só escala `dy`.
- Lab B: 21 `v2Raw`. `invalidCount = 0`. Pior `minDetJ` 0,594 (p12 t=−1). Pico ~2,1–2,8 px. Relatório [`v2-eyebrow-width-b-report.md`](./v2-eyebrow-width-b-report.md).
- Módulo: `warp/v2/eyebrow_width/`. Não importa Altura nem os outros Fields.
- Cadeia: depois da Altura (`head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → jaw → …`). Tab **Sobrancelha**, ícone Largura. Preview e export partilham `applyFaceWarpChain`.
- Spec: [`v2-eyebrow-width.md`](./v2-eyebrow-width.md). Plano: [`v2-eyebrow-width-plan.md`](./v2-eyebrow-width-plan.md). C: [`v2-eyebrow-width-c-report.md`](./v2-eyebrow-width-c-report.md). D: [`v2-eyebrow-width-d-report.md`](./v2-eyebrow-width-d-report.md).

### Eye Size — inspecção no editor

- Key: `eye_size` («Tamanho»). **Não** é `eye_scale`. **Não** é Height / Width / Length / Distance / Puffy eyes. **Não** é makeup `eyelashes` nem `iris_enhance`.
- No editor (2026-09-29) para o Leonardo aprovar o menu antes do próximo ícone de Olhos. Sem B escrita. Sem C assinada. Sem E. Sobrancelhas e os Fields vivos intactos.
- Campo: escala local em volta da íris. `s = 1 + 0.28 t`. `D = α · w · (p − c)`, `α = 1 − 1/s`. `t < 0` encolhe; `t > 0` aumenta. Foto esquerda = íris **468** / canto **33**. Foto direita = íris **473** / canto **263**. A íris fica. Sobrancelha, nariz, boca e landmark 10 ficam (porta por distância, sem disco binário). Sem `RidgeWeight`. Sem `PersonMask`. Sem importar outros Fields.
- Convenção: **esquerda encolhe**; **direita aumenta**. L/R da foto. Geral move os dois.
- Runtime: o unitário é `w · (p − c)` por olho; o slider só entra em `α(t)`.
- Cadeia: depois da Ponta (`head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → eye_size → jaw → …`). Tab **Olhos**, ícone Tamanho. Preview e export partilham `applyFaceWarpChain`.
- Spec: [`v2-eye-size.md`](./v2-eye-size.md).

### Eye Height — inspecção no editor

- Key: `eye_height` («Altura»). **Não** é `eyebrow_height`. **Não** é `eye_size`. **Não** é Width / Length / Distance / Puffy eyes.
- No editor (2026-09-29) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos intactos.
- Campo: só Δy. `dx = 0`. `dy = −t_lado · 0.030 · faceWidth · w`. `t > 0` sobe; `t < 0` desce. Foto esquerda = íris **468**. Foto direita = íris **473**. A íris anda com o olho. Sobrancelha, nariz, boca e landmark 10 ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho nem os outros Fields.
- Convenção: **esquerda desce**; **direita sobe**. L/R da foto. Geral move os dois.
- Runtime: o unitário é o peso de cada olho; o slider só escala `dy`.
- Cadeia: depois do Tamanho (`… → eye_size → eye_height → jaw → …`). Tab **Olhos**, ícone Altura à direita de Tamanho.
- Spec: [`v2-eye-height.md`](./v2-eye-height.md).

### Eye Width — inspecção no editor

- Key: `eye_width` («Largura»). **Não** é `eyebrow_width`. **Não** é `eye_size` nem `eye_height`. **Não** é Length / Distance / Puffy eyes.
- No editor (2026-09-29) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura e os Fields vivos intactos.
- Campo: só Δx. `dy = 0`. Escala horizontal em volta da íris. `s = 1 + 0.28 t`. `dx = α · w · (x − c_x)`, `α = 1 − 1/s`. `t > 0` alarga; `t < 0` estreita. Foto esquerda = íris **468** / canto **33**. Foto direita = íris **473** / canto **263**. A íris fica. A altura do olho não muda. Sobrancelha, nariz, boca e landmark 10 ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Altura nem os outros Fields.
- Convenção: **esquerda estreita**; **direita alarga**. L/R da foto. Geral move os dois.
- Runtime: o unitário é `w · (x − c_x)` por olho; o slider só entra em `α(t)`.
- Cadeia: depois da Altura (`… → eye_size → eye_height → eye_width → jaw → …`). Tab **Olhos**, ícone Largura à direita de Altura.
- Spec: [`v2-eye-width.md`](./v2-eye-width.md).

### Eye Length — inspecção no editor

- Key: `eye_length` («Comprimento»). **Não** é `eye_width`. **Não** é `eye_size` nem `eye_height`. **Não** é Distance / Puffy eyes.
- No editor (2026-09-29) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura, Largura e os Fields vivos intactos.
- Campo: só Δx. `dy = 0`. O canto externo anda; a íris e o canto interno ficam. `dx = t_lado · 0.028 · faceWidth · w · perfil · side`. `perfil` é 0 da íris para dentro e sobe em smoothstep até 1 no canto externo (33 / 263). `t > 0` alonga; `t < 0` encurta. Foto esquerda = íris **468** / externo **33** / interno **133**. Foto direita = íris **473** / externo **263** / interno **362**. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Altura, Largura nem os outros Fields.
- Convenção: **esquerda encurta**; **direita alonga**. L/R da foto. Geral move os dois.
- Runtime: o unitário é `w · perfil · side` por olho; o slider só escala `dx`.
- Cadeia: depois da Largura (`… → eye_width → eye_length → jaw → …`). Tab **Olhos**, ícone Comprimento à direita de Largura.
- Spec: [`v2-eye-length.md`](./v2-eye-length.md).

### Eye Distance — inspecção no editor

- Key: `eye_distance` («Distância»). **Não** é `eye_length`. **Não** é `eye_size` nem `eye_width`. **Não** é Puffy eyes.
- No editor (2026-09-29) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Altura, Largura, Comprimento e os Fields vivos intactos.
- Campo: só Δx. `dy = 0`. O olho inteiro translada, íris incluída. `dx = t_lado · 0.030 · faceWidth · w · side`. `side` aponta para fora da linha do meio das íris (468 e 473). `t > 0` afasta; `t < 0` aproxima. Hull pad `0.09 × faceWidth`, para o canto externo estar no planalto e andar com a íris. Porta do nariz `0.10 × faceWidth`. A da sobrancelha é o vão até à pálpebra (159 / 386), borrado: a pálpebra anda com a íris e a sobrancelha fica. Ajuste 2026-09-29, a porta fixa de `0.10` deixava a pálpebra presa. Sobrancelha, nariz, boca e landmark 10 ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar os outros Fields.
- Convenção: **esquerda aproxima**; **direita afasta**. L/R da foto. Geral move os dois.
- Runtime: o unitário é `w · side` por olho; o slider só escala `dx`.
- Cadeia: depois do Comprimento (`… → eye_length → eye_distance → nose_size → jaw → …`). Tab **Olhos**, ícone Distância à direita de Comprimento.
- Spec: [`v2-eye-distance.md`](./v2-eye-distance.md).

### Eye Puffy — inspecção no editor

- Key: `eye_puffy` («Olheiras»). Tab Olhos. **Não** é warp. **Não** fecha o olho. **Não** é Distância nem Tamanho.
- No editor (2026-09-29) para o Leonardo aprovar o menu. Sem B/C/E. Os Fields vivos intactos.
- Efeito: clarear a sombra da pálpebra inferior e do sulco, nos dois olhos, no passe A3, em direção ao tom da pele vizinha (anel fora da máscara). Separação de frequências: a baixa sobe 90% do vão; o poro fica. Pele já nesse tom não se pinta. Íris e esclera ficam. É o invariante A3 de [`13-visual-quality-targets.md`](./13-visual-quality-targets.md), o mesmo passe de `remove_dark_circles`. O slider de Olhos e o de Pele usam o maior dos dois. Um slider só.
- Fora da cadeia de warp (`… → eye_distance → nose_size → jaw → …`). Tab **Olhos**, ícone Olheiras à direita de Distância.
- Spec: [`v2-eye-puffy.md`](./v2-eye-puffy.md).

### Nose Size — inspecção no editor

- Key: `nose_size` («Tamanho»). **Não** é `nose_slim`, `nose_length`, `nose_height`, `nose_tip` nem `nose_bridge`. **Não** é Head. **Não** é Lift / Ala / Root / Bridge / Tip.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Os Fields vivos e os de Olhos intactos. **Intacto** na Elevação, na Largura e na Ponte. Root e Tip ainda não existem.
- Campo: escala isotrópica em volta do centróide do hull `V2RegionCatalog.nose`. `s = 1 − 0.14 t`, `α = 1 − 1/s`, `D = α · w · (p − c)`. `t > 0` encolhe; `t < 0` aumenta. Ponta (1) e asas (98/327) andam juntas. Olhos, sobrancelha, boca e linha do cabelo ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Head nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda aumenta**; **direita encolhe**. Igual à Cabeça. Contrária ao Tamanho dos olhos.
- Runtime: o unitário é `w · (p − c)`; o slider só entra em `α(t)`.
- Cadeia: depois da Distância (`… → eye_distance → nose_size → nose_lift → nose_ala → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Nariz**, ícone Tamanho.
- Spec: [`v2-nose-size.md`](./v2-nose-size.md).

### Nose Lift — inspecção no editor

- Key: `nose_lift` («Elevação»). **Não** é `nose_size`. **Não** é Tip / Ala / Root / Bridge. **Não** é `nose_length`.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos intactos. **Intacto** na Largura e na Ponte. Root e Tip ainda não existem.
- Campo: só Δy. `dx = 0`. `dy = −t · 0.045 · faceWidth · w · perfil`. `perfil` é 0 na raiz (168) até `u = 0.08` do eixo 168→1, e 1 a partir de `u = 0.48` (ponta 1, asas 98/327, columela). `t > 0` sobe; `t < 0` desce. Hull pad `0.090` e rampa `0.105` para o extremo que desce não dobrar no lábio. Olhos, sobrancelha, boca e linha do cabelo ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda desce**; **direita sobe**.
- Runtime: o unitário é `w · perfil`; o slider só escala `dy`.
- Cadeia: depois do Tamanho (`… → nose_size → nose_lift → nose_ala → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Nariz**, ícone Elevação à direita de Tamanho.
- Spec: [`v2-nose-lift.md`](./v2-nose-lift.md).

### Nose Ala — inspecção no editor

- Key: `nose_ala` («Largura»). **Não** é `nose_slim`. **Não** é `nose_size` nem `nose_lift`. **Não** é Root / Bridge / Tip.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Elevação e os Fields vivos intactos. **Intacto** na Ponte. Root e Tip ainda não existem.
- Campo: só Δx. `dy = 0`. `s = 1 − 0.24 t`, `α = 1 − 1/s`, `dx = α · w · perfil · midGate · (x − x_mid)`. `x_mid` é a média do x de 168 e 1. `midGate` segura a ponta. `perfil` é 0 na raiz até `u = 0.12` e 1 a partir de `u = 0.42`. `t > 0` afina; `t < 0` alarga. Foto esquerda = asa **98**; foto direita = **327**. Olhos, ponta em x, raiz, boca e sobrancelha ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Elevação nem os outros Fields. Geral / L / R da foto.
- Convenção: **esquerda alarga**; **direita afina**. L/R da foto.
- Runtime: o unitário é `w · perfil · midGate · (x − x_mid)` por lado; o slider só entra em `α(t_lado)`.
- Cadeia: depois da Elevação (`… → nose_lift → nose_ala → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Nariz**, ícone Largura à direita de Elevação.
- Spec: [`v2-nose-ala.md`](./v2-nose-ala.md).

### Nose Bridge — inspecção no editor

- Key: `nose_bridge` («Ponte»). **Não** é `nose_slim`. **Não** é `nose_size`, `nose_lift` nem `nose_ala`. **Não** é Root nem Tip.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Elevação, Largura e os Fields vivos intactos. Root e Tip ainda não existem.
- Campo: só Δx. `dy = 0`. `s = 1 − 0.28 t`, `α = 1 − 1/s`, `dx = α · w · perfil · midGate · (x − x_mid)`. `perfil` é uma banda no terço do meio (`0.18–0.70`, cheia em `0.32–0.50`). `t > 0` afina o dorso; `t < 0` alarga. Raiz (168), asas (98/327) e ponta (1) ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Elevação, Largura nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda alarga**; **direita afina**.
- Runtime: o unitário é `w · perfil · midGate · (x − x_mid)`; o slider só entra em `α(t)`.
- Cadeia: depois da Largura (`… → nose_ala → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Nariz**, ícone Ponte à direita de Largura.
- Spec: [`v2-nose-bridge.md`](./v2-nose-bridge.md).

### Lip Size — inspecção no editor

- Key: `lip_size` («Tamanho»). **Não** é `lip_thickness`. **Não** é Width / Height / Angle / Rotate / M-shaped.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Nariz e os Fields vivos intactos. **Intacto** na Largura e na Altura. Angle / Rotate / M-shaped ainda não existem.
- Campo: escala isotrópica em volta do centróide do hull `V2RegionCatalog.lips`. `s = 1 − 0.12 t`, `α = 1 − 1/s`, `D = α · w · (p − c)`. `t > 0` encolhe; `t < 0` aumenta. Detalhe suave. Nariz, queixo, olhos e sobrancelha ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Nariz nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda aumenta**; **direita encolhe**. Igual à Cabeça e ao Tamanho do nariz.
- Runtime: o unitário é `w · (p − c)`; o slider só entra em `α(t)`.
- Cadeia: depois da Ponte (`… → nose_bridge → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Lábios**, ícone Tamanho.
- Spec: [`v2-lip-size.md`](./v2-lip-size.md).

### Lip Width — inspecção no editor

- Key: `lip_width` («Largura»). **Não** é `lip_size`. **Não** é Height / Angle / Rotate / M-shaped. **Não** é `lip_thickness`.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho e os Fields vivos intactos. **Intacto** na Altura. Angle / Rotate / M-shaped ainda não existem.
- Campo: escala só em x em volta do centróide do hull `V2RegionCatalog.lips`. `s = 1 − 0.12 t`, `α = 1 − 1/s`, `dx = α · w · (x − c.x)`, `dy = 0`. `t > 0` afina; `t < 0` alarga. Praticamente o Tamanho, só em x. Nariz, queixo, olhos e sobrancelha ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda alarga**; **direita afina**.
- Runtime: o unitário é `w · (x − c.x)`; o slider só entra em `α(t)`.
- Cadeia: depois do Tamanho (`… → lip_size → lip_width → lip_height → lip_angle → jaw → …`). Tab **Lábios**, ícone Largura à direita de Tamanho.
- Spec: [`v2-lip-width.md`](./v2-lip-width.md).

### Lip Height — inspecção no editor

- Key: `lip_height` («Altura»). **Não** é `lip_size` nem `lip_width`. **Não** é Angle / Rotate / M-shaped. **Não** é `lip_thickness`.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura e os Fields vivos intactos. **Intacto** no Ângulo. Rotate / M-shaped ainda não existem.
- Campo: só Δy. `dx = 0`. `dy = −t · 0.024 · faceWidth · w`. A boca sobe ou desce como um bloco. `t > 0` sobe; `t < 0` desce. Hull pad `0.040` e rampa `0.055` para a pele à volta viajar com a boca. Nariz, queixo, olhos e sobrancelha ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda desce**; **direita sobe**.
- Runtime: o unitário é `w`; o slider só escala `dy`.
- Cadeia: depois da Largura (`… → lip_width → lip_height → lip_angle → jaw → …`). Tab **Lábios**, ícone Altura à direita de Largura.
- Spec: [`v2-lip-height.md`](./v2-lip-height.md).

### Lip Angle — inspecção no editor

- Key: `lip_angle` («Ângulo»). **Não** é `lip_size`, `lip_width` nem `lip_height`. **Não** é Rotate / M-shaped. **Não** é `lip_thickness`.
- No editor (2026-09-30) para o Leonardo aprovar o menu. Sem B escrita. Sem C assinada. Sem E. Tamanho, Largura, Altura e os Fields vivos intactos. Rotate / M-shaped ainda não existem.
- Campo: rotação em volta do centróide. `θ = 0.12 t`, `dx = θ · w · (y − c.y)`, `dy = −θ · w · (x − c.x)`. Os cantos andam na diagonal. `t > 0` canto esquerdo da foto desce / direito sobe; `t < 0` o contrário. Hull pad `0.040` e rampa `0.055`. Nariz, queixo, olhos e sobrancelha ficam. Sem `RidgeWeight`. Sem `PersonMask`. Sem importar Tamanho, Largura, Altura nem os outros Fields. Um slider só, sem Geral / L / R.
- Convenção: **esquerda = `\`** (canto esquerdo sobe); **direita = `/`** (canto esquerdo desce).
- Runtime: o unitário é `w · (y − c.y)` e `w · −(x − c.x)`; o slider só entra em `θ(t)`.
- Cadeia: depois da Altura (`… → lip_height → lip_angle → jaw → …`). Tab **Lábios**, ícone Ângulo à direita de Altura.
- Spec: [`v2-lip-angle.md`](./v2-lip-angle.md).

### Eyebrow End — Sprint D

- Key: `eyebrow_end` («Ponta»). **Não** é `eyebrows`. **Não** é `eyebrow_height` nem `eyebrow_width`. **Não** é Length / Front / Angle / Shape.
- Sprint D (2026-09-04). C assinada. Tab **Sobrancelha**, ícone Ponta à direita de Largura. Slider bipolar com L/R da foto. Sem E escrita. Altura, Largura e os Fields vivos intactos.
- Campo: só Δx. `dy = 0`. `dx = t_lado · 0.030 · faceWidth · w · band · s_inner · away`. `away = 2·leftFrac − 1`. `s_inner` por lado (`u` em 336→300 e 107→70; 1 se `u ≤ 0.12`, 0 se `u ≥ 0.48`, smoothstep) e só depois mistura com `leftFrac` — misturar os extremos primeiro colapsava o vão e o gate saltava. `band` gaussiana em torno do eixo (`σ = 1.4 · halfBand`). Junta: pontas 336/107 para a midline. Separa: para fora. Cauda 300/70 e arco 334/105 quase parados. Amplitude calibrada 2026-09-04: `0.010`…`0.020` ainda sutis; vigente `0.030`. Mesmo `lidGate` da Altura (cópia, sem importar). Sem `RidgeWeight`. Sem `PersonMask`.
- Convenção: **esquerda junta** (`t < 0`); **direita separa** (`t > 0`). L/R da foto. Foto esquerda = MP direita (107); foto direita = MP esquerda (336).
- Runtime: `unitWeight` = `w · band · s_inner · away`; o slider só escala `dx`.
- Lab B: 21 `v2Raw`. `invalidCount = 0`. Pior `minDetJ` 0,792 (p05 t=−1). Pico ~2,5–3,1 px. Relatório [`v2-eyebrow-end-b-report.md`](./v2-eyebrow-end-b-report.md).
- Módulo: `warp/v2/eyebrow_end/`. Não importa Altura nem Largura nem os outros Fields.
- Cadeia: depois da Largura (`head → hairline → eyebrow_height → eyebrow_width → eyebrow_end → jaw → …`). Tab **Sobrancelha**, ícone Ponta. Preview e export partilham `applyFaceWarpChain`.
- Spec: [`v2-eyebrow-end.md`](./v2-eyebrow-end.md). Plano: [`v2-eyebrow-end-plan.md`](./v2-eyebrow-end-plan.md). C: [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md). D: [`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md).

---

## Roadmap de produto (aprovado)

**Adenda 2026-09-02 (latência, segunda ronda).** Leonardo, depois de a Mandíbula sozinha passar a 14 ms: «quero que seja rápido em todos os efeitos por mais que eu tenha selecionado 1 ou outro já, pode fazer isso? sem estragar o que funciona». O rebuild dos efeitos a jusante é inevitável — a advecção muda-lhes a geometria — mas corria na imagem inteira quando o efeito ocupa 6–13% dela. Seis correcções, todas com o resultado inalterado e cada uma com um teste que a compara com a definição que substitui: remap só no suporte do campo dilatado de um pixel (18,3→9,4 ms); rampa de fronteira numa janela recortada (25,8→5,7 ms); `fillPolygon` por linha em vez de percorrer o anel por pixel (14,2→1,3 ms no oval de 36 vértices); `dilate` só na caixa do que está marcado (12,5→3,8 ms); `RidgeWeight` com os segmentos em `Float64List` e `stronger` a descartar o lado que não pode ganhar (32,8→20,8 ms); `supportBox` no envelope malar do `cheekbone`, que era avaliado nos 711 680 pixels (rebuild 234→75 ms). **Arrastar só a Mandíbula: 3,9 ms (256 fps). Com dois efeitos a jusante: 258→91 ms.** Os seis rebuilds somados: 437→291 ms. Suíte inteira verde (535 testes) sem mover um único limite de qualidade. **Descartado com medição:** baixar a resolução do preview no arrasto dá 31 ms (32 fps) a 50% do lado, mas a resolução é a chave de `ParsingMaskCache`, `RenderStageCache`, dos `*FieldRuntime` e do pool de texturas — com retoque de pele activo forçaria re-inferir o parsing por frame e sairia mais lento, e os sliders faciais não têm `onChangeStart`/`onChangeEnd` onde ligar o modo. Falta, para tempo real com vários efeitos: warp fora da thread da UI, ou campo na GPU. Relatório [`v2-latencia-preview.md`](./v2-latencia-preview.md).

**Adenda 2026-09-02 (aliasing na compressão).** Leonardo, com a rampa já corrigida e só a Mandíbula a 100%: «está 98%, no meio das linhas vermelhas fica um pouco serrilhado», marcando uma faixa na bochecha, interior e não a silhueta. **O campo não era o culpado:** medida a alta frequência do `jaw` bem dentro do domínio, o pior resíduo é 0,06–0,13 px e as vizinhanças variam monotonamente. O defeito é de **amostragem**. O remap é `src = p − D(p)`, cuja jacobiana é `I − JD`; onde o maior valor singular passa de um, um passo de um pixel no destino salta mais de um pixel na origem e a bilinear, que só lê 2×2, deixa cair o que fica no meio. Com o `jaw` no extremo isso apanha **42% dos pixels deslocados, até 1,43×** de compressão, nas cinco faces. Medido contra o filtro de área exacto (8×8 sub-amostras) num alvo de contraste 20–245: erro **33 de RMS e 57 de pior caso**. Corrigido em `BackwardBilinearWarp` com filtragem por área nos pixels que comprimem (grelha de `n×n` sub-amostras, `n = ⌈σ_max⌉` até 3, campo lido interpolado), mantendo a bilinear pura acima de `σ_max ≤ 1,05` — translação pura não perde nitidez, e quem não comprime sai byte a byte igual. Erro passou a **2,8 de RMS e 7 de pior caso**, doze vezes menos. Custo: +6,4 ms por remap (17,8 contra 11,4 ms a 695×1024), contra os ~113 ms que cada campo já leva a construir. Agrava-se no preview mas **não é um defeito só do preview**: a compressão é uma razão de gradientes e a amplitude escala com a cara, logo existe igual no export; o preview apenas a amplia, porque corre a 720–1080 px e é esticado para o ecrã com `FilterQuality.medium`. Relatório [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

**Adenda 2026-09-02 (serrilhado fino da rampa).** Leonardo, depois do bico resolvido: «está quase perfeito, quase; ficaram alguns serrilhados bem pequenos, mas geram reclamações dos clientes», com setas sobre a fronteira pele/cabelo na têmpora. Medido pixel a pixel na travessia da fronteira do domínio: o campo entrava a **0,23 px de golpe** no `v_shape` e 0,20 px no `jaw`, porque a rampa era linear e arranca com derivada `1 / falloff` — o primeiro pixel activo vale já um passo inteiro. As máscaras são binárias e rasterizadas a pixel cheio, portanto a fronteira sai em dentes de um pixel e esse passo corre em degraus ao longo dela; num limite de contraste máximo, a pele contra o cabelo, lê-se como serrilhado apesar de ser sub-pixel. Corrigido em `BoundaryFeather`, sem tocar em nenhum efeito: rampa **smoothstep** (derivada nula nas duas pontas, portanto entra do zero sem passo e fecha sem joelho) e alisamento da distância com σ fixo de 1,2 px, descontando `σ/√(2π)` para devolver o zero à fronteira. Degrau de entrada, pior das cinco amostras nos dois extremos: `jaw` 0,20→0,042, `v_shape` 0,23→0,029, `chin` 0,063, `v_chin` 0,089, `jaw_angle` 0,029. `minDetJ` continua positivo em todos (mínimo 0,196 no `chin` a t=−1); curvatura no núcleo desceu ou manteve-se. Custo: +8% na construção dos campos (682 ms contra 631 ms para os seis a 695×1024). **Pendência:** o `cheekbone` fica em 0,244 porque quem lhe manda o campo a zero junto à orelha é a rampa de 13 px do `earFalloff`, curta de mais para a zona onde o efeito está no pico — encurtar esse degrau é recalibrar o `earFalloff`, decisão do Sprint do efeito. Relatório [`v2-serrilhado-distancia.md`](./v2-serrilhado-distancia.md).

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

**Adenda 2026-09-30 (Lip Angle).** Leonardo, com o Meitu em Lábios → Angle, slider ao centro, à direita e à esquerda: «agora faca o angle  ele movimenta na diagonal». Rotação em volta do centróide, `θ = 0.12 t`. Direita: canto esquerdo da foto desce, direito sobe. Esquerda: o contrário. Tab **Lábios**, key `lip_angle`, cadeia depois de `lip_height`. Tamanho, Largura e Altura intactos. Sem Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-angle.md`](./v2-lip-angle.md).

**Adenda 2026-09-30 (Lip Width + Lip Height).** Leonardo, com o Meitu em Lábios → Height, slider à direita: «aplique o width e i Heigth agora, heigth para o lado direito a barra a boca sobe.. e para lado esquedo, ela desce... width é praticamente a mesma coisa que o  tamanho que foi aplicado agora pouco..». Largura: escala só em x, `k = 0.12`. Altura: translação Δy, `0.024 × faceWidth`. Tab **Lábios**, keys `lip_width` / `lip_height`, cadeia depois de `lip_size`. Tamanho intacto. Sem Angle / Rotate / M-shaped. Sem B/C/E. Specs [`v2-lip-width.md`](./v2-lip-width.md) e [`v2-lip-height.md`](./v2-lip-height.md).

**Adenda 2026-09-30 (Lip Size).** Leonardo, com o Meitu em Lábios → Size, slider à direita e à esquerda: «Agora vamos para o menu de labios, o primeiro menu é o tamanho.  para o lado direito, diminui, e para o lado esquerdo aumenta, é umd etalhe bem suave». Escala isotrópica em volta do centróide, `k = 0.12`. Tab **Lábios**, key `lip_size`, cadeia depois de `nose_bridge`. Nariz intacto. Sem Angle / Rotate / M-shaped. Sem B/C/E. Spec [`v2-lip-size.md`](./v2-lip-size.md).

**Adenda 2026-09-30 (Nose Bridge).** Leonardo, com o Meitu em Nariz → Bridge, slider à direita e à esquerda: «oq seria o Bridge? pode fazer?». Largura do dorso (terço do meio). Só Δx. `k = 0.28`. Tab **Nariz**, key `nose_bridge`, cadeia depois de `nose_ala`. Tamanho, Elevação e Largura intactos. Sem Root / Tip. Sem B/C/E. Spec [`v2-nose-bridge.md`](./v2-nose-bridge.md).

**Adenda 2026-09-30 (Nose Ala).** Leonardo, com o Meitu em Nariz → Ala, Geral / esquerda / direita e o slider à esquerda: «agora vamos para largura  (ala) tem direita e esquerda, barra para o lado direito diminui a largura e pro lado esquerdo aumenta.. se selecionar lado esquerdo no geral, so o lado esqerduo vai receber os ajustes, e vice versa». Só Δx em volta da midline. `k = 0.24`. Tab **Nariz**, key `nose_ala`, cadeia depois de `nose_lift`. Tamanho e Elevação intactos. Sem Root / Bridge / Tip. Sem B/C/E. Spec [`v2-nose-ala.md`](./v2-nose-ala.md).

**Adenda 2026-09-30 (Nose Lift).** Leonardo, com o Meitu em Nariz → Lift, slider à direita e à esquerda: «vou te mandar oq cada print representa lif faca primeiro.  ele sobe o nariz se lado direito e desce se lado esquerdo .. faca apenas o lift antes». Só Δy. Perfil 0 na raiz (168), 1 na ponta e nas asas. Tab **Nariz**, key `nose_lift`, cadeia depois de `nose_size`. Tamanho intacto. Sem Ala / Root / Bridge / Tip. Sem B/C/E. Spec [`v2-nose-lift.md`](./v2-nose-lift.md).

**Adenda 2026-09-30 (Nose Size).** Leonardo, com o Meitu em Nariz → Size: «agora vamos para o nariz, criar um menu de nariz.. e dentrod ele o primeiro menu de tamanho.. size para o lado direito, ele diminui como umt odo o nariz de forma natural.. nao é absurdo a diminuicao.. e par ao lado esquerdo ele aumenta o nariz, seguindo proporcoes ideiais.. sem exagero, fica muito natural, replique essa engenharia». Escala isotrópica em volta do centróide, `k = 0.14` (`s` de 0,86 a 1,14), igual à Cabeça no nariz. Tab **Nariz**, key `nose_size`, cadeia depois de `eye_distance`. Não é `nose_slim`. Olhos e os outros Fields intactos. Sem Lift / Ala / Root / Bridge / Tip. Sem B/C/E. Spec [`v2-nose-size.md`](./v2-nose-size.md).

**Adenda 2026-09-30 (Eye Puffy, interior do olho).** Leonardo, a 99, contra o Meitu a 100: «vc clareou dentro do olho, nao é isso q queremos.. observe a segunda imagem do meitu.. é desse jeito que quero  ele so mexe na parte da olheira mesmo». O oval começava a meio do olho (`centro + 0,72 · radiusY`) e o corte da íris só cobria 62% do raio, logo a linha d'água e a esclera clareavam. O oval passou a nascer debaixo da pestana e a abertura do olho ficou a zero no interior.

**Adenda 2026-09-30 (Eye Puffy, sulco).** Leonardo, a 100, nas duas fotos, com ovais vermelhos na pálpebra inferior e no sulco: «ainda n teve resultado.. a area das olheiras sao essas». A faixa era estreita demais e a referência (bochecha distante) deixava o vão a zero. A máscara passou a ser o oval inteiro dessa zona. A referência passou a ser a pele logo à volta. Sobe a baixa frequência; o poro fica.

**Adenda 2026-09-30 (Eye Puffy, pálpebra).** Leonardo, a 98, nas duas fotos: «nao esta legal ainda». A faixa tinha descido para a bochecha e o corte do olho apagava a pálpebra, que é onde a sombra está. O borrão largo misturava essa sombra com a pele ao lado e o vão desaparecia. A faixa voltou à pálpebra inferior e ao sulco, inclinada ao nariz. A íris fica de fora. O borrão ficou à escala do poro e a sombra sobe 88% do vão.

**Adenda 2026-09-30 (Eye Puffy, oval).** Leonardo, com Olheiras a 97: «ficou muito feio». O crescente era um disco e a referência era a metade mais clara da bochecha, por isso a pele do sulco — mesmo a que já estava bem — era substituída por um tom pálido e o poro sumia. A faixa ficou fina, debaixo da pálpebra e inclinada ao nariz. A referência passou ao miolo da bochecha. Sobe a sombra borrada (62% do vão) e o poro fica. Pele já no tom da bochecha não se pinta.

**Adenda 2026-09-29 (Eye Puffy, um slider).** Leonardo, com Olheiras a 97: «nao mudou nada... e tbm nao tem olheira direita e esquerda é tudo uma so.. tem q ficar igual na imagem 2». A protecção do olho (pad 0,08 da imagem) zerava o peso de pele no sulco, a máscara da olheira exigia essa pele, e a referência era a cara inteira — com barba, tão escura como a olheira, o passe saltava todos os pixels. O crescente passou a viver debaixo da pálpebra, sem depender do peso de pele, e a referência passou a ser a metade mais clara da bochecha. O chip Geral / esquerda / direita saiu: um slider clareia os dois olhos. O olho não se mexe.

**Adenda 2026-09-29 (Eye Puffy, cor).** Leonardo, com Olheiras a 97: «esta errado ainda.. voce esta fazendo a olheira fechar o olho.. ele deveria apenas remover a olheira (parte mais escura que temos em baixo do olho … deixar mais claro». O warp saiu da cadeia. O slider passou a clarear a pele escura debaixo do olho, no passe A3, sem mover a pálpebra.

**Adenda 2026-09-29 (Eye Puffy, pálpebra).** Leonardo, com Olheiras a 99: «olheiras nao retirou nada». A tentativa de levantar a pálpebra fechava o olho. Superada pela adenda de cor no mesmo dia.

**Adenda 2026-09-29 (Eye Puffy).** Leonardo, com o Meitu em Olhos → Olheiras: «agora vamos para olheiras.» O slider à esquerda deixa a pele como está. À direita a bolsa debaixo do olho sobe. A íris fica. Tab **Olhos**, key `eye_puffy`, cadeia depois de `eye_distance`. Não é o retoque de pele `remove_dark_circles`. Distância e os outros Fields intactos. Sem B/C/E. Spec [`v2-eye-puffy.md`](./v2-eye-puffy.md).

**Adenda 2026-09-29 (Eye Distance, pálpebra).** Leonardo, com a Distância a −90: «ficou um ponto fixo e puxou somente o restante». A porta da sobrancelha de `0.10 × faceWidth` segurava a pálpebra (em p01, 2,3 px contra 7,0 da íris). A porta passou a ser o vão até 159/386, com borrão curto. A pálpebra ficou a 10,3 px contra 11,4 da íris. Sobrancelha, nariz e os outros Fields intactos.

**Adenda 2026-09-29 (Eye Distance).** Leonardo, com o Meitu em Olhos → Distance: «agora vamos para Distance». Direita afasta os olhos, esquerda aproxima. O olho inteiro anda, íris incluída. Tab **Olhos**, key `eye_distance`, cadeia depois de `eye_length`. Tamanho, Altura, Largura e Comprimento intactos. Puffy não entra. Sem B/C/E. Spec [`v2-eye-distance.md`](./v2-eye-distance.md).

**Adenda 2026-09-29 (Eye Length).** Leonardo, com o Meitu em Olhos → Length: «agora vamos para o length». Direita alonga pelo canto externo, esquerda encurta. Íris e canto interno ficam. Tab **Olhos**, key `eye_length`, cadeia depois de `eye_width`. Tamanho, Altura e Largura intactos. Distance / Puffy não entram. Sem B/C/E. Spec [`v2-eye-length.md`](./v2-eye-length.md).

**Adenda 2026-09-29 (Eye Width).** Leonardo, com o Meitu em Olhos → Width: «vamos para o Width agora olhe como se comporta». Direita alarga na horizontal, esquerda estreita. A altura do olho fica. Tab **Olhos**, key `eye_width`, cadeia depois de `eye_height`. Tamanho e Altura intactos. Length / Distance / Puffy não entram. Sem B/C/E. Spec [`v2-eye-width.md`](./v2-eye-width.md).

**Adenda 2026-09-29 (Eye Height).** Leonardo, com o Meitu em Olhos → Height: «agora vamos para o height… note como é o movimento… tambem é possivel aumentar a altura e diminuir somente de 1 olho». Direita sobe, esquerda desce. Tab **Olhos**, key `eye_height`, cadeia depois de `eye_size`. Tamanho intacto. Width / Length / Distance / Puffy não entram. Sem B/C/E. Spec [`v2-eye-height.md`](./v2-eye-height.md).

**Adenda 2026-09-29 (Eye Size).** Leonardo, com o Meitu em Olhos → Size: «vamos para criacao do menu de olhos… o primeiro menu interno do olho q vamos fazer é o tamanho… após eu aprovar esse menu, vamos para o proximo». Slider à esquerda encolhe, à direita aumenta. Tab **Olhos**, key `eye_size`, cadeia depois de `eyebrow_end`. Height / Width / Length / Distance / Puffy não entram. Sem B/C/E. Spec [`v2-eye-size.md`](./v2-eye-size.md).

**Adenda 2026-09-05 (Lab p15).** Leonardo: «crie um novo lab… p15 com essa foto». Foto `phase12/p15-office-blazer.png` (1620×1080, a origem era 540×360) + 478 landmarks `benchmark/real/p15-office-blazer.json`. Botão **Lab p15** no editor, a seguir a p01/p05/p12. O `p15.jpg` antigo do dump phase12 (pexels-415829) fica intacto e **não** é o lab V2. As matrizes oficiais A/B continuam p01 / p05 / p12; p15 entra no manifest de rostos reais (`real-p15`) para uso futuro, sem alargar as suítes A.

**Adenda 2026-09-04 (Eyebrow End amplitude).** Leonardo, no editor: «podemos chegar mais a ponta do meio», «aumente um pouco mais» e depois «podemos aumentar mais sem quebrar?? tipo uns 0.030». Amplitude `0.010` → `0.016` → `0.020` → `0.030`. Equação, `s_inner`, `lidGate` e os outros Fields intactos. Tecto `influenceMax < 0.040 × faceWidth`.

**Adenda 2026-09-04 (Eyebrow End D).** Leonardo: «implemente a proxima». C assinada. Tab Sobrancelha, key `eyebrow_end`, cadeia depois da Largura. Sem E escrita. Relatório [`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md).

**Adenda 2026-09-04 (Eyebrow End C).** Leonardo: «implemente a proxima», depois do lab B. C assinada das 21 `v2Raw`. Field intacto. Sem UI. Relatório [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md).

**Adenda 2026-09-04 (Eyebrow End B).** Leonardo: «implemente a proxima». Lab `v2Raw` 21 runs (Geral ±1/±0,5/0 + L100/R100) em p01/p05/p12. `invalidCount = 0`. Sem fill. Sem UI. Field intacto. Relatório [`v2-eyebrow-end-b-report.md`](./v2-eyebrow-end-b-report.md).

**Adenda 2026-09-04 (Eyebrow End A).** Leonardo, com o ícone Meitu End (seta para a ponta interna): «agora vamos criar o efeito da sobrancelha tbm chamado end… junta a sobrancelha se o slider for pra esquerda e separa se for pra direita, bem sutil, sem estragar e movendo apenas a sobrancelha». Sprint A (`eyebrow_end`). Meitu End = ponta **interna** (glabela), não a cauda. Campo só Δx no terço interno. Amplitude `0.010 × faceWidth`. Sem makeup `eyebrows`. Sem Length/Front/Angle/Shape. Sem cadeia. Sem slider. Altura, Largura e os Fields vivos intactos. Spec [`v2-eyebrow-end.md`](./v2-eyebrow-end.md).

**Adenda 2026-09-04 (Eyebrow Width D).** Leonardo: «implemente a proxima», com `p01/0/original.png` do lab aberto. C assinada. Tab Sobrancelha, key `eyebrow_width`, cadeia depois da Altura. Sem E escrita. Relatório [`v2-eyebrow-width-d-report.md`](./v2-eyebrow-width-d-report.md).

**Adenda 2026-09-04 (Eyebrow Width C).** Leonardo avançou depois do lab B. C assinada das 21 `v2Raw`. Field intacto. Relatório [`v2-eyebrow-width-c-report.md`](./v2-eyebrow-width-c-report.md).

**Adenda 2026-09-04 (Eyebrow Width B).** Leonardo: «implemente a proxima entao». Lab `v2Raw` 21 runs (Geral ±1/±0,5/0 + L100/R100) em p01/p05/p12. `invalidCount = 0`. Sem fill. Sem UI. Field intacto. Relatório [`v2-eyebrow-width-b-report.md`](./v2-eyebrow-width-b-report.md).

**Adenda 2026-09-04 (Eyebrow Width A).** Leonardo, depois da Altura no editor, com o ícone Meitu Width: «agora precisamos de outra que é a largura da sobrancelha… mesma estrutura da altura, mas deixar ela minimamente mais larga… bem pouca coisa para ficar bem real… uma leve engrossada». Sprint A (`eyebrow_width`). **Não** é planalto da Altura (isso só traduz). Campo assinado a partir do eixo: arco sobe, base desce. Amplitude `0.008 × faceWidth`. Sem makeup `eyebrows`. Sem Length/End/Front/Angle/Shape. Sem cadeia. Sem slider. Altura e os Fields vivos intactos. Spec [`v2-eyebrow-width.md`](./v2-eyebrow-width.md).

**Adenda 2026-09-04 (Eyebrow Height D).** Leonardo: «implemente a sprint proxima». Tab Sobrancelha, key `eyebrow_height`, cadeia depois do Hairline. Sem E escrita. Relatório [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md).

**Adenda 2026-09-04 (Eyebrow Height C).** Leonardo: «Pode seguir para a proxima sprint», com `p01/100/v2Raw.png` aberto, depois da calibração da dobra. C assinada das 21 `v2Raw`. Field intacto. Relatório [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md).

**Adenda 2026-09-04 (Eyebrow Height pálpebra externa).** Leonardo, no lab B: «está quase perfeito, mas está puxando essa região do olho… parece as pálpebras», com círculos nos cantos externos da pálpebra superior (dobra / sulco, não o centro 159/386). O hull do olho parava no cílio; o pad `0.14` da brow descia até essa dobra e o `lidGate` deixava ~70% do pico (4,6 px em p01 t=0,5). Calibração: o hull dos olhos ganha a prateleira `0.026 × faceWidth` no terço externo (33/246/161, 263/466/388) e amostras no vão cauda→canto a 30/45/58% (para antes do pelo 70/300). Dobra ≤ 0,09 px no extremo (~0,6% do pico). Arco 105/334 e ilha 52/282 intactos. Amplitude e `k` intactos.

**Adenda 2026-09-04 (Eyebrow Height B).** Leonardo: «implemente sprint b». Lab `v2Raw` 21 runs (Geral ±1/±0,5/0 + L100/R100) em p01/p05/p12. `invalidCount = 0`. Sem fill. Sem UI. Relatório [`v2-eyebrow-height-b-report.md`](./v2-eyebrow-height-b-report.md).

**Adenda 2026-09-04 (Eyebrow Height A).** Leonardo abriu o menu Sobrancelha, primeiro ícone Altura: esquerda baixa, direita sobe, Geral/L/R da foto. Sprint A (`eyebrow_height`). Sem makeup `eyebrows`. Sem Width/Length/Shape. Sem cadeia. Sem slider. Os Fields vivos intactos. Spec [`v2-eyebrow-height.md`](./v2-eyebrow-height.md).

**Adenda 2026-09-04 (Head asas laterais).** Leonardo, Cabeça a 100% (encolhe): cara/queixo bons; o cabelo volumoso dos lados (olhos→ombros) parado. O mesh acaba na orelha (`323/454`); sem `PersonMask` o `w` era 0 nessa massa. Calibração: pontos virtuais Δx `0.34 × faceWidth` em têmpora→orelha→gónio (`21 162 127 234 93 132 58 172` / `251 389 356 454 323 361 288 397`), no hull e no `R₊`. Sem parsing. Sem Temple / Hairline / Bloqueio de fundo.

**Adenda 2026-09-04 (Head D).** Leonardo: «proxima sprint». Tab Proporção, key `head`, cadeia no início. Sem E escrita. Relatório [`v2-head-d-report.md`](./v2-head-d-report.md).

**Adenda 2026-09-04 (Head C).** Leonardo: «implemente proxima sprint». C assinada dos 15 `v2Raw`. Banda no cap ao encolher em p01/p05 aceite (crop, sem fill). Relatório [`v2-head-c-report.md`](./v2-head-c-report.md).

**Adenda 2026-09-04 (Head B).** Leonardo: «implemente a proxima». Lab `v2Raw` 15 runs. Encolher pede origem acima do crop: `invalidSource` no cap em p01 (7 311 / 14 270) e p05 (3 554 / 6 825); p12 a 0. Sem fill. Relatório [`v2-head-b-report.md`](./v2-head-b-report.md).

**Adenda 2026-09-04 (Head aberto).** Leonardo pediu o menu Proporção e o Head: esquerda a cabeça toma o quadro, direita afasta; os landmarks têm de ir com ela para o queixo/mandíbula não dessincronizarem. Abre-se Sprint A (`head`). Sem zoom de câmara (bordas `invalidSource`). Sem Bloqueio de fundo. Sem `head_size`. Sem cadeia. Sem slider. Os sete Fields vivos intactos. Spec [`v2-head.md`](./v2-head.md).

**Adenda 2026-09-03 (Hairline a partir da linha).** Leonardo: a linha tracejada (arco pele/cabelo, têmpora a têmpora) **não mexe**; o cabelo cresce ou diminui a partir dela, no arco todo, em todas as fotos. O Field radial `D ∝ w · (p − 9)` com crista no cume estava errado: a linha mexia e só o topo do cap tinha energia. Equação vigente: `D ∝ w · (p − q)`, `q ∈ L`, testa e linha a zero, sem decaimento transversal. Sem Temple.

**Adenda 2026-09-03 (Hairline flancos do cap).** Leonardo, ainda só o topo a subir: «precisa subir também um pouco os lados…». Superada no mesmo dia pela equação a partir da linha.

**Adenda 2026-09-03 (Hairline linha+têmporas).** Leonardo, com o cap já a subir: «precisa fazer isso… a linha em si começa no final da testa, e puxa levemente até as têmporas, mas não tanto, apenas para não dar os cortes secos». Crista passa a testa→cap numa só polilinha; origem do leque no 9; cauda 0,08 no 21/251. Sem disco. Sem Temple. Superada no mesmo dia pelos flancos do cap.

**Adenda 2026-09-03 (Hairline C).** Leonardo: «implemente a sprint c». C assinada do Field radial + crista no cap. A–E fechadas. Vivo (`hairline`). Relatório [`v2-hairline-c-report.md`](./v2-hairline-c-report.md). Não alterar salvo calibração pedida por escrito.

**Adenda 2026-09-03 (Hairline D).** Leonardo: «implemente a proxima sprint quero ver como ficou no aparelho». Key no painel, cadeia, ícone. Superada no mesmo dia pela C.

**Adenda 2026-09-03 (Hairline radial).** Leonardo, depois da B Δy-only: «não vi diferença nenhuma… o movimento é da parte de dentro da cabeça/testa pra fora, e quando diminuir de fora pra dentro». A primeira A/B (só Δy no 10) fica rejeitada. A reabre com escala radial `D ∝ w · (p − 151)`, crista levantada ao cap, factor `0.10`. O unitário `A · w · n` invertia (`minDetJ` −5); `0.16` no cap também (`−0,24`). Sem C. Sem cadeia.

**Adenda 2026-09-03 (Hairline B).** Leonardo autorizou a Sprint B do Field Δy-only. Lab `v2Raw` 15 runs. **Superada** no mesmo dia pela rejeição visual: o contorno do cabelo não mexia. Relatório antigo [`v2-hairline-b-report.md`](./v2-hairline-b-report.md) descreve o Field morto.

**Adenda 2026-09-03 (Hairline aberto).** Leonardo pediu o Hairline: infla / desincha o topo, sem picos, só em cima. Abre-se Sprint A (`hairline`), sem ligar cadeia nem slider. Temple não se abre. Os seis Fields vivos intactos. Spec [`v2-hairline.md`](./v2-hairline.md).

**Adenda 2026-08-26 (Chin Length bipolar).** Leonardo reabriu o Chin **só** para slider bipolar (alongar + encurtar, rótulo «Tamanho do queixo»). Calibração vigente: amplitude `0.07 × faceWidth`, crista no oval até 172/397 (cauda 0.08, só Δy; gônios fora da crista). Preview de rosto sem debounce (coalesce). Documento [`v2-chin-length-bipolar.md`](./v2-chin-length-bipolar.md). Cheekbones H intacto.

Ordem seguinte **depois** de Cheekbones (C → D → E):

1. Temple
2. Hairline — **feito** (aprovado 2026-09-03)
3. Width — baixa prioridade (o Jaw já cobre o essencial em Δx)
4. Lift
5. Double Chin — bloqueado (falta pescoço)

V Chin: **feito** (aprovado 2026-08-26).  
Hairline: **feito** (aprovado 2026-09-03).  
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
- [`v2-latencia-preview.md`](./v2-latencia-preview.md) — perfil de latência do preview; peso unitário em cache por efeito, janela da região activa, e o que falta para tempo real com vários efeitos

**Vigente para Jaw Angle**

- [`v2-jaw-angle.md`](./v2-jaw-angle.md) — **Field e UI no disco**; inspecção no editor (não é C)

**Vigente para V Shape**

- [`v2-v-shape.md`](./v2-v-shape.md) — **Field e UI no disco**; inspecção no editor (não é C)

**Vigente para V Chin**

- [`v2-v-chin.md`](./v2-v-chin.md) — **aprovado e encerrado** (Field e UI no disco)

**Vigente para Eyebrow End**

- [`v2-eyebrow-end.md`](./v2-eyebrow-end.md) — D no editor (Field + UI)
- [`v2-eyebrow-end-plan.md`](./v2-eyebrow-end-plan.md) — plano A–E (A–D feitas)
- [`v2-eyebrow-end-b-report.md`](./v2-eyebrow-end-b-report.md) — lab vigente
- [`v2-eyebrow-end-c-report.md`](./v2-eyebrow-end-c-report.md) — C assinada 2026-09-04
- [`v2-eyebrow-end-d-report.md`](./v2-eyebrow-end-d-report.md) — D no editor

**Vigente para Eyebrow Width**

- [`v2-eyebrow-width.md`](./v2-eyebrow-width.md) — D no editor (Field + UI)
- [`v2-eyebrow-width-plan.md`](./v2-eyebrow-width-plan.md) — plano A–E (A–D feitas)
- [`v2-eyebrow-width-b-report.md`](./v2-eyebrow-width-b-report.md) — lab vigente
- [`v2-eyebrow-width-c-report.md`](./v2-eyebrow-width-c-report.md) — C assinada 2026-09-04
- [`v2-eyebrow-width-d-report.md`](./v2-eyebrow-width-d-report.md) — D no editor

**Vigente para Eyebrow Height**

- [`v2-eyebrow-height.md`](./v2-eyebrow-height.md) — D no editor (Field + UI)
- [`v2-eyebrow-height-plan.md`](./v2-eyebrow-height-plan.md) — plano A–E (A–D feitas)
- [`v2-eyebrow-height-b-report.md`](./v2-eyebrow-height-b-report.md) — lab vigente
- [`v2-eyebrow-height-c-report.md`](./v2-eyebrow-height-c-report.md) — C assinada 2026-09-04
- [`v2-eyebrow-height-d-report.md`](./v2-eyebrow-height-d-report.md) — D no editor

**Vigente para Head**

- [`v2-head.md`](./v2-head.md) — D no editor (Field + UI)
- [`v2-head-plan.md`](./v2-head-plan.md) — plano A–E (A–D feitas)
- [`v2-head-b-report.md`](./v2-head-b-report.md) — lab vigente
- [`v2-head-c-report.md`](./v2-head-c-report.md) — C assinada 2026-09-04
- [`v2-head-d-report.md`](./v2-head-d-report.md) — D no editor

**Vigente para Hairline**

- [`v2-hairline.md`](./v2-hairline.md) — **aprovado e encerrado** (Field e UI no disco)
- [`v2-hairline-plan.md`](./v2-hairline-plan.md) — plano A–E (fechado)
- [`v2-hairline-b-report.md`](./v2-hairline-b-report.md) — lab vigente (radial)
- [`v2-hairline-c-report.md`](./v2-hairline-c-report.md) — C assinada 2026-09-03

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
