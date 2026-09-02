# V2 — Serrilhado na silhueta: a distância era L1

Data: 2026-09-02
Alcance autorizado por Leonardo, em dois passos escritos no mesmo dia:

1. **Transversal na distância**, nos seis Fields, incluindo V Chin (encerrado) e Cheekbones H («não alterar»).
2. **Reabrir o `jaw`** para trocar o `max` de gaussianas por crista em polilinha, mantendo amplitude `0.04`, Δx e energia nos gônios.

Amplitudes, hard-zeros e valores de slider: **intactos**. Nenhum outro efeito mudou de geometria.

---

## Sintoma

Leonardo, com **Mandíbula** (`jaw`) a 99%: serrilhado no bordo da silhueta, no ramo
entre a orelha e o gónio. Escada de pixel, não deformação errada.

---

## Diagnóstico

Duas causas independentes. O renderer está limpo: `BackwardBilinearWarp` é
bilinear puro e não introduz degraus. O defeito entra no campo.

### Causa 1 — `max` de gaussianas por landmark (só `jaw`) — **dominante, corrigida**

`jaw_field.dart` pesava a silhueta como `max` de gaussianas centradas em 8
landmarks discretos (`silhouettePrimary` a 1.0, `silhouetteSecondary` a 0.85),
σ = `0.08 × faceWidth`. O máximo de gaussianas isoladas ondula ao longo do bordo
— sobe em cada landmark, cai no vão — e na fronteira onde duas empatam a
derivada é descontínua.

Medido nos landmarks reais de p01/p05/p12, no ponto médio de cada vão contra as
âncoras que o limitam:

| Vão | Comprimento | σ | Peso no meio ÷ menor âncora |
|---|---|---|---|
| 132→58 (e 361→288) | 36–51 px | 23–30 px | **0.70 – 0.75** |
| 58→172 (e 288→397) | 29–45 px | 23–30 px | 0.90 – 0.97 |
| 172→136 (e 397→365) | 22–39 px | 23–30 px | 0.81 – 0.89 |

O vão 132→58 perdia **~30% do peso** ao longo de ~25 px de silhueta. Com
amplitude `0.04 × faceWidth` isso é uma ondulação de vários pixéis de
deslocamento no ramo orelha→gónio — exactamente onde Leonardo marcou o círculo.

É o mesmo defeito que este projecto já tinha resolvido no Cheekbones: *«`weight`
= distância à crista, **não** `max(gaussianas)`»*. O `jaw` era o último Field
com o padrão antigo.

**Correcção:** crista em polilinha, à imagem do Cheekbones e do V Shape.

```
curveLeft    = [132, 58, 172, 136]
curveRight   = [361, 288, 397, 365]
curveWeights = [0.85, 1.00, 0.90, 0.65]
sigmaAcrossFaceWidth = 0.08   (era handleSigmaFaceWidth, mesmo valor)
```

Ordem de cima para baixo: cauda junto à orelha → gónio → curva → cauda para o
mento. Não inverter: voltar atrás corta a crista. O peso interpola ao longo da
polilinha com pico no gónio, o que preserva «energia nos gônios 58–288». Um
ponto médio é inserido entre âncoras consecutivas para a distância ao segmento
não cortar em curvas fechadas. `amplitudeFaceWidth` continua `0.04`, o campo
continua só Δx e os gónios continuam a mandar.

No modelo novo o mesmo quociente do quadro acima é **1.06 – 1.19** em todos os
vãos e nas três faces: o meio do segmento nunca cava.

### Causa 2 — distância de Manhattan em passos inteiros — **corrigida**

A rampa de fronteira usava um chamfer de duas passagens com 4 vizinhos e custo
1. Isso mede em **L1**, não em euclidiana: as isolinhas saem em losango a 45° e
em valores inteiros. Como a silhueta mandibular é oblíqua, `boundary = dist /
falloff` subia em escada em vez de rampa. Cada degrau valia
`amplitude / falloff = (0.04 · fw) / (0.12 · fw) ≈ ⅓ px` de deslocamento — e ⅓ px
num bordo de contraste alto (pele contra cabelo escuro) é visível.

O mesmo chamfer estava copiado **sete** vezes: uma em cada um dos seis Fields e
outra em `RegionMaskRaster.dilate`. No `dilate` tinha um segundo efeito: um raio
`r` só dilatava `r / √2` na diagonal, pelo que o domínio activo nascia em
losango, com quinas a 45° que a rampa depois imprimia.

