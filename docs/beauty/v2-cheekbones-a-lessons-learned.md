# Cheekbones — lições de A1 e A2

Síntese. Sem implementação. Sem terceira hipótese.

Fontes exclusivas:

- [`v2-cheekbones-a-report.md`](./v2-cheekbones-a-report.md) e mapas `.cursor/facial-warp-v2/cheekbones/A/`
- [`v2-cheekbones-a2-report.md`](./v2-cheekbones-a2-report.md) e mapas `.cursor/facial-warp-v2/cheekbones/A2/`

Fotos: `real-p01`, `real-p05`, `real-p12`. t=0.5. Sem `v2Raw`. Sem Sprint B.

Sprint A **encerrada por agora**. Não há A3 neste documento.

---

## 1. O que A1 demonstrou?

Hipótese medida: pad unimodal por lado; pico em 123/411; peso gaussiano anisotrópico; domínio = suporte do peso, sem hull malar.

### Comprovado

- Nos mapas A1, o domínio **não** é um hull facetado. Losango e ilha Voronoi nítida **ausentes**.
- `influence` mostra **dois lóbulos compactos**, unimodais, no mid-face.
- Esses lóbulos lêem-se como **carimbo gaussiano** (iso-contornos concêntricos, suporte pequeno face à maçã).
- `displacement` é só Δx; dy = 0 em todo o campo.
- A forma do `displacement` **replica** a forma do `influence`.
- `cheekActive` é cortado por **discos** de protecção, sobretudo à direita (p01, p05).
- Isolamento técnico: `|d|` em 58, 288 e 152 = 0; p95 das protecções = 0; `outsideCheekZoneP95` = 0.
- t=0 → campo zero. t=0.5 → `cheekbonesNarrows`. dx esquerdo > 0, direito < 0.
- `minDetJ > 0` nas três fotos (0.53–0.64). `maxNeighborJump` ≤ 0.48.
- Assimetria em p01: `|dx|` em 411 ≈ 43% de `influenceMax` (−3.25 vs 7.58).
- `influenceMax` ≈ amplitude (`t * 0.04 * faceWidth`).

### Provável

- A leitura de carimbo segue do **único máximo** por lado: os mapas coincidem com um lóbulo centrado no primário; A1 não isolou outras localizações do pico no dump final.
- O recorte direito em p01 está ligado à **proximidade 411–orelha**: o lóbulo é visivelmente mais fraco nesse lado, e 411 está junto do disco.

### Não demonstrado

- Volume malar anatómico. Pad distribuído sobre a maçã.
- Equivalência visual ao Meitu.
- Redistribuição de tecido (o `displacement` não mostra outra forma além do lóbulo).
- Que o observador lê dois volumes independentes no sentido de produto.
- Que 123/411 sejam o centro visual de um produto comercial.
- Aparência do warp na fotografia (`v2Raw` inexistente).
- Bidireccionalidade ou L/R independentes.
- Que A1 esteja pronta como produto ou como Sprint B.

---

## 2. O que A2 demonstrou?

Hipótese medida: envelope ao longo de um arco (órbita → interior da maçã → inferior); queda perpendicular ao arco; 123/411 não são o cume.

### Comprovado

- Hull facetado e losango **continuam ausentes**.
- O suporte **alongou-se**: banda / arco em vez de um lóbulo compacto.
- `cheekActive` **subiu** face à A1: p01 34144 → 54611; p05 21406 → 27264; p12 26987 → 33827.
- `influence` lê-se como **faixa / salsicha**, não como maçã. Em p05, o lado direito mostra **vários máximos** ao longo da polilinha.
- `cheekActive` é uma tira **mordida** por discos (orelha / Jaw) e por cortes angulares (nariz / faceCenter). Os cortes são **mais extensos** do que na A1.
- `displacement` continua só Δx e **replica a faixa**, incluindo as mordidelas.
- Isolamento técnico **mantém-se**: 58/288/152 = 0; p95 das protecções = 0; `outsideCheekZoneP95` = 0.
- t=0 → campo zero. t=0.5 → `cheekbonesNarrows`. dx esquerdo > 0, direito < 0.
- `minDetJ < 0` nas três fotos (−4.62 / −3.13 / −3.69). `maxNeighborJump` 4.13–5.62.
- Energia nos primários **caiu**: Δ largura malar 10.83–12.98 → 4.80–6.27; `|dx|` em 123/411 claramente abaixo da A1.
- `influenceMax` continua ≈ amplitude.
- Leitura de pad malar: **não**. A implementação foi interrompida por resultado claramente artificial.

