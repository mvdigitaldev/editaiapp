# Análise de produto — Cheekbones V2

**Estado:** encerrado como instrumento de decisão. Não escolhe família de implementação.

**Adenda 2026-08-26 (editor, hipótese H).** Confirmado no produto, sem reabrir pesquisa:

- Slider **bidireccional** e flag **Geral / Esquerda / Direita** (lados da foto).
- O Meitu **puxa um pedaço do ângulo mandibular** neste slider; hard-zero no gônio no nosso Field lia-se como trava / S.
- 323 e 454 estão no **oval** (junta orelha–bochecha). Travar a orelha aí deixa um pico parado no contorno.
- Field vigente: [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md).

O texto abaixo é a pesquisa original (2026-08-25). Não o apagar.


Níveis: **Observado** · **Evidência indireta** · **Hipótese** · **Desconhecido**.  
Graus: **Muito forte** · **Forte** · **Moderada** · **Fraca** · **Especulativa**.

O algoritmo interno do Meitu permanece **Desconhecido**. Engenharia reversa não exige essa certeza. Exige convergência suficiente para decidir se uma Sprint A **experimental** está justificada.

---

# Parte 1 — Comportamento observado (Meitu)

Só o slider Cheekbones no produto. Sem o nosso Field. Sem hipóteses de implementação.

Fontes: ícones do painel; capturas do warp (Cheekbones seleccionado, categoria Rosto). Inclui a foto lab **p01** (mesma cara da Sprint B). Bloqueio de fundo desligado. Estimativas visuais não são números de contrato.

**UI (Observado, Forte).** Slider **bidireccional** (zero no centro; esquerda = negativo; direita = positivo). Âmbito: **Geral** (ambos), **Esquerda**, **Direita**. Temple / Lift / Width / Chin / Jawline são controlos à parte.

**Sequência p01 (Observado, Forte).** Neutro (Geral, slider ao centro) → positivo Geral (maçãs mais largas / mais volume) → negativo Geral (maçãs entram) → negativo só Esquerda (um lado entra; o outro fica perto do baseline). Mandíbula e mento não parecem o alvo.

| Item | Observado | Inferido (estimativa visual) | Desconhecido |
|---|---|---|---|
| Onde começa | Mid-face, bochecha superior (ícone + warp p01). | Abaixo do olho, na eminência, não na têmpora. | Pixel exacto. |
| Onde termina | Acima da mandíbula; não chega ao mento (ícone + p01). | Terço médio, acima de Width/Lift. | Pixel exacto. |
| Centro visual | Terço médio; perímetro lateral. No warp: a “maçã”. | Eminência, não o gônio. | Mapa de energia interno. |
| Largura | Bandas laterais; não atravessa o nariz. | Metade lateral do mid-face, não até ao sulco. | Fracção da faceWidth. |
| Altura | Abaixo de Temple, acima de Width/Lift. | Terço médio da cara. | Fracção da faceHeight. |
| Direcção | **Bidireccional.** Negativo: para dentro. Positivo: para fora / mais volume. Ícone só mostra o sentido “estreitar”. Lift é outro slider. | O + e o − actuam no **mesmo sítio**, sentidos opostos. | Componente vertical exacta. |
| Lados | Geral = dois lados. Esquerda/Direita = um lado (p01 1111). | Dois volumes independentes. | Se há bleed no lado “off”. |
| Gradiente | Zona curva no ícone; no warp p01 a transição **não** é um degrau nem um triângulo. | Queda suave ao longo da banda. | Radial vs anisotrópico no renderer. |
| Sulco nasolabial | Ícone no perímetro externo. No p01 o sulco não parece o motor do efeito. | Invasão nula ou residual. | Fuga em pixéis. |
| Infraorbital | Começa abaixo dos olhos. | Proximidade da órbita sem a ocupar. | Fuga sob a pálpebra. |
| Mandíbula | Controlos Jaw/Width/Lift à parte. No p01 o mento/gônio não leem como alvo. | Não é Jaw. | Fuga residual. |
| Têmpora | Temple é mais alto. | Isolamento vertical. | Fuga residual. |
| Silhueta | Traço no oval **lateral** do mid-face. | Mexe o bordo da maçã, não o arco mandibular. | Quanto o contorno se move. |
| Volume | **−** reduz o pad; **+** aumenta / alarga. Não parece um selo achatado. | Preserva leitura de volume (maçã menor ou maior). | Modelo interno do pad. |
| Continuidade | Warp p01: banda orgânica, simétrica em Geral. | Não é um polígono de 3 pontos. | Continuidade sub-pixel. |

Confiança: ícone **Forte**; warp p01 (região, ±, L/R, continuidade vs patch) **Forte**. Sem captura equivalente ainda em p05/p12.

### Anatomia funcional (interpretação do fenómeno)

Não justifica implementação. Lê o que o ícone **parece** acompanhar.

O efeito aparenta seguir a **eminência zigomática** e o volume da maçã (malar fat pad / tecido mole do mid-face), não o masseter, não o bordo mandibular, não a têmpora. No p01, + e − parecem o mesmo pad a encher ou esvaziar. Não parece slim de silhueta completa (V shape / 瘦脸). Confiança: **Moderada**. Não prova gordura vs músculo no shader.

### Evidência indireta de produto (sem o nosso código)

APIs independentes (Banuba, Alibaba, BytePlus, Tencent): cheekbone é **controlo separado** de jaw e de slim global. Confiança: **Muito forte**.  
Refs públicas de warp: várias famílias **produzem um resultado visual** que o observador lê como contínuo (não um polígono de 3 pontos). **Não** “o Meitu usa” disco, elipse, MLS, TPS ou mesh. Confiança dessa *classe de percepção*: **Forte**. Confiança de um solver: nenhuma.