---

## Correcção

Novo módulo `warp/v2/distance_transform.dart`:
`EuclideanDistanceTransform`, transformada euclidiana **exacta** (Felzenszwalb &
Huttenlocher), separável, `O(width × height)`.

- `toZeroOf` — distância ao zero mais próximo (substitui `_distanceToInactive`).
- `toNonZeroOf` — distância ao não nulo mais próximo (substitui
  `_distanceToProtected` do Cheekbones e o chamfer do `dilate`).

As sete cópias do chamfer foram removidas. Ficheiros tocados na Causa 2:
`jaw_field.dart`, `jaw_angle/jaw_angle_field.dart`, `chin/chin_field.dart`,
`v_chin/v_chin_field.dart`, `v_shape/v_shape_field.dart`,
`cheekbones/cheekbones_field.dart`, `region_masks.dart`.

Não é um efeito novo nem uma Sprint. Não entra na cadeia nada de novo: é a mesma
rampa dos mesmos Fields, medida sem enviesamento direccional.

### Consequência assumida

O `dilate` passa a ser um disco em vez de losango, portanto o domínio activo
cresce nas diagonais até `r · (1 − 1/√2)` ≈ 29% de `r`. Isso é a intenção
declarada do pad («os gónios ficam no planalto, não na rampa») a funcionar de
forma isotrópica pela primeira vez. Afecta os seis efeitos de igual modo e
nenhuma métrica de lab saiu fora de tolerância.

---

## Verificação

- `facial_warp_v2_distance_transform_test.dart` — novo. Exactidão contra força
  bruta em máscara irregular, 3-4-5 (o L1 dava 7), semântica das duas sementes,
  1-Lipschitz sobre fronteira oblíqua (a rampa não pode ter degrau duplo),
  ausência de `NaN` sem sementes, guardas de tamanho.
- `facial_warp_v2_jaw_field_test.dart` — dois testes novos. **`t=1`** (o slider
  vai a 99% e o lab só cobria `t=0.5`): sem dobra e protecções mantidas nas três
  faces. **Anti-festão**: no ponto médio de cada vão da crista o `|dx|` tem de
  ficar ≥ 0.8 × a menor âncora. O limiar foi escolhido a partir da medição
  acima, portanto o teste **rejeita** o modelo antigo (0.70–0.75 no vão 132→58)
  e aceita o novo — não é um teste que passa sempre.
- `flutter test test/beauty_engine/` — **418 passam**. Inclui `minDetJ` dos seis
  efeitos (sem dobra em nenhuma face de benchmark), V Chin e Cheekbones H.
- `flutter analyze` — limpo nos ficheiros tocados.
- Custo, 1080×1440 em JIT: chamfer L1 18,6 ms, EDT 21,5 ms (**1,15×**). Em
  release AOT a diferença é menor. Os Fields com cache de peso unitário só
  pagam isto quando a geometria muda, não por movimento de slider.

---

## Passo 3 — a ponta no topo do ramo (mesmo dia, após ver a foto)

Leonardo, com o slider a 100%: a silhueta ficava **pontuda** na lateral do rosto,
à altura dos olhos. Pediu que a mandíbula puxe «100% da área da mandíbula e 5%
dessa área ali de fora, para não ter esse corte brutal».

Medido em `t=1`, o deslocamento ao longo da silhueta de cima para baixo era:

| | 127 | 234 | 93 | 132 | 58 |
|---|---|---|---|---|---|
| antes | 0.00 | **0.00** | **0.00** | 8.51 | 9.89 |
| agora | 0.00 | 0.51 | 2.12 | 8.55 | 9.89 |

O corte **não era da crista, era do domínio**: no 132 o campo valia 8.5 px e no
93, a 47 px de distância, valia zero, porque o pixel simplesmente saía do hull
do jaw. A rampa de fronteira só actua dentro do domínio, logo não havia
transição nenhuma — daí a ponta.

Três correcções, todas no `jaw_field.dart`:

1. **Cauda na crista.** `curveLeft` passou a `[234, 93, 132, 58, 172, 136]`
   (espelho `[454, 323, 361, 288, 397, 365]`) com pesos
   `[0.05, 0.20, 0.85, 1.00, 0.90, 0.65]`. Os dois primeiros levam peso baixo de
   propósito: é a cauda pedida, não é Cheekbones.
