# Cheekbones Sprint A Experimental — CheekbonesField

**Arquivo.** Código no disco **não** é A1. Vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).


Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md), [`v2-cheekbones-plan.md`](./v2-cheekbones-plan.md), [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md).  
Comportamento visado (pesquisa encerrada): [`v2-cheekbones-product-analysis.md`](./v2-cheekbones-product-analysis.md).

```
CheekbonesField.build(face:, imageSize:, t:) → DisplacementField
```

`t` em `[0, 1]`. t=0 → campo zero. Sem `BackwardBilinearWarp` neste módulo.

Esta Sprint A experimental **não** valida uma família de implementação. **Não** demonstra equivalência visual ao Meitu. Os mapas A comprovam um subconjunto estreito (secção seguinte e avaliação crítica). O resto permanece hipótese.

---

## Hipótese do primeiro protótipo

**Um pad malar unimodal por lado** — um único máximo de energia em cada lado, queda suave, domínio definido pelo próprio peso (não por um polígono).

No Field (descrição da implementação, não evidência visual):

- pico em 123 / 411 (localizam a região);
- eixos lateral (afasta da midline) e inferior;
- σ anisotrópico cortado por órbita / sulco / gônio / orelha;
- peso gaussiano `exp(−½ ((u/σu)² + (v/σv)²))`;
- rampa só a partir das **protecções** (hard-zero), nunca a partir de um hull malar;
- só Δx para a midline; dy = 0.

Isto não afirma o algoritmo do Meitu. Foi a construção escolhida para atacar a causa geométrica do patch poligonal.

---

## Por que esta hipótese

A análise (Parte 2) isolou a causa do patch da Sprint B poligonal rejeitada:

1. convex hull de 3–4 landmarks → arestas rectas;
2. dilatação não curva;
3. chamfer linear **imprime** esse polígono;
4. `max(Gaussians)` nos vértices → ilhas Voronoi.

A Parte 1 descreve o comportamento visual observado no Meitu. Essa descrição **orientou** a escolha da hipótese. Os mapas A **não** a comprovam.

Um único máximo por lado foi escolhido para atacar aqueles quatro mecanismos. Landmarks localizam a região. Que a energia seja lida como volume anatómico da maçã **não está demonstrado**.

---

## Alternativas descartadas (neste protótipo)

| Alternativa | Motivo do descarte |
|---|---|
| Hull curto + chamfer + `max(Gaussians)` (A/B anteriores) | Causa comprovada do losango nos mapas da B poligonal. |
| Disco isotrópico | Preferência desta A (a análise descreve banda lateral); não foi testado à parte. |
| Envelope de muitos centros / soma de Gaussians no mesmo lado | Não testado; evitado por risco de ilhas, não por prova. |
| Elipse como “o algoritmo do Meitu” | A análise não priorizou família nenhuma. |
| MLS / TPS / ARAP / mesh / neural / multi-pass | Incompatível com a V2. |
| Suporte compacto `(1−r²)²` | Testado nesta A: com paragens curtas (orelha em p01) o \|∇\| inverteu `minDetJ`. Abandonado **neste** protótipo, não como verdicto de família. |
| Recuar o pico para longe de 123/411 | Falhou o gate de 40% em 411 (p01). O pico ficou no primário. |

Nenhuma destas passa a ser “a solução correcta”. Foram decisões deste experimento.

---

## Relação com a análise de produto

O que o Field **tenta**. Não o que os mapas **provam**.

| Análise de produto | O que este Field tenta | O que os mapas A demonstram |
|---|---|---|
| Região exclusivamente malar | Pad no terço médio; hard-zero em Jaw/Chin/olhos/nariz/boca/orelhas | Energia no mid-face; 58/288/152 a zero. Extensão anatómica da maçã: **não medida**. |
| Dois lados | Dois pads | Dois lóbulos separados. Não prova “dois volumes independentes” no sentido de produto. |
| O observador percebe um volume contínuo | Unimodal, sem hull, sem `max` | Continuidade melhor que o losango. Volume anatómico: **não demonstrado**. |
| Redução da maçã | Δx para a midline (`t ∈ [0,1]`) | `cheekbonesNarrows` nas métricas. Percepção de pad: **não avaliada** (sem `v2Raw`). |
| Não parece Jaw / Chin | Energia fora da silhueta mandibular e do mento | Isolamento técnico nos mapas de domínio. Aparência de produto: **não avaliada**. |
| Sem triângulo / losango / facetas | Domínio = suporte do pad | Hull facetado e losango **ausentes**. Carimbo gaussiano e cortes de máscara **presentes**. |
| Bidireccional ± e L/R no Meitu | Fora desta A | Não aplicável. |

