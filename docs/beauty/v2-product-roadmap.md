# Roadmap de produto — Jawline, Chin Length e o que vem a seguir

Complemento a [`v2-product-audit.md`](./v2-product-audit.md). Só produto: o que o utilizador vê e o que o Field faz.

**Adenda 2026-08-26.** Cheekbones (hipótese H) está em inspecção no editor. Relatório [`v2-cheekbones-h-report.md`](./v2-cheekbones-h-report.md). O “próximo trabalho é Cheekbones” da secção 5 **cumpriu-se ao nível de Field/UI**; falta C formal.

Leonardo quer, a seguir, alinhar o **Chin** ao Meitu (sangria residual no maxilar — já notada na secção 2). Chin permanece encerrado até aprovação explícita para reabrir. Não misturar com o Field Cheekbones.

Pergunta a fechar: **o `JawField` actual já é o slider Jawline do Meitu?**

Fontes:

- Meitu: ícones com área de influência (Jawline, Width, Jaw angle, Chin length, V chin, Cheekbones, Temple, Hairline, Lift, Double chin).
- Nosso Jaw: relatório V2.1 — energia na silhueta, métrica 58–288, só Δx, t=0.5 Δ gonion ≈ 8–10 px nas fotos lab.
- Nosso Chin: relatório A — só Δy no 152, gônios a zero, t=0.5 Δy ≈ 2.8–3.7 px.

---

## 1. Jaw × Jawline

### O que o Meitu mostra

O ícone **Jawline** é um perfil com tracejado no contorno da mandíbula **até ao pescoço**.

No mesmo ecrã o Meitu **separa** outros sliders no mesmo andar da cara:

| Slider Meitu | O ícone marca |
|---|---|
| Jawline | Contorno mandíbula + pescoço |
| Width | Largura da **base** da cara (gônios) |
| Jaw angle | **Canto** da mandíbula, sob a orelha |
| Lift | Os mesmos cantos, para **fora** |

Jawline no Meitu não é o único controlo do maxilar. Width e Jaw angle atacam o mesmo sítio ósseo com desenhos diferentes.

### O que o nosso Jaw faz

- Slider vivo `jaw` (Mandíbula).
- Campo **só horizontal**, para a midline (`dx`, `dy = 0`).
- Energia nos handles da silhueta, sobretudo **gônios 58 e 288**.
- Gate de produto: a largura 58–288 diminui.
- Não mexe mento (152), olhos, boca, nariz, orelhas.
- Não mexe pescoço (não há domínio cervical no Field).

Isto é, no ecrã: **a mandíbula estreita nos cantos**. É o que o olho lê como “afinar o maxilar”.

### Já equivalente

- A **função principal** que o utilizador espera de um Jawline / Width comercial: os cantos da mandíbula entram.
- O sítio certo: silhueta, não o miolo da bochecha.
- Isolado do queixo: o Chin não pode roubar este movimento (e o Jaw não encurta o mento).

O `JawField` **já cobre o papel de “estreitar mandíbula nos gônios”**. Isso é a intersecção de Jawline + Width + Jaw angle no Meitu, não o menu inteiro.

### Ainda falta (em relação ao ícone Jawline)

- **Pescoço.** O Jawline Meitu desenha o tracejado a descer do maxilar. O nosso Jaw pára no hull facial.
- **O Meitu tem três sliders** nesse andar (Jawline, Width, Jaw angle) e nós temos **um**. Não falta “mais algoritmo no mesmo gônio” para parecer Jawline; falta aceitar que Width e Jaw angle, se existirem um dia, são *outros* controlos, não um Jaw maior.
- **Componente ao longo da curva** (subir/descer pele na linha da mandíbula). O nosso campo é só Δx. O ícone Jawline é um contorno, não duas setas horizontais (essas são Width / Jaw angle).
- **Lift** é o sentido oposto (para fora). O Jaw actual não faz isso.

### O que nunca deve ser alterado no Jaw

- **Não absorver Cheekbones, Temple ou Hairline.** São ícones noutro sítio da cara.
- **Não transformar o Jaw num Face Slim.** Face Slim foi o mid-face + silhueta **sem** gônio. Jawline/Width/Jaw angle **existem para mexer no gônio**.
- **Não pôr hard-zero nos 58/288** para “suavizar quina”. Isso apaga o slider.
- **Não passar a encurtar o mento (Δy no 152).** Isso é Chin Length.
- **Não mexer no renderer nem no contrato t=0 / protecções** de olhos, boca, nariz, orelhas.

### Resposta directa

**Não.** O `JawField` não é o Jawline completo do Meitu (falta pescoço e o Meitu parte o maxilar em vários sliders).

**Sim**, como o slider de **estreitar a mandíbula nos gônios**. Para o produto actual, isso é suficiente para não reabrir o Jaw como se fosse um problema por resolver.

---

## 2. Chin × Chin Length

### O que o Meitu mostra

**Chin Length:** traços horizontais na **base do mento**. O desenho é deslocamento **vertical** da ponta, não setas para dentro nas maçãs.

