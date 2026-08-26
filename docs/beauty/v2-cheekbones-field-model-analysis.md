# Cheekbones — análise do modelo do Field

Documento de decisão. Sem código. Sem experimento. Sem A3. Sem Sprint B.

Pergunta: as limitações de A1 e A2 pertencem à **geometria do peso** ou ao **modelo** que transforma esse peso em `DisplacementField`?

Fontes: [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md), [`v2-cheekbones-a2-report.md`](./v2-cheekbones-a2-report.md), [`v2-cheekbones-a-lessons-learned.md`](./v2-cheekbones-a-lessons-learned.md). Mapas A e A2.

Sprint A **encerrada**. Este texto não escolhe a próxima geometria nem a próxima arquitectura.

---

## 1. O que A1 e A2 têm em comum matematicamente?

Não é a forma do suporte. É a arquitectura do Field, idêntica nas duas sprints.

```
Field.build(face, imageSize, t)
        ↓
   weight(x, y) ∈ [0, 1]
        ↓
   dx = amplitude × weight
   dy = 0
        ↓
   DisplacementField
```

### Factos comprovados

- **Um** `DisplacementField` por `build`. Não há segundo campo, nem composição de Fields V2.
- O valor espacial que varia é um **escalar** `weight(x, y)`. A diferença A1/A2 está só em *como* esse escalar é calculado, não na equação que o consome.
- `amplitude` é um **escalar global**: `t * 0.04 * faceWidth`. Não é um campo. t=0 ⇒ amplitude 0 ⇒ campo zero nas duas.
- A equação de deslocamento, nas duas, é

  `dx(x, y) = sign(midlineX − x) · amplitude · weight(x, y)`  
  `dy(x, y) = 0`

  A direcção não sai do peso; sai do sinal à midline. O peso só **modula a magnitude**.
- `weight` efectivo inclui um factor de **rampa a partir de `protected`**. Sobre pixéis protegidos o campo não escreve: `dx = 0` (hard-zero).
- O mapa `influence` destas sprints visualiza a magnitude desse `dx`. Por construção, `|dx| = amplitude · weight` onde o campo é escrito.
- Métrica comum: `influenceMax ≈ amplitude` nas três fotos, em A1 e em A2. O máximo de `|dx|` satura `A` quando `weight` atinge 1.
- Contrato V2 a jusante (`DisplacementField` → `BackwardBilinearWarp`) **não foi exercido**. As duas sprints param no Field.

Não se afirma que este modelo seja o único permitido pela V2. Afirma-se só que **foi o único usado em A1 e A2**.

---

## 2. Quais comportamentos observados parecem consequência desse modelo?

Só A1 e A2. Só o que sobreviveu à mudança de geometria, ou o que a comparação A1→A2 mostra sobre a equação `dx = A · w`.

| Observação | Onde | Ligação ao modelo (sem extrapolar) |
|---|---|---|
| O `displacement` **replica** o `influence` | A1 (lóbulo) e A2 (faixa) | `|dx| = A · w`. A forma pintada no `influence` é a forma de `w`. O `displacement` é essa forma com sinal. |
| Mudar a geometria do peso muda o `displacement` na **mesma** geometria | A1 vs A2 | A equação não acrescenta outra função. Trocar `w` troca `dx`. |
| A energia (magnitude) está onde o peso é máximo | A1 e A2: `influenceMax ≈ A` | `\|dx\|` é monótona em `w`. O máximo de `w` é o máximo de `\|dx\|`. |
| Não há `displacement` com forma distinta do peso | A1 e A2 | Não foi introduzida nenhuma função `dx = f(w)` diferente da proporcionalidade. Os mapas não mostram outra forma. |
| Cortes hard-zero aparecem **nos dois** mapas | A1 e A2 | Onde `protected` impede escrita, `w` efectivo e `dx` são ambos zero. O corte é o mesmo suporte. |
| dy = 0 em todo o campo | A1 e A2 | Imposto pela equação, não pela geometria do peso. |
| `cheekbonesNarrows` e dx com sinal à midline | A1 e A2 | O sinal é `sign(midline − x)`, independente da forma de `w`. |

O que **não** se atribui ao modelo só porque apareceu numa sprint:

- leitura de **carimbo** — A1, não A2;
- leitura de **faixa mordida** — A2, não A1;
- `minDetJ < 0` e `maxNeighborJump` ≈ 4–6 — A2, não A1.

Esses três mudaram quando mudou a geometria, com o **mesmo** modelo. Não são evidência de que o modelo, por si, produza carimbo, faixa ou dobra.

---

## 3. O que NÃO foi testado?

Se não foi implementado em A1 nem A2: **Não testado**. Sem proposta de implementação.