2. **Domínio estendido.** `taperLandmarks = {234, 93, 454, 323}` entram no hull.
   Sem isto o peso da cauda não tem onde actuar e a mudança não teria efeito.
3. **Pina fora da rampa longa.** O disco da orelha estava centrado em 323/454
   com raio `0.06 × faceWidth`. Mas **323/454 estão no oval, não na pina**: são
   a lateral do rosto, espelho de 93/234. O disco comia a silhueta e, pior,
   entrava na rampa de `0.12 × faceWidth`, o que deixava a cauda do lado direito
   a **um terço** do lado esquerdo (0.70 contra 2.12). Adoptado o esquema já
   validado no Cheekbones: raio `0.022`, pina deslocada `0.05` para fora do oval,
   e rampa própria `earFalloffFaceWidth = 0.035` separada da rampa do domínio.
   A cauda ficou 1.54 contra 2.12 — a assimetria que resta é a da própria pose.

A protecção da orelha mantém-se: `ears.p95Abs = 0` nas três faces.
`minDetJ` = 0.36–0.47 em `t=1`. `outsideJawZoneP95 = 0`.

Teste novo, `cauda na lateral do rosto é leve e simétrica`: exige a cauda entre
2% e 35% do pico no 93/323 e entre 0.5% e 15% no 234/454, e menos de 2× de
diferença entre os lados. Rejeita o estado anterior por ambos os motivos (era
0% no 93 e 3× de assimetria depois da cauda).

---

## Passo 4 — o vinco na bochecha: a rampa herdava a medial axis

Leonardo, com **Mandíbula** e **Formato V** ambos a 100% para a direita: «ele
buga e fica tudo errado, olha a força dos cortes puxando apenas onde ele tem a
maior área de atuação». Na foto, três setas paralelas apontando uma linha
diagonal a meio da bochecha, paralela à silhueta.

### Não era dobra

`minDetJ` estava positivo (0,53) e a cadeia passava todos os testes. O que
faltava era medir **vinco**: uma quebra de gradiente passa o crivo do `detJ` e
ainda assim imprime uma linha na pele, porque o olho lê a derivada segunda. A
métrica passou a ser a maior segunda diferença do campo.

### Causa — o bico da transformada de distância

A rampa `min(1, dist / falloff)` herda a crista da transformada de distância. Na
**medial axis** do domínio a distância tem um máximo interior, com
`|grad dist| = 1` de cada lado e sinais opostos, logo o gradiente da rampa salta
`2 / falloff`. Medido no `v_shape` de p01, numa linha à altura do 397:

| k (px do 397) | −24 | −16 | −12 | 0 | +12 | +24 |
|---|---|---|---|---|---|---|
| `dist` | 38.9 | **45.0** | 43.6 | 33.1 | 21.9 | 10.8 |
| `boundary` | 0.644 | 0.746 | 0.722 | 0.548 | 0.363 | 0.178 |

O máximo da distância cai a 45 px da fronteira, a meio da zona activa. Como
`falloff` vale `0,16 × faceWidth` = 60 px e a medial axis está a 45, a rampa
**nunca satura**: o bico fica no meio da bochecha com peso 0,72. Com a amplitude
de 20,7 px isso dá 0,69 px/px de salto de gradiente — a linha das setas.

O bico existia nos **seis** efeitos, com a rampa copiada em cinco Fields.
Curvatura no núcleo do efeito, antes: `jaw_angle` 0,88, `cheekbone` 0,84,
`v_chin` 0,69, `v_shape` 0,77, `jaw` 0,55, `chin` 0,49.

### Correcção

Novo módulo `warp/v2/boundary_feather.dart`: `BoundaryFeather`, que borra a
rampa com três passagens de caixa (aproximação da gaussiana, `O(n)`), e assim
arredonda tanto a medial axis como o joelho da saturação. `insideActive` e
`awayFromInactive` cobrem as duas sementes já usadas pelos Fields.

Dois detalhes que só a medição revelou, ambos travados por teste:

1. **O borrão sozinho desfaz o zero na fronteira.** Espalha peso para cima da
   borda, e o campo, que fora do domínio é nulo, passou a saltar 1,3 px na
   fronteira do `v_shape` e a inverter (`minDetJ` −0,20). Perto da fronteira
   volta-se por isso à rampa crua.