No mesmo ecrã existem **V chin** (ponta mais aguda) e **Double chin** (submento / pescoço de perfil). São outros ícones.

### O que o nosso Chin faz

- Slider vivo `chin` (Queixo).
- Campo **só vertical**: o 152 sobe (`dy` negativo). `dx = 0` em todo o campo.
- Gônios 58/288 ficam a zero neste Field.
- Preview e export já o aplicam a seguir ao Jaw.

### Já equivalente?

**Sim, na função principal do Chin Length:** o queixo fica mais curto no eixo vertical.

Não é V Chin (forma da ponta). Não é Double Chin (papada/pescoço).

### Falta alguma coisa?

- **Alongar.** O Field actual só encurta. O nome Meitu é *length*; se o slider comercial for bipolar (mais curto / mais comprido), o nosso só cobre um lado. Isso não está nos ícones; só no nome.
- **Sangria para a mandíbula.** No Meitu, mexer o queixo pode puxar um pouco o maxilar. O nosso Chin **proíbe** os gônios. Visualmente o mento sobe e a linha 58–288 fica parada. É mais “limpo” e menos “Jawline no mesmo gesto”.
- **Pescoço / papada.** Fora deste slider.

Nada disto justifica reescrever o Chin antes de existir Cheekbones. O Chin Length do produto está entregue.

---

## 3. Prioridade dos próximos sliders

Ordem para **parecer Meitu no menu e no ecrã**, dado que Jaw (gônio) e Chin (length) já existem.

| # | Slider | Porquê esta posição |
|---|---|---|
| 1 | **Cheekbones** | Único buraco grande **acima** da mandíbula. O Meitu isola as maçãs com setas no mid-face. Jaw e Chin **não** tocam aí. Sem isto, o Rosto continua a ser só maxilar+mento. |
| 2 | **Temple** | Ícone distinto, terço superior. Nenhum Field vivo chega lá. Independente. |
| 3 | **Hairline** | Ícone no topo da testa. Distinto de Temple. `forehead` no código é só um nome morto. |
| 4 | **Width** | No Meitu é a base da cara. O Jaw **já faz** esse movimento. Prioridade baixa: ou é o mesmo slider com outro nome, ou um segundo controlo no **mesmo** sítio (só depois de Jawline/Jaw estarem aceites como estão). |
| 5 | **Jaw Angle** | Idem: o Jaw já vive no canto. Separar só se o produto quiser dois knobs no gônio. |
| 6 | **V Chin** | O Chin Length já mexe o 152. V Chin é *forma* da ponta, não length. Vem depois do mento vertical estar estável (já está). |
| 7 | **V shape** | O ícone atravessa bochecha + mandíbula + queixo. Sem Cheekbones (e sem aceitar Jaw+Chin como estão) vira um operador único outra vez. |
| 8 | **Lift** | Mesmo andar do Width, sentido contrário. Só com Jaw estável. |
| 9 | **Double Chin** | Pedem pescoço/submento. Não temos essa região. |
| — | **Face Slim / Narrow Face** | Não estão nos ecrãs Meitu como estes sliders. Fora do roadmap de produto. |
| — | **Smooth** | No nosso app é pele (shader), não Rosto. |

---

## 4. Dependências (produto)

“Depende de Jaw/Chin” = **precisa que esse slider já exista e fique como está**, ou pisa o mesmo sítio no ecrã. Não é dependência de código.

| Slider | Depende de Jaw? | Depende de Chin? | Independente? |
|---|---|---|---|
| Cheekbones | Independente como *slider*. H usa cauda leve no gônio (peso 0.22), como o Meitu; não é o Jaw. | Não (mento a zero). | **Sim** (região). |
| Temple | Não | Não | **Sim** |
| Hairline | Não | Não | **Sim** |
| Width | **Sim** — mesmo andar que o Jaw actual | Não | Não |
| Jaw Angle | **Sim** — mesmo canto (58/288) | Não | Não |
| Lift | **Sim** — cantos do maxilar | Não | Não |
| V Chin | Não (gônio) | **Sim** — mesma ponta que Chin Length | Não |
| V shape | **Sim** (faixa baixa) | **Sim** | Não — também precisa de Cheek |
| Double Chin | Não | Leve (submento vizinho) | Na prática **independente** e bloqueado: falta pescoço |
| Face Slim | — | — | Fora do roadmap |

---

## 5. Recomendação final

**O Jaw está encerrado como slider de mandíbula.**

Não deve “continuar a evoluir” para ganhar pescoço, Δy, bochecha ou o envelope do Face Slim. Isso deixaria de ser o Jaw aprovado e voltaria a um operador que mistura o que o Meitu separa.

O que o Jaw já é: **estreitar gônios (Jawline/Width/Jaw angle no essencial).**  
O que falta no *produto* não está no Jaw: está no **mid-face e no terço superior**.

**O próximo trabalho de produto é Cheekbones.**

Chin Length está equivalente na função vertical. Não é o próximo gap.

Jawline completo do Meitu (incluindo pescoço) é um *outro* slider, mais tarde, se o produto quiser Neck — não uma revisão do `JawField`.