---

## Calibração vigente (não contrato)

| Peça | Valor nesta A experimental |
|---|---|
| Primário esquerdo / direito | 123 / 411 |
| Âncoras de localização | 116 / 345 (lateral), 187 / 436 (medial) |
| Paragens | órbita 145 / 374; sulco 203 / 423; orelha 323 / 454 |
| Amplitude | semente `t * 0.04 * faceWidth` |
| σ típico | `0.07 × faceWidth`, cortado pelas paragens |
| Rampa | `0.08 × faceWidth`, só a partir de `protected` |

O contrato do módulo continua a ser a **região malar**. IDs, σ e amplitude são calibração.

---

## Gates

Gates de Field (métricas). Não são equivalência visual.

| Gate | Resultado |
|---|---|
| t=0 campo zero | passou nas 3 fotos |
| t=0.5 `cheekbonesNarrows` | passou |
| `\|dx\|` nos primários > 40% de `influenceMax` | passou (411 em p01 fica perto do limiar) |
| dx esquerdo > 0, direito < 0 | passou |
| dy = 0 em todo o campo | passou |
| `\|d\|` em 58, 288 e 152 = 0 | passou |
| protecções p95 = 0 | passou |
| `outsideCheekZoneP95` = 0 | passou |
| `minDetJ > 0` | passou |
| isolamento de imports | passou |
| testes Jaw / Chin / renderer inalterados | passaram |
| mapas: hull facetado / losango / Voronoi nítido | **ausentes** relativamente à B poligonal |

`v2Raw`: **não existe nesta sprint**. Percepção sobre foto: não avaliada.

---

## Métricas t=0.5

| Foto | amplitude | influenceMax | dx@123 | dx@411 | Δ largura malar | \|d\| 58/288/152 | minDetJ | protect p95 |
|---|---|---|---|---|---|---|---|---|
| p01 | 7.58 | 7.58 | +7.58 | −3.25 | **10.83** | 0 | 0.643 | 0 |
| p05 | 5.75 | 5.74 | +5.73 | −5.74 | **11.47** | 0 | 0.570 | 0 |
| p12 | 6.51 | 6.51 | +6.48 | −6.50 | **12.98** | 0 | 0.528 | 0 |

`maxNeighborJump` ≤ 0.48. JSON: `.cursor/facial-warp-v2/cheekbones/A/{real-p01,real-p05,real-p12}/metrics.json`

---

## O que os mapas demonstram

Fontes: `influence.png`, `displacement.png`, `cheekActive.png`, `protected.png`, `jawDomain.png`, `chinDomain.png` em `.cursor/facial-warp-v2/cheekbones/A/{id}/`.

**Comprovado**

- o domínio deixou de ser um hull facetado;
- o losango desapareceu;
- não há uma ilha claramente Voronoi;
- `influence` mostra dois lóbulos compactos, unimodais, no mid-face;
- `displacement` é só Δx (vermelho/ciano), sem Δy;
- Jaw/Chin de domínio estão isolados nos respectivos mapas; 58/288/152 a zero nas métricas.

**Também visível nos mesmos mapas (não é sucesso)**

- os lóbulos são pequenos; lêem-se como carimbos gaussianos, não como um pad distribuído sobre a maçã;
- as protecções cortam a região activa (discos nítidos, sobretudo à direita);
- o `displacement` reproduz praticamente a mesma forma do `influence` — uma única fonte de energia concentrada, não uma redistribuição de tecido.

A hipótese aproxima-se mais de um volume do que a Sprint B poligonal. Isso é o máximo que estes mapas sustentam.

---

# Avaliação crítica da hipótese

### O que realmente melhorou?

A causa geométrica do patch poligonal foi removida do domínio: já não há hull de 3–4 pontos, nem chamfer a imprimir arestas, nem `max` de handles a criar Voronoi. A continuidade espacial é melhor do que na B rejeitada. Os gates de isolamento (Jaw/Chin/protecções) continuam verdes.