2. **A troca tem de ser mistura, não porta multiplicativa.** Uma porta impõe a
   sua própria escala; como o suporte do borrão é bem menor que `falloff`, sai
   mais abrupta que a rampa e aperta-a pelo factor 1,5 do smoothstep. O `chin`,
   que já vivia no limite (`dy` cai exactamente 1,00 px/px), inverteu
   (`minDetJ` −0,007 a t=−1). Na mistura o único termo acrescentado ao gradiente
   é `g' × (borrado − cru)`, desprezável porque a diferença é da ordem do
   borrão.

Também se limitou o desvio a `falloff / 3`: com o suporte acima do `falloff` a
mistura fica aberta onde a rampa já saturou e devolve o cru em toda a transição,
que era o caso da rampa da orelha do `cheekbone` (`earFalloff` 13 px contra
24 px de suporte).

Na mesma passagem migraram-se para a crista contínua (`RidgeWeight`) os três
Fields que faltavam — `jaw`, `jaw_angle`, `v_shape` — e a interpolação do peso
ao longo da crista passou a smoothstep. A crista do `v_shape` tem o pico num
vértice interior (`58 → 172 → 136` com pesos `0,20 → 1,00 → 0,62`), e com
interpolação linear o máximo do peso era um bico, não uma curva: o gradiente
passava de +0,33 para −0,45 num ponto.

### Resultado

Curvatura no núcleo do efeito, onde o deslocamento vale ao menos um quarto do
pico:

| efeito | antes | agora |
|---|---|---|
| `jaw` | 0.55 | **0.14** |
| `jaw_angle` | 0.88 | **0.15** |
| `chin` | 0.49 | **0.16** |
| `cheekbone` | 0.84 | **0.16** |
| `v_shape` | 0.77 | **0.20** |
| `v_chin` | 0.69 | 0.50 |

`minDetJ` subiu em todos: `jaw` 0,34 → 0,62, `chin` 0,31 → 0,41, `cheekbone`
0,49 → 0,58. Na cadeia que Leonardo reportou — Mandíbula 100% e Formato V 100%
— a curvatura interior do campo total ficou em 0,00–0,07 com `minDetJ` 0,57–0,60
nas cinco faces.

### Pendência conhecida

O `v_chin` continua acima dos restantes por causa do joelho do `midGate`, que
vale `amplitude / midBlend`. Com os `0,080` de amplitude deste efeito esse
gradiente é 0,73 e é também o que lhe segura o `minDetJ`, pelo que suavizar o
joelho — a única correcção possível — exige baixar a amplitude. É decisão de
calibração do V Chin e não desta correcção. O tecto do teste está em 0,55 para
este efeito e 0,25 para os outros cinco.

Fica igualmente por tratar o arranque da rampa na própria fronteira do domínio,
onde o campo sai de zero com gradiente `amplitude / falloff`. É um joelho
inerente à rampa linear e está fora do núcleo do efeito, logo longe do olho.

> Esta última pendência era o serrilhado fino que Leonardo viu a seguir. Estava
> mal avaliada: o joelho não está longe do olho, está exactamente sobre a
> silhueta. Ver o Passo 5.

---

## Passo 5 — o serrilhado fino: a rampa entrava com um passo

Leonardo, com o bico já resolvido: «está quase perfeito, quase; ficaram alguns
serrilhados bem pequenos, mas geram reclamações dos clientes». As setas caem
sobre a fronteira pele/cabelo na têmpora.

### Diagnóstico

As métricas em uso não o apanhavam. O `minDetJ` estava em 0,57 e a curvatura no
núcleo em 0,26, ambos dentro dos tectos — e com razão, porque o defeito não está
no núcleo: está na **fronteira**, que o núcleo exclui de propósito.

Medido o campo pixel a pixel a atravessar a fronteira do domínio do `v_shape`
(p01, `t=1`), na horizontal:

```
0,000   0,000   −0,226   −0,361   −0,529   −0,720
        ↑ fronteira      ↑ primeiro pixel dentro
```

O primeiro pixel dentro do domínio vale já 0,23 px. É aritmética da rampa: com
`min(1, d / falloff)` a derivada no arranque é `1 / falloff`, portanto o primeiro
pixel, que está a um pixel da fronteira, leva `amplitude / falloff` — com 13,5 px
de amplitude e 60 px de `falloff`, 0,23 px.

