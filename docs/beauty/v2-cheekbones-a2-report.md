# Cheekbones Sprint A2 — envelope de arco (interrompida)

**Arquivo.** Código no disco **não** é A2. Vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).


Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md).  
A1 vigente (mapas e avaliação): [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md).  
Comportamento visado (pesquisa encerrada): [`v2-cheekbones-product-analysis.md`](./v2-cheekbones-product-analysis.md).

```
CheekbonesField.build(face:, imageSize:, t:) → DisplacementField
```

`t` em `[0, 1]`. t=0 → campo zero. Sem `BackwardBilinearWarp` neste módulo.

**Sprint B não foi iniciada.** Esta A2 não a autoriza.

---

## Por que A2 existiu (e não B)

A A1 removeu hull, losango e Voronoi nítido. Os próprios mapas A1, e o relatório revisto, concluíram o resto:

- o `influence` lê-se como carimbo gaussiano;
- o `displacement` replica o `influence`;
- as protecções moldam o domínio;
- não há leitura anatómica da maçã.

B continua bloqueada: validar RGBA sobre um campo que ainda não é pad malar só adiaria o diagnóstico. A2 só tenta melhorar o campo geométrico.

---

## Diagnóstico geométrico dos mapas A1

Feito **antes** de alterar código. Fontes: `.cursor/facial-warp-v2/cheekbones/A/{real-p01,real-p05,real-p12}/`.

| Leitura nos mapas A1 | Causa geométrica no Field A1 |
|---|---|
| Carimbo | Um único pico por lado (123 / 411). Iso-contornos concêntricos. Qualquer `exp(−½ r²)` centrado num ponto produz isto. |
| Concentração | `dx = A · w` e `w` é o próprio lóbulo. Uma fonte; o displacement não pode ter outra forma. |
| Cortes | Pico colado a discos hard-zero (orelha em 411/p01; Jaw). `protected` a zero imprime círculos no `cheekActive`. |
| Pouca ocupação da maçã | σ ≈ `0.07 × faceWidth`, ainda cortado pelas paragens. Metade do suporte cai para fora do corpo da maçã (187 / 436). |

Aumentar só o σ alargaria o mesmo carimbo e agravaria a colisão com os discos. Voltar ao hull devolveria o losango. Nenhum dos dois era A2.

---

## Hipótese A2

**Envelope ao longo de um arco malar**, com queda **perpendicular** ao arco, não um pico em 123/411.

No Field (descrição da implementação, não evidência visual):

- polilinha: órbita (111 / 340) → interior da maçã (`lerp` 123/411 com 187/436) → inferior (147 / 425);
- 123 / 411 **não** são o cume — estão no contorno, junto das máscaras; só puxam o interior;
- espessura medial > lateral; cap no sulco (203 / 423) e na orelha;
- peso = gaussiana da distância ao arco × taper nas pontas;
- rampa só a partir de `protected`;
- só Δx para a midline; dy = 0.

Continua `Field.build → DisplacementField → BackwardBilinearWarp`. Sem MLS, TPS, ARAP, mesh, hull poligonal, nem aumento isolado de σ do carimbo A1.

---

## Interrupção

A hipótese foi implementada e medida nas três fotos. Os mapas A2 são **claramente artificiais**. A implementação **parou**. Não se força mais σ, mais arco, nem mais overlap com os discos.

Critério da interrupção (pedido desta sprint): o resultado não é um pad malar; é uma faixa alongada **comida** pelas protecções, com dobras (`minDetJ < 0` nas três faces).

Tentativas intermédias (Bezier que não passava em 123/411; polilinha *por* 123/411; primários em 187/436; falloff 0.10 e 0.18) esbarraram no mesmo facto estrutural: **ocupar a maçã sobrepõe discos hard-zero**. Falloff curto dobra; falloff longo deixa as máscaras comerem o pad. Não há calibração A2 que resolva isto sem mudar o contrato das protecções ou a hipótese.

---

## Calibração desta tentativa (não contrato)