### O que continua artificial?

O `influence` ainda é um par de lóbulos compactos, com queda gaussiana visível. Parece um carimbo, não um envelope da maçã. No lado direito, discos de protecção cortam o lóbulo: o observador ainda lê as máscaras. O domínio deixou de ser um hull; passou a estar condicionado pelas exclusões.

### O que ainda impede leitura anatómica?

Escala (pad pequeno face à maçã), forma (unimodal concentrada), e o recorte das protecções. O `displacement` copia o lóbulo do `influence`: não há sinal, nestes mapas, de energia espalhada pelo tecido malar. Sem `v2Raw`, também não há como julgar se a deformação na foto se lê como redução da maçã.

### O que os mapas não conseguem provar?

- que o observador lê dois volumes anatómicos;
- equivalência visual ao Meitu;
- que a hipótese “reproduz o comportamento da análise”;
- redistribuição de tecido;
- que o Field está pronto como produto.

Provam: remoção do patch poligonal; continuidade melhor; energia unimodal. Nada além disso.

### O que ainda depende da Sprint B?

Qualquer juízo sobre o warp na fotografia (`v2Raw`): se a maçã entra, se o carimbo se vê na pele, se as mordidelas das máscaras aparecem no resultado, se o efeito ainda se distingue de Jaw/Chin. A equivalência visual permanece não demonstrada até essa validação.

---

## Limitações (evidência dos mapas + fora de escopo desta A)

1. **Pad compacto.** Lóbulos pequenos no `influence`; leitura de carimbo gaussiano.
2. **Protecções no formato.** Discos hard-zero visíveis na região activa, sobretudo à direita.
3. **Displacement = influence.** Uma fonte concentrada; a forma do campo não se separa do lóbulo de peso.
4. **Assimetria em p01.** `|dx|` em 411 é ~43% de `influenceMax` (passa o gate; o lóbulo direito é mais fraco).
5. **Um sentido só.** O Meitu é bidireccional e tem L/R. Este Field só estreita, sempre os dois lados. Fora do plano A.
6. **σ e primários são calibração.** Os mapas não mostram que 123/411 sejam o centro visual do pad Meitu.
7. **Sem `v2Raw`.** Sprint B não iniciada.

---

## Se se reabrir a hipótese

Esta A **não** está comprovada como volume malar. Candidatos posteriores (não iniciados), só se houver nova A experimental:

- tratar o recorte das protecções sem devolver o hull;
- alargar ou redistribuir energia **sem** voltar ao polígono de 3–4 pontos;
- **não** voltar ao hull curto + `max(Gaussians)`.

Nenhuma implementação desta A entra no contrato da V2.

---

## Isolamento

O módulo não importa renderer, controller, UI, `extended_roi`, MLS, Telea, `jaw_field.dart`, `chin_field.dart`, `face_slim_field.dart` nem `sourceRgba`. Catálogo partilhado só **lido**.

## Testes

```
flutter test test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart
```

Contratos Jaw / Chin / renderer / displacement: verdes, sem mudança de expectativa.  
O teste de lab B **não foi corrido**. Sprint B não iniciada.

## Arquivos

**Alterados nesta A experimental (código + dumps; o texto deste relatório foi revisto depois, sem novo código)**

- `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart`
- `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_masks.dart`
- `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_metrics.dart` (sem mudança de contrato)
- `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart`
- `docs/beauty/v2-cheekbones-a-report.md` (este relatório)
- `.cursor/facial-warp-v2/cheekbones/A/` — métricas e mapas t=0.5

**Não alterados**

`BackwardBilinearWarp`, `DisplacementField`, `JawField`, módulo `chin/`, `face_slim/`, `RegionMasks`, `FieldMetrics`, `region_catalog.dart`, controller, preview, export, UI, Device Lab, regras V2. Teste de lab Cheekbones B não executado.

---

## Conclusão

A hipótese elimina a principal causa geométrica do patch poligonal observado anteriormente.

Entretanto, os mapas ainda não demonstram que o campo seja percebido como um volume malar anatómico.

A equivalência visual permanece não demonstrada e depende da validação da Sprint B.

Isto **não** promove gaussiana, elipse nem qualquer família a contrato.

## Sprint B

**Não iniciada.** Sem RGBA, sem `v2Raw`, sem lab. Não se inicia sem aprovação explícita.