Um passo constante ao longo de uma fronteira lisa seria invisível. O que o torna
visível é a fronteira **não** ser lisa: as máscaras de região são binárias e
rasterizadas a pixel cheio, logo uma silhueta oblíqua sai em dentes de um pixel.
O passo acompanha os dentes, e o resultado é uma orla que salta 0,23 px para
dentro e para fora ao descer a face. Na pele contra o cabelo, onde o contraste é
máximo, isso lê-se como serrilhado apesar de ser sub-pixel.

Foi por isso que a rampa borrada não bastou: junto à fronteira o `BoundaryFeather`
**mistura de volta ao cru**, de propósito, para não desfazer o zero da borda — e
o cru é precisamente onde o passo vive.

### Correcção

Duas mudanças, ambas em `warp/v2/boundary_feather.dart`. Nenhum efeito foi
tocado, nenhuma amplitude mexeu.

**A rampa passou a smoothstep**, `r²(3−2r)`. Tem derivada nula nas duas pontas:
entra do zero sem passo e fecha na saturação sem joelho. O primeiro pixel passa
a valer `3 (1/falloff)²`, uma ordem de grandeza abaixo. O preço é `1,5 / falloff`
de gradiente ao meio da rampa em vez de `1 / falloff`; com os `falloff` em uso
isso fica muito abaixo de 1 e por isso não ameaça o `detJ`.

**A distância é alisada** com σ fixo de 1,2 px antes da rampa. Fixo em pixels, e
não em fracção da cara, porque o dente da rasterização mede um pixel qualquer que
seja o tamanho da cara. O borrão apaga a oscilação, que corre ao longo da
fronteira, mas também levanta a rampa acima do zero na travessia, pelo que se
desconta `σ/√(2π)` — o valor médio de `max(0, d)` alisado sobre uma fronteira
recta — e se corta em zero. A fronteira efectiva passa a ser a curva de nível de
uma função já alisada, lisa ao longo dela. Quem está fora do domínio fica fora:
sem essa guarda o borrão espalha distância para o exterior e a rampa deixa de
valer zero lá, que é o que faz o campo casar com a parte parada da imagem.

### Verificação

Degrau de entrada, o maior deslocamento num pixel com vizinho parado, pior das
cinco faces reais nos dois extremos:

| Efeito | Antes | Depois |
| --- | --- | --- |
| `jaw` | 0.20 | **0.042** |
| `v_shape` | 0.23 | **0.029** |
| `chin` | — | **0.063** |
| `v_chin` | — | **0.089** |
| `jaw_angle` | — | **0.029** |
| `cheekbone` | — | 0.244 |

O `minDetJ` continua positivo em todos, com mínimo de 0,196 no `chin` a `t=−1`,
e a curvatura no núcleo desceu ou manteve-se. O alisamento da distância paga por
si: sem ele o degrau ficaria em 0,042 no `v_shape` e 0,114 no `v_chin`, e a
curvatura no núcleo do `cheekbone` em 0,237 em vez de 0,183.

Custo: +8% na construção dos campos, 682 ms contra 631 ms para os seis a
695×1024.

A métrica entrou nos testes, ao lado da curvatura no núcleo, no
`nenhum efeito vinca o núcleo nem entra com degrau`. O `BoundaryFeather` ganhou
também um teste com fronteira oblíqua rasterizada, que é a geometria do defeito.

### Pendência conhecida

O `cheekbone` fica em 0,244, seis vezes acima dos outros. Não é a rampa de bordo:
quem lhe manda o campo a zero junto à orelha é a rampa de 13 px do `earFalloff`,
e 13 px são curtos para uma zona onde o efeito está no seu pico — em p01 o último
pixel activo junto ao landmark 454 sai a 0,117 px. Encurtar esse degrau é
recalibrar o `earFalloff`, decisão do Sprint do Cheekbones, que está em inspecção
sem Sprint C.

---

## Passo 6 — o aliasing onde o remap comprime

Leonardo, com a rampa já corrigida e a testar **só** a Mandíbula a 100%: «está
98%, no meio das linhas vermelhas fica um pouco serrilhado». A faixa marcada é
interior à bochecha, não a silhueta.

### O campo não era o culpado