| Peça | Valor nesta A2 (interrompida) |
|---|---|
| Primários de métrica | 123 / 411 (não são o pico do arco) |
| Arco | 111/340 → interior → 147/425 |
| Interior | `lerp(contour, medial, 0.55)` com 187 / 436 |
| Largura medial / lateral | ≈ `0.09` / `0.055–0.08` × faceWidth |
| Amplitude | `t * 0.04 * faceWidth` (igual à A1) |
| Rampa a partir de `protected` | `0.18 × faceWidth` |

O módulo em disco contém **esta** A2, não a A1. A A1 permanece o último estado com `minDetJ > 0`.

---

## Gates

| Gate | A1 | A2 |
|---|---|---|
| t=0 campo zero | passou | passou |
| t=0.5 `cheekbonesNarrows` | passou | passou |
| dx esquerdo > 0, direito < 0 | passou | passou |
| dy = 0 | passou | passou |
| `\|d\|` em 58, 288, 152 = 0 | passou | passou |
| protecções p95 = 0 | passou | passou |
| `outsideCheekZoneP95` = 0 | passou | passou |
| isolamento de imports | passou | passou |
| `minDetJ > 0` | passou | **falhou nas 3 fotos** |
| `maxNeighborJump` | ≤ 0.48 | **4.1 – 5.6** |
| mapas: hull / losango | ausentes | ausentes |
| mapas: leitura de pad malar | não | **não** (faixa mordida) |

O gate de 40% em 123/411 da A1 **não** se aplicou: era o critério do carimbo. Em A2 a energia nos primários caiu (ver métricas).

`v2Raw`: **não existe**. Lab B **não foi corrido**.

---

## Métricas t=0.5

### A1 (referência)

| Foto | influenceMax | dx@123 | dx@411 | Δ largura malar | cheekActive | minDetJ | maxNeighborJump |
|---|---|---|---|---|---|---|---|
| p01 | 7.58 | +7.58 | −3.25 | **10.83** | 34144 | 0.643 | ≤ 0.48 |
| p05 | 5.74 | +5.73 | −5.74 | **11.47** | 21406 | 0.570 | ≤ 0.48 |
| p12 | 6.51 | +6.48 | −6.50 | **12.98** | 26987 | 0.528 | ≤ 0.48 |

### A2 (esta tentativa)

| Foto | influenceMax | dx@123 | dx@411 | Δ largura malar | cheekActive | minDetJ | maxNeighborJump |
|---|---|---|---|---|---|---|---|
| p01 | 7.58 | +3.65 | −1.14 | **4.80** | 54611 | **−4.62** | **5.62** |
| p05 | 5.75 | +3.98 | −2.06 | **6.04** | 27264 | **−3.13** | **4.13** |
| p12 | 6.51 | +4.06 | −2.21 | **6.27** | 33827 | **−3.69** | **4.69** |

JSON A2: `.cursor/facial-warp-v2/cheekbones/A2/{real-p01,real-p05,real-p12}/metrics.json`

O `cheekActive` cresceu (p01 +60%, p05 +27%, p12 +25%). A largura malar medida nos primários **estreitou menos**. Energia saiu de 123/411 e foi cortada nas bordas. `influenceMax` continua ≈ amplitude: o máximo local ainda satura `A`.

---

## O que os mapas A2 demonstram

Fontes: `influence.png`, `displacement.png`, `cheekActive.png`, `protected.png` em `.cursor/facial-warp-v2/cheekbones/A2/{id}/`.

**Comprovado**

- o domínio continua sem hull facetado e sem losango;
- o suporte alongou-se (banda / arco em vez de um único lóbulo compacto);
- `displacement` continua só Δx;
- Jaw/Chin e o resto das protecções continuam a zero nas métricas.

**Também visível (motivo da interrupção)**

- o `influence` é uma faixa, não um volume da maçã; em p05 o lado direito mostra vários máximos ao longo da polilinha (leitura serrada, não um envelope);
- `cheekActive` é uma tira horizontal comida por discos (orelha / Jaw) e por cortes angulares do nariz / faceCenter — o observador lê as máscaras **mais** do que na A1, porque a faixa é mais longa e atravessa mais discos;
- o `displacement` replica a faixa do `influence`, incluindo as mordidelas; `dx = A · w` não mudou de família;
- a queda hard-zero nas bordas dos discos coincide com `maxNeighborJump` ≈ 4–6 e `minDetJ` negativo: o campo **dobra**.