| Item | Estado |
|---|---|
| `influence` com forma distinta do `displacement` | Não testado |
| `dx` derivado de outra função que não `A · weight` | Não testado |
| Magnitude de `dx` independente do máximo de `w` (ex.: `influenceMax` ≠ amplitude) | Não testado |
| Composição de **múltiplos** `DisplacementField` independentes | Não testado |
| Dois pesos que não se somam num único `dx = A · min(1, wL+wR)` | Não testado |
| `dy ≠ 0` neste módulo | Não testado |
| Campo sem hard-zero em `protected` | Não testado |
| Outro modelo de protecção (não discos/hulls a zero) | Não testado |
| Amplitude espacialmente variável, distinta de `w` | Não testado |
| Outras arquitecturas de Field **compatíveis com V2** (`Field → DisplacementField → BackwardBilinearWarp`, sem MLS) | Não testado |
| O mesmo modelo com geometrias além das duas dumps finais | Não testado (calibração fixa por sprint) |
| Qualquer `v2Raw` / Sprint B | Não testado |

O contrato V2 **permite** um `DisplacementField` gerado de outra forma, desde que o renderer continue `src = dest − displacement`. A1 e A2 **não** exploraram essa liberdade. Também não a proíbem.

---

## 4. O que as evidências permitem afirmar?

### Comprovado

- A1 e A2 partilham a equação `dx = A · w`, `dy = 0`.
- Sob essa equação, o `displacement` copiou o `influence` nas duas geometrias.
- Trocar só `w` (A1 → A2) trocou a forma copiada (lóbulo → faixa) e trocou fold / ocupação / cortes.
- Limitações **comuns** às duas: não há pad malar; `influence` e `displacement` não se separam; `influenceMax ≈ A`.
- Limitações **que mudaram** com a geometria: carimbo vs faixa; `minDetJ` positivo vs negativo; ocupação e perímetro de corte.
- Nenhuma das duas sprints mediu outro modelo de Field.

### Provável

- A **cópia** `displacement ← influence` deve-se à proporcionalidade `dx = A · w`, não à gaussiana nem ao arco: sobreviveu à única mudança que as sprints fizeram (a forma de `w`).
- Parte da leitura “artificial” de A1 e de A2 é a forma de `w` (carimbo, faixa). Isso é geométrico. A cópia dessa forma para o `displacement` é o modelo. Os mapas não isolam o peso de cada parte na falha de “pad malar”.

### Desconhecido

- Se um Field V2 com **outra** equação de `dx` produziria `influence` ≠ `displacement`.
- Se essa diferença, existindo, seria lida como pad malar.
- Se a falha de pad é sobretudo geometria, sobretudo modelo, ou os dois.
- Se o modelo `dx = A · w` é suficiente para o comportamento visado na análise de produto.
- Como um produto comercial constrói o campo.
- Qualquer juízo sobre a fotografia (`v2Raw`).

---

## 5. O que as evidências NÃO permitem afirmar

- Que **o modelo está errado**.
- Que **esta arquitectura nunca funcionará**.
- Que `dx = A · w` seja incompatível com um pad malar.
- Que `dx = A · w` seja o único Field possível na V2.
- Que a próxima investigação **tenha** de abandonar o modelo.
- Que a próxima investigação **tenha** de ficar só noutra geometria.
- Que A1 ou A2 tenham testado o modelo: testaram **duas geometrias dentro do mesmo modelo**.
- Que fold, carimbo ou faixa sejam propriedades necessárias de `dx = A · w` (A1 e A2 contradizem uma atribuição única: o modelo foi constante e esses sintomas não).
- Que o contrato `Field → DisplacementField → BackwardBilinearWarp` tenha sido invalidado (o renderer não entrou).

---

## 6. Conclusão

As evidências atuais indicam que as limitações observadas podem estar relacionadas tanto à geometria escolhida quanto ao modelo matemático do Field. As Sprints A1 e A2 não permitem distinguir essas duas causas.

Sustentação: as duas sprints mudaram a geometria de `w` e mantiveram `dx = A · w`. Sintomas que **mudaram** (carimbo vs faixa, fold) apontam para geometria. Sintomas que **não mudaram** (cópia influence/displacement, máximo em `A`, ausência de pad) são compatíveis com o modelo e também com “ainda não foi a geometria certa”. Sem um terceiro experimento que mude o modelo **ou** que esgote geometrias, as duas causas ficam confundidas.

Este documento não inicia A3 nem Sprint B. Não implementa nada. Serve só para a decisão: continuar a procurar outra geometria, ou questionar primeiro o modelo do Field.

---

## 7. Nota H (2026-08-26)

H **não** mudou a equação `dx = A · w`, `dy = 0`. Mudou **como** se calcula `w`: distância a uma polilinha no oval, em vez de `max` de gaussianas. Continua um `DisplacementField`. Relatório: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).

