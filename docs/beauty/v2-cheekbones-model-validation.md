# Cheekbones — validação do modelo vs geometria

**Escopo: A1 vs A2.** O código em disco **já não** é A2. Vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md) (ainda `dx = A · w`; `w` = distância à crista oval).


> As Sprints A1 e A2 realmente testaram apenas duas geometrias dentro do mesmo modelo matemático de Field?

Fontes:

- Código em disco (estado A2): `lib/features/editor/beauty_engine/warp/v2/cheekbones/cheekbones_field.dart`, `cheekbones_masks.dart`, `cheekbones_metrics.dart`; dump de mapas em `test/beauty_engine/warp/v2/facial_warp_v2_cheekbones_field_test.dart`
- Relatório A1: [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md) — o source A1 **não está no disco**; foi substituído pela A2
- Relatório A2: [`v2-cheekbones-a2-report.md`](./v2-cheekbones-a2-report.md)
- Mapas: `.cursor/facial-warp-v2/cheekbones/A/` e `.../A2/`

Sem implementação. Sem A3. Sem Sprint B. Sem decisão do próximo experimento.

---

## 1. Qual é exactamente o modelo matemático usado hoje?

O código em disco é a A2. Equação em `_applyNarrowing` (`cheekbones_field.dart`):

```
amplitude = clamp(t, 0, 1) · 0.04 · faceWidth

pad(x, y)      = min(1, w_L(x, y) + w_R(x, y))
boundary(x, y) = min(1, dist_protected(x, y) / falloff)
weight(x, y)   = pad(x, y) · boundary(x, y)

se cheekActive(x, y) = 0:   não escreve (dx e dy permanecem 0)
se |midlineX − x| < 1e-6:   não escreve
se weight ≤ 1e-6:           não escreve

dx(x, y) = sign(midlineX − x) · amplitude · weight(x, y)
dy(x, y) = 0
```

`falloff = max(10, 0.18 · faceWidth)` no código actual.

`dist_protected` é a distância (transformada 4-conectada, +1 por pixel) à máscara `protected`. Sobre `protected`, a distância é 0.

`cheekActive = (cheek ≠ 0) ∧ (protected = 0)`.  
`cheek` liga onde `w_L + w_R > 1e-3` (peso do pad, antes da rampa).

### Peças

| Peça | O que é no código / métricas |
|---|---|
| **weight** | `pad · boundary`. Escala a magnitude. Não define a direcção. |
| **amplitude** | Escalar global. Não é um campo. `t = 0` ⇒ amplitude 0 ⇒ `DisplacementField` zero. |
| **sign** | `sign(midlineX − x)`. A midline é a média em x do oval. Independente de `w_L` / `w_R`. |
| **dx** | `sign · amplitude · weight`. Única componente escrita. |
| **dy** | Literalmente 0 em todo o pixel escrito. |
| **protected** | OR de eyes, brows, nose, mouth, faceCenter, ears, jawDomain, chinDomain. Hard-zero: esses pixéis não entram em `cheekActive`; `dx` fica 0. |
| **influence** | **Não é um campo separado.** Métrica `influenceMax` = `max √(dx²+dy²)` em `cheekbones_metrics.dart`. O PNG `influence.png` do teste A é `√(dx²+dy²) / maxMag` em cinzento. Com `dy = 0`, influence = `|dx|` normalizado. |

### Geometria vs modelo

**Modelo** (equação que consome o escalar e escreve o `DisplacementField`):

```
dx = sign(midlineX − x) · A · pad · boundary
dy = 0
```

um único `DisplacementField` por `build`. Sem segundo Field. Sem `BackwardBilinearWarp` neste módulo.

**Geometria** (como se obtém o escalar `pad` / `w_L` / `w_R`):

hoje, `CheekbonesMalarPad.weight`: distância a uma polilinha, gaussiana radial `exp(−½ r²)`, `r = dist / half`, `half` medial ou lateral, taper nas pontas do arco. Isso **não** é a equação de `dx`. É a definição de `w_L` e `w_R`.