### Provável

- Nesta construção, **ocupar mais pixéis** fez a faixa atravessar mais discos; os mapas A2 mostram mais perímetro de corte do que os A1.
- A rampa a partir de `protected` **não apagou** o corte: o `displacement` cai para zero na borda do disco com salto da ordem de 4–6 px, coincidente com `minDetJ` negativo.
- Os vários máximos em p05 são consistentes com **distância a uma polilinha** (energia no cume, não um envelope liso). A2 não isolou essa causa noutro dump.

### Não demonstrado

- Que “arco” seja, ou deixe de ser, a família certa.
- Volume malar anatómico.
- Equivalência visual ao Meitu.
- Que **qualquer** ocupação maior da maçã dobre, ou que **qualquer** arco dobre.
- Que o conflito ocupação ↔ discos ↔ fold seja insolúvel fora desta A2.
- Aparência do warp na fotografia (`v2Raw` inexistente; B recusada sobre campo que dobra).
- Que recuar o cume, outra polilinha ou outro falloff (tentativas intermédias da A2) tenham sido medidos com mapas finais comparáveis aos dumps A/A2.

---

## 3. O que ambas demonstram em comum?

Só o que os mapas e as métricas A1 **e** A2 suportam.

- **Sem hull malar, sem losango.** As duas sprints, com distribuições de peso diferentes, produzem domínio sem hull facetado e sem losango. O losango não reapareceu quando o hull foi omitido.
- **A forma do peso determina a forma do displacement.** Em A1 o `displacement` copia o lóbulo; em A2 copia a faixa. Alterar só a distribuição de `w`, com `dx = A · w`, altera o `displacement` na mesma geometria. As duas formas **não se separam** nestes mapas.
- **`influenceMax` satura a amplitude** nas duas (`≈ t * 0.04 * faceWidth`). O máximo local chega a `A`.
- **Aumentar ocupação em pixéis não produziu pad.** A2 tem mais `cheekActive` e pior leitura (faixa mordida) mais fold. Ocupação ≠ qualidade geométrica nestes dois dumps.
- **Aumentar ocupação coincidiu com mais conflito com protecções.** A1: discos no lóbulo direito. A2: discos e cortes ao longo da faixa. As protecções p95 continuam 0 **sobre** a máscara; o corte vê-se no `cheekActive` / `influence` / `displacement`.
- **Hard-zero de Jaw/Chin/olhos/nariz/boca/orelhas é atingível** sem importar outros Fields: 58/288/152 a zero; p95 das protecções a zero; dy = 0; dx para a midline; `cheekbonesNarrows` nas duas.
- **Nenhuma das duas lê a maçã.** A1 = carimbo. A2 = faixa mordida. Volume anatómico: não.
- **Gates de Field que não são pad** passam nas duas: t=0 zero; isolamento; Δx only. Isso não distingue carimbo de faixa.
- **`|dx|` em 123/411 não mede pad.** A1 concentra energia aí (carimbo). A2 tira energia daí (faixa noutro sítio) e estreita menos nesses IDs. O gate de 40% da A1 é métrica de carimbo, não de maçã.
- **Sem `v2Raw`, não há juízo sobre a pele.** As duas sprints são só Field.

---

## 4. O que continua completamente desconhecido?

Se não houver evidência nestas duas sprints: **Desconhecido**.

| Questão | Estado |
|---|---|
| Como um produto comercial distribui energia pela maçã | Desconhecido |
| Que família geométrica esse produto usa | Desconhecido |
| Como (ou se) evita cortes visíveis das máscaras | Desconhecido |
| Se separa `influence` e `displacement` | Desconhecido |
| Como um Field V2 poderia separar `influence` e `displacement` sem `dx = A · w` | Desconhecido (não testado) |
| Aparência A1 ou A2 na fotografia (`v2Raw`) | Desconhecido |
| Se o carimbo A1 se vê na pele | Desconhecido |
| Se as mordidelas A2 se vêem na pele | Desconhecido |
| Extensão anatómica da maçã nestes landmarks | Desconhecido (não medida; só leitura dos mapas) |
| Se 123/411, 187/436 ou o arco 111–147 localizam a eminência visual | Desconhecido |
| Se outro modelo de protecção (não discos/hulls hard-zero) muda o corte | Desconhecido (não testado) |
| Se outra amplitude, outro falloff ou outros IDs, **dentro** de A1 ou A2, produzem pad | Desconhecido (calibração fixa nos dumps finais) |
| Bidireccionalidade ± e L/R independentes | Desconhecido (fora do plano A; não medido) |
| Equivalência ao Meitu | Desconhecido |
| Se Sprint B sobre A1 (sem dobra) confirmaria ou rejeitaria o carimbo na foto | Desconhecido (B não iniciada) |