---

# Parte 2 — Caracterização do comportamento do Field atual

Só o comportamento actual. Sem Meitu.

**Observado.** Confiança: **Forte**. Código + dumps da Sprint B.

Domínio = convex hull de 3–4 landmarks → arestas rectas (triângulo / losango). Dilatar `0.04 × faceWidth` não curva. Chamfer linear **imprime** essas arestas. `max(Gaussians)` cria ilhas. Amplitude escala o mesmo `weight`.

Resultado visível: patch rígido, quinas, facetas. Dois lados, Δx, Jaw/Chin a zero, protecções, t=0 — isolamento de região passou; a forma da energia dentro da região é um selo.

---

# Parte 3 — Comparação

| | Meitu (Parte 1, incl. p01) | Field actual (Parte 2) |
|---|---|---|
| Sítio | Terço médio lateral | Também mid-face (isolamento técnico ok) |
| Direcção | Bidireccional (+ volume / − estreitar) | Só Δx para a midline (um sentido) |
| Lados | Geral ou um lado | Sempre os dois |
| Forma percebida | O observador lê uma banda / volume contínuo | Polígono / patch |
| Continuidade | No p01 o resultado visual aparenta continuidade | Facetas, Voronoi de handles |
| Mandíbula / têmpora | Controlos à parte; p01 não os aponta | Zero técnico no Field |
| Volume | Pad menor ou maior | Carimbo |

Diferença decisória: a **região** está alinhada; a **distribuição** e o **eixo ±** não. O patch não se explica por falta de amplitude. Na mesma foto p01, o Meitu no extremo negativo não reproduz o losango da Sprint B.

---

## Arquitectura V2

`Field → DisplacementField → BackwardBilinearWarp`. Jaw, Chin e renderer intocados.

**Incompatível (não implementar nesta arquitectura):** MLS / TPS / ARAP completos, mesh solvers, deformação neural, parsing como renderer, multi-pass de pipeline.

**Compatível em princípio:** qualquer Field que só emita `dx`/`dy`, com um resultado visual que o observador não leia como hull de 3–4 pontos.

Estas famílias são exemplos de soluções compatíveis com a arquitectura V2.

Elas **não** representam prioridade, recomendação ou aproximação conhecida do algoritmo do Meitu.

As evidências actuais **permitem múltiplas famílias V2-compatíveis**. Nenhuma possui evidência suficiente para ser priorizada. Permanecem possibilidades, não candidatas: envelope local no Field; campo contínuo no Field; vários centros malar no Field; pesos por distância no Field sem solver.

---

## Encerramento

**O que sabemos (alta confiança):** o Field actual produz um patch poligonal; o Meitu Cheekbones é mid-face distinto de Jaw/Temple, **bidireccional**, com L/R opcionais; no p01 o observador percebe um volume contínuo, não um losango; SDKs separam o mesmo controlo; solvers no renderer estão fora da V2.

**O que apenas inferimos:** terço médio, pouco sulco/órbita/mandíbula; pad / eminência; + e − no mesmo sítio.

**O que permanece desconhecido:** algoritmo Meitu; mapa de deslocamento pixel a pixel; família de solver; números exactos de raio.

**O que é incompatível com a V2:** ver tabela acima.

### Gate — Sprint A experimental

Pergunta única: **já existe evidência suficiente para justificar uma Sprint A experimental?**

Não: “sabemos como o Meitu funciona?” Essa resposta não é exigida.

A Sprint A experimental está justificada quando houver **convergência** entre:

- observação visual do produto (ícone e estimativas da Parte 1);
- literatura / refs públicas em que o observador lê continuidade (não um polígono de 3 pontos);
- implementações/APIs que isolam a região malar;
- anatomia funcional (pad / eminência);
- compatibilidade V2 (Field only, sem renderer novo);
- explicação do patch da Parte 2 (hull + chamfer + `max`).

Não se exige medir o warp interno do Meitu.

- [x] Comportamento visual caracterizado o suficiente para orientar um Field (região, direcção, o que não invadir)
- [x] Convergência observação + APIs + refs de continuidade + anatomia do pad
- [x] Compatível com V2 sem alterar o renderer
- [x] O patch actual está explicado
- [ ] Família de implementação escolhida — **não é requisito**; nenhuma está priorizada

**Conclusão A.** Existe evidência convergente suficiente para justificar uma Sprint A experimental cujo objectivo é reproduzir o **comportamento visual observado** (o observador percebe um volume malar contínuo, isolado de Jaw/Temple; no Meitu também ± e L/R). A implementação real do Meitu permanece desconhecida. Nenhuma família está priorizada.

A Sprint A experimental existe para validar uma hipótese de comportamento visual, não uma hipótese de implementação.

Este documento encerra a etapa de pesquisa. Revisões futuras só devem ocorrer caso apareçam novas evidências externas relevantes.

A próxima etapa é decidir se essa Sprint A experimental se inicia.

---

## Fontes

- Internas: [`v2-product-audit.md`](./v2-product-audit.md), [`v2-cheekbones-spec.md`](./v2-cheekbones-spec.md), [`v2-cheekbones-b-report.md`](./v2-cheekbones-b-report.md). Capturas Meitu Cheekbones (p01 e uma segunda cara), 2026-08-25.
- Gustafsson 1993; Schaefer MLS 2006; arXiv:1910.13671; Liao/Shum 2021; Liang et al. 2015; US 11,238,569
- GPUPixel; Banuba FaceMorph; Alibaba Queen; BytePlus; Tencent Effect; MediaPipe Face Landmarker
- Anatomia: malar fat pad (literatura médica)

Nenhuma destas fontes é o código interno do Meitu.