Primeiro excluí a hipótese óbvia. Medido o resíduo de alta frequência do `jaw`
bem dentro do domínio — o campo menos a sua versão alisada a σ ≈ 1,15 px, que
deixa passar só o que varia em um ou dois pixels — o pior valor é 0,06 px em p01
e 0,13 px em p06, e as vizinhanças descem monotonamente:

```
-9,973  -9,922  -9,838  -9,720  -9,565  -9,373  -9,144
```

Sem escada. O defeito está na **amostragem**, não no campo.

### Diagnóstico

O remap é `src = p − D(p)`, logo a sua jacobiana é `A = I − JD`. Onde o maior
valor singular de `A` passa de um, um passo de um pixel no destino salta mais de
um pixel na origem — e a bilinear, que lê o quadrado `2×2` em volta do ponto,
deixa cair tudo o que fica no meio. É aliasing por falta de pré-filtro, e numa
borda de contraste lê-se como serrilhado.

Medido nas cinco faces com o `jaw` no extremo:

| Face | Compressão máxima | Pixels deslocados que comprimem |
| --- | --- | --- |
| p01 | 1.373 | 42.1% |
| p05 | 1.410 | 43.9% |
| p06 | 1.336 | 42.9% |
| p12 | 1.428 | 43.0% |
| p21 | 1.352 | 42.7% |

Quase metade da zona do efeito. Contra o filtro de área exacto, com 8×8
sub-amostras, num alvo de contraste 20–245: **33 de erro RMS e 57 de pior caso**.

Isto **não é um defeito só do preview**. A compressão é uma razão de gradientes,
e como a amplitude e o `falloff` escalam ambos com a cara, ela é a mesma em
qualquer resolução: existe igual no export. O preview apenas a torna mais
visível, porque corre a 720–1080 px de maior lado e é esticado para o ecrã com
`FilterQuality.medium`, mais o zoom do `InteractiveViewer` — um artefacto de um
pixel no preview chega ao olho com um pixel e meio ou dois.

### Correcção

`BackwardBilinearWarp` passou a filtrar por área os pixels que comprimem: uma
grelha de `n×n` sub-amostras dentro do pixel de destino, com `n = ⌈σ_max⌉` até
três, cada uma lendo o campo interpolado. A média sobre a grelha do destino é o
filtro de área da sua pré-imagem, que é exactamente o que falta à bilinear.

Duas decisões deliberadas:

- **Acima de `σ_max ≤ 1,05` fica a bilinear pura.** Filtrar por área onde não há
  compressão só custaria nitidez. Translação pura, que tem compressão exactamente
  um, continua a sair da bilinear, e há teste para isso.
- **Sub-amostra com origem fora do rect é descartada da média**, não presa à
  borda, para manter a regra de não fazer clamp da coordenada de origem.

### Verificação

Erro face ao filtro de área, nos pixels que comprimem:

| | Antes | Depois |
| --- | --- | --- |
| RMS | 33.0 | **2.8** |
| Pior caso | 57 | **7** |

Doze vezes menos, num alvo que só vai de 20 a 245. Custo: +6,4 ms por remap,
17,8 contra 11,4 ms a 695×1024, face aos cerca de 113 ms que a construção de cada
campo já leva.

Fixado em `facial_warp_v2_antialias_test.dart`, com três afirmações: translação
pura não perde nitidez, compressão uniforme de 1,35× fica junto ao filtro de
área, e nenhum dos seis efeitos no extremo alia onde comprime, nas cinco faces.

### Nota sobre o teste do Face Slim

O `renderer applies vertical displacement on slimActive` passou a escolher um
ponto com a vizinhança toda activa. Esse teste pinta um campo sintético que salta
5 px na fronteira da máscara, e aí o renderer filtra por área de propósito —
exigir-lhe o valor de uma amostra pontual seria exigir o aliasing que ele existe
para evitar. O que o teste afirma, o deslocamento, mantém-se intacto.

---

## O que mudou no resultado visual

Preencher os vãos aumenta a energia média ao longo da silhueta: o efeito fica
mais **uniforme** e um pouco menos concentrado nos picos dos landmarks. Era o
custo assumido ao autorizar a reabertura. A amplitude de pico não subiu
(`0.04 × faceWidth` intacta) e `minDetJ > 0` em `t=1` nas três faces.

Falta assinatura visual de Leonardo no editor. Enquanto isso, o `jaw` continua
**aprovado e vivo**; esta é uma correcção de qualidade de campo, não uma sprint
nova nem uma mudança de papel de produto.