---

## 5. O que NÃO podemos concluir

- **A gaussiana não está descartada.** A1 mostrou *esta* gaussiana unimodal em 123/411 como carimbo. Não mostrou que toda gaussiana, outro σ, outro centro ou outra anisotropia falham.
- **O arco não está descartado.** A2 mostrou *este* envelope de polilinha, com estas protecções e este falloff, como faixa mordida com fold. Não mostrou que todo arco falha.
- **O problema não foi provado como insolúvel.** As duas hipóteses falharam de modos diferentes. Isso não prova que um pad malar seja impossível no contrato `Field → DisplacementField → BackwardBilinearWarp`.
- **O Meitu não foi identificado.** Nenhuma sprint mediu o algoritmo de um produto comercial.
- **A1 não está aprovada como pad.** É o último dump com `minDetJ > 0`. Isso não a torna volume malar nem candidata automática a B.
- **A2 não prova que “mais ocupação ⇒ fold”.** Provou fold **nesta** A2. Não generaliza a qualquer aumento de suporte.
- **Protecções hard-zero não foram provadas como erro de contrato.** Foram visíveis nos mapas. Não foram comparadas a outro modelo.
- **`dx = A · w` não foi provado como único modo possível** no contrato V2. Foi o modo das duas sprints; nelas, displacement copiou o peso. Outras construções de Field não foram medidas.
- **Continuidade melhor que o losango não é leitura anatómica.** A1 e A2 não têm losango e também não têm maçã.
- **Passar gates de isolamento não é passar produto.** As duas passaram isolamento e falharam a leitura de pad.

---

## 6. Requisitos de uma futura hipótese

Sem solução. Sem família. Só o que as falhas observadas tornam objectivo.

1. **`minDetJ > 0`** nas fotos de lab usadas em A (A2 falhou nas três).
2. **`maxNeighborJump` da ordem da A1** (≤ 0.48 nestes dumps), não da A2 (4–6).
3. **Domínio sem hull facetado, sem losango, sem Voronoi nítido** (A1 mostrou que omitir o hull remove o losango; A2 confirmou que o losango não é necessário para haver artefacto).
4. **`influence` não lido como carimbo** unimodal compacto (falha A1).
5. **`influence` não lido como faixa / salsicha mordida** (falha A2).
6. **Isolamento Jaw/Chin e resto das protecções:** `|d|` em 58, 288, 152 = 0; p95 das protecções = 0; `outsideCheekZoneP95` = 0 (atingido nas duas; não relaxar).
7. **Contrato de Field:** só Δx para a midline; dy = 0; t=0 → campo zero.
8. **Não tratar `cheekActive` maior como sucesso** (A2 subiu ocupação e piorou o campo).
9. **Não tratar `|dx|` em 123/411 como sucesso de pad** (A1 saturava o carimbo; A2 esvaziava os primários).
10. **Inspeccionar `influence` e `displacement` em par.** Nas duas sprints o segundo copiou o primeiro; uma hipótese nova só pode afirmar formas distintas se os mapas o mostrarem.
11. **Não iniciar Sprint B** enquanto o Field não cumprir (1)–(5) e a leitura dos mapas não for de pad. Campo com `minDetJ < 0` não é input de `v2Raw`.
12. **Não voltar ao hull curto + chamfer + `max(Gaussians)`** — causa do losango já isolada antes destas sprints; A1/A2 não a reabriram.

Estes requisitos não escolhem gaussiana, arco, elipse, nem outra família. Não autorizam A3.

---

Não existem evidências suficientes **neste documento A1/A2** para seleccionar a próxima hipótese experimental.

**Seguinte (2026-08-26):** hipótese H no editor — crista no oval. Relatório [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). Este ficheiro de lições **não** descreve H.