---

## Comparação A1 vs A2

| Critério | A1 | A2 |
|---|---|---|
| Hull / losango / Voronoi nítido | ausentes | ausentes |
| Forma do `influence` | dois lóbulos compactos (carimbo) | faixa / salsicha ao longo do arco |
| Ocupação em pixéis | menor | maior |
| Leitura da maçã | carimbo no primário | faixa que não preenche o corpo da maçã; energia no cume da polilinha |
| Cortes das protecções | discos no lóbulo direito (p01/p05) | discos + recortes angulares ao longo de toda a faixa |
| `displacement` vs `influence` | replica o lóbulo | replica a faixa |
| Fold (`minDetJ`) | positivo | **negativo nas 3** |
| Estreitar medido em 123/411 | forte | fraco |
| Pronto para B | não | **não** |

A A2 troca um artefacto (carimbo) por outro (faixa mordida + dobra). Não é um progresso de qualidade geométrica no sentido pedido.

---

# Avaliação crítica

### O que melhorou?

O suporte deixou de ser um único máximo pontual. Há mais pixéis activos e a forma deixa de ser um disco. Hull e losango continuam ausentes. Isolamento técnico (Jaw/Chin/protecções a zero) mantém-se.

### O que continua a falhar?

A leitura continua artificial. As protecções passam a ser o desenho dominante do domínio. O `displacement` continua a ser uma cópia do peso. Não há volume malar. O campo **não é injectivo** (`minDetJ < 0`): mesmo como Field, A2 é pior que A1.

### O que a hipótese não resolveu (e não resolve por calibração)

O conflito é estrutural: a maçã vive **entre** órbita, nariz, sulco e orelha; as protecções desta A são discos / hulls hard-zero desses landmarks. Qualquer envelope que ocupe a maçã intersecta esses discos. A rampa a partir de `protected` não apaga o corte; só o suaviza até a amplitude × peso ainda ser grande — e aí o Jacobiano inverte.

Aumentar σ, alongar o arco ou recuar o cume não sai deste triângulo: ocupação ↔ cortes ↔ dobra.

### O que os mapas não conseguem provar

- pad anatómico;
- equivalência Meitu;
- que um arco é a família certa;
- que B “confirmará na foto” — B sobre um campo que dobra não é validação, é ruído.

---

## Isolamento

O módulo não importa renderer, controller, UI, `extended_roi`, MLS, Telea, `jaw_field.dart`, `chin_field.dart`, `face_slim_field.dart` nem `sourceRgba`. Catálogo partilhado só **lido**.

## Testes

```
flutter test test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart
```

O teste A2 **não** exige `minDetJ > 0`: o fold está no JSON e neste relatório. Exigir o gate aqui esconderia a interrupção ou deixaria o suite vermelho sem acrescentar facto.

Contratos Jaw / Chin / renderer: não alterados.  
O teste de lab B **não foi corrido**.

## Arquivos

**Desta A2**

- `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart`
- `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_masks.dart`
- `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart`
- `docs/beauty/v2-cheekbones-a2-report.md` (este relatório)
- `.cursor/facial-warp-v2/cheekbones/A2/` — métricas e mapas t=0.5

**Não alterados**

`BackwardBilinearWarp`, `DisplacementField`, `JawField`, módulo `chin/`, `face_slim/`, `RegionMasks`, `FieldMetrics`, `region_catalog.dart`, controller, preview, export, UI, Device Lab, regras V2. Mapas A1 em `cheekbones/A/` **não** foram sobrescritos. Teste de lab Cheekbones B não executado.

---

## Conclusão

A A2 implementou a hipótese do envelope de arco e **interrompeu-a**.

Melhorou a ocupação em pixéis e manteve a ausência de hull/losango. Piorou a qualidade do campo: cortes mais visíveis, `displacement` ainda replica o peso, `minDetJ < 0` nas três fotos, leitura de faixa mordida em vez de maçã.

A1 continua a ser o último Field **sem dobra**. Nenhuma das duas é pad malar convincente.

Isto **não** promove arco, gaussiana nem qualquer família a contrato.

## Sprint B

**Não iniciada.** Sem RGBA, sem `v2Raw`, sem lab. Não se inicia sem aprovação explícita.