A1 (só o relatório; código ausente): `pad` era gaussiana anisotrópica centrada em 123/411, `exp(−½ ((u/σu)² + (v/σv)²))`. A equação de `dx` descrita no relatório A1 é a mesma família: rampa a partir de `protected`; só Δx para a midline; `dy = 0`; `A = t · 0.04 · faceWidth`.

---

## 2. O que mudou entre A1 e A2?

A1: relatório A + mapas `cheekbones/A/`.  
A2: código em disco + relatório A2 + mapas `cheekbones/A2/`.

| componente | A1 | A2 | |
|---|---|---|---|
| `CheekbonesField.build → DisplacementField` | sim | sim | idêntico |
| `dx = sign · A · weight`, `dy = 0` | sim (relatório) | sim (código) | idêntico na equação |
| `A = t · 0.04 · faceWidth` | sim | sim | idêntico |
| dois pads L/R, um campo | sim | `min(1, w_L+w_R)` | idêntico na arquitectura |
| `protected` hard-zero + rampa | sim | sim | idêntico na arquitectura |
| constante da rampa | `0.08 × faceWidth` (relatório) | `0.18 × faceWidth` (código) | **mudou** |
| definição de `pad` / `w` | gaussiana unimodal em 123/411; σ ≈ `0.07 × faceWidth`; eixos lateral e inferior | distância a arco 111/340 → interior → 147/425; `exp(−½ r²)` perpendicular; taper nas pontas | **mudou** |
| papel de 123/411 | pico do pad | âncora de métrica e de `lerp` do interior; não são o cume | **mudou** |
| IDs extra do pad | 116/345, 187/436, órbita 145/374 | 111/340, 187/436, 147/425 | **mudou** |
| influence = `\|d\|` do mesmo Field | sim (mapas + métrica) | sim (teste + métrica) | idêntico |
| `influenceMax ≈ A` | 7.58 / 5.74 / 6.51 | 7.58 / 5.75 / 6.51 | idêntico nas três fotos |
| `BackwardBilinearWarp` / `v2Raw` | não | não | idêntico |
| Jaw / Chin / renderer | não alterados | não alterados | idêntico |

**O que mudou:** a função espacial `pad(x,y)` (e, com ela, `cheek` / `cheekActive`); a constante da rampa `0.08 → 0.18`; os IDs que localizam o pad.

**O que permaneceu idêntico:** a equação `dx = sign · A · weight`, `dy = 0`; amplitude `0.04`; um Field; influence como magnitude de `d`; ausência de renderer.

O código A1 não está no repositório. A igualdade literal de `_applyNarrowing` entre A1 e A2 **não** é verificável por diff. A identidade da equação apoia-se no relatório A1 + no código A2.

---

## 3. Quais propriedades pertencem claramente ao modelo?

Só o que as **duas** sprints observaram, com a equação acima.

- `dy = 0` em todo o campo.
- `dx` tem o sinal de `midlineX − x` nos dois lados.
- O mapa `displacement` tem a **mesma silhueta** que o mapa `influence` (A1: lóbulo; A2: faixa). Com `influence = |dx|` e `dx ∝ weight`, isso é a equação, não uma leitura extra.
- `influenceMax ≈ amplitude` nas três fotos, nas duas sprints. O máximo de `|dx|` satura `A`.
- t=0 → campo zero.
- Pixéis `protected`: `|d|` p95 = 0; 58 / 288 / 152 a zero.
- Um único `DisplacementField`. Não há um campo de influence independente no código.

Estas propriedades não trocaram de valor quando `pad` trocou de forma.

---

## 4. Quais propriedades pertencem claramente à geometria?

Só diferenças **observadas** entre os dumps A e A2.

| Propriedade | A1 | A2 |
|---|---|---|
| Forma do `influence` | dois lóbulos compactos unimodais (carimbo) | faixa / salsicha ao longo do arco |
| `cheekActive` (pixéis) | 34144 / 21406 / 26987 | 54611 / 27264 / 33827 |
| Cortes de `protected` no domínio activo | discos no lóbulo direito (p01, p05) | discos e cortes ao longo da faixa |
| `minDetJ` | 0.53 – 0.64 | −4.62 / −3.13 / −3.69 |
| `maxNeighborJump` | ≤ 0.48 | 4.13 – 5.62 |
| `\|dx\|` em 123 / 411 | satura ou quase satura `A` (411/p01: −3.25 vs 7.58) | cai (ex. p01: +3.65 / −1.14) |
| Δ largura malar em 123–411 | 10.83 / 11.47 / 12.98 | 4.80 / 6.04 / 6.27 |
| Vários máximos no lado direito (p05) | não reportado | presente (polilinha) |

Carimbo vs faixa, ocupação, fold e energia nos primários **mudaram** com a definição de `pad`. O modelo `dx = sign · A · weight` estava em vigor nos dois dumps.

---

## 5. O que continua impossível separar?

A1 e A2 não cruzam os dois eixos.

- Eixo que **variou:** `pad(x,y)` (geometria), mais a constante da rampa.
- Eixo que **não variou:** `dx = sign · A · pad · boundary`.

Sintomas que **mudaram** (carimbo vs faixa, `minDetJ`, ocupação) não podem ser atribuídos ao modelo: o modelo era o mesmo.

Sintomas que **não mudaram** (cópia influence/displacement, `influenceMax ≈ A`, ausência de leitura de pad malar) têm duas leituras compatíveis com os dumps:

1. consequência da equação `dx ∝ weight` (modelo);
2. consequência de as duas geometrias ainda não serem um pad, ambas consumidas pela mesma equação.

Não existe dump em que `pad` seja fixo e a equação de `dx` mude. Não existe dump em que a equação seja outra e a geometria seja a de A1 ou A2. Sem essa cruz, geometria e modelo **não** se isolam na falha “não é pad malar”.

A rampa `0.08 → 0.18` impede ainda o enunciado estrito “só mudou a geometria”: um parâmetro do termo `boundary` também mudou.

---

## 6. Existe alguma evidência de que o modelo esteja errado?

**Ainda não é possível concluir.**

Justificação:

- O modelo não foi a variável independente. A1 e A2 não o substituíram por outra equação de `dx`.
- Propriedades que o modelo **implica** (`dx ∝ weight` ⇒ influence e displacement com a mesma forma; `max|dx| = A` quando `weight` atinge 1) **ocorreram**. Isso confirma que o código fez o que a equação diz. Não avalia se a equação é inadequada para o produto.
- Propriedades que **falharam** de modo diferente (carimbo vs faixa; fold só na A2) ocorreram com o **mesmo** modelo. Não são prova de erro do modelo.
- A ausência de pad malar nas duas é um resultado conjunto. Não há contraste que a impute só ao modelo.
- Relatórios A1 e A2 e o código A2 **não** contém um experimento que refute `dx = sign · A · weight`.

Não há evidência, nestas fontes, de que o modelo esteja correcto como produto. Não há evidência de que esteja errado. O estado é o mesmo: **não isolado**.

---

## 7. Gate

A hipótese de que A1 e A2 testaram apenas geometrias diferentes está:

[ ] comprovada

[x] parcialmente sustentada

[ ] não sustentada

**Justificação**

Sustentada: as duas sprints usam a mesma equação de Field (`dx = sign · A · weight`, `dy = 0`, um `DisplacementField`, influence = `|d|`). O que os mapas mostram como forma (lóbulo vs faixa) segue a definição de `pad`. Isso é duas geometrias **dentro do mesmo modelo**.

Não comprovada como “**apenas** geometrias”:

1. a constante da rampa mudou (`0.08` → `0.18` × faceWidth);
2. o source A1 não está no disco; a identidade da equação com A2 vem do relatório A1, não de um diff.

Não sustentada ficaria se A2 tivesse outra equação de `dx`. O código actual não tem: `field.dx[i] = toward.sign * amplitude * weight`.

Este documento não escolhe o próximo experimento. Valida só o que A1 e A2 realmente contrastaram.
