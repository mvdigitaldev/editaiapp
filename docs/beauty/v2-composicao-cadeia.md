# V2 — Composição da cadeia facial (advecção de landmarks)

Data: 2026-09-02. Autorizado por Leonardo no mesmo dia (opção «propagar os
landmarks pela cadeia», preview e export em conjunto).

## Sintoma

Com **Mandíbula a 100%** e o **Ângulo da mandíbula** puxado, a silhueta ganhava
pontas nas laterais, à altura da boca. Adicionando **Formato V** por cima, com a
mesma configuração, a bochecha deformava de forma grosseira.

Cada efeito, isolado, estava correcto. O defeito só aparecia ao combinar.

## Causa

A cadeia aplicava um efeito sobre o RGBA que o anterior devolveu, mas passava a
**todos** o mesmo `face` da detecção:

```dart
final jawRgba      = applyJawWarp(sourceRgba: rgbaSource.bytes, face: face, ...);
final jawAngleRgba = applyJawAngleWarp(sourceRgba: jawRgba,     face: face, ...);
final faceRgba     = applyChinWarp(sourceRgba: jawAngleRgba,    face: face, ...);
```

O efeito a jusante recebia a imagem deformada mas media a geometria na imagem de
origem. Com o Jaw a 100%, a silhueta desloca-se sob as âncoras que ficaram
paradas:

| Âncora | 132 | 58 | 172 | 136 | 361 | 288 | 397 | 365 |
|---|---|---|---|---|---|---|---|---|
| p01 | 8,5 | 9,9 | 9,1 | 6,4 | 8,2 | 9,6 | 8,9 | 6,3 |
| p05 | 6,6 | 7,8 | 6,9 | 4,3 | 6,5 | 7,4 | 6,7 | 4,9 |
| p12 | 7,7 | 8,8 | 7,8 | 4,5 | 7,1 | 8,3 | 7,7 | 5,5 |

Deslocamento da silhueta em px, `jaw = 1`.

Estas oito âncoras são precisamente a crista do Jaw Angle **e** do V Shape. Com
a crista 6–10 px fora do bordo, parte do peso caía em cabelo e fundo, e a
silhueta verdadeira ficava na periferia da rampa, onde o peso já decaiu. Daí as
pontas, e daí o agravamento no segundo print, onde o erro do Jaw e do Jaw Angle
se acumulava antes de o V Shape entrar.

## Correcção

`warp/v2/landmark_advection.dart`. Entre etapas, os landmarks passam para a
geometria já deformada.

O renderer é backward (`src = dest − D(dest)`), logo o ponto material que estava
em `p` aparece em `q` com `q − D(q) = p`. Resolve-se por ponto fixo
`q ← p + D(q)`, com três iterações e amostragem bilinear do campo. Converge
porque o campo não dobra.

Só os landmarks avançam: `boundingBox` e `confidence` seguem intactos, porque
nenhum Field os lê e a convenção de unidades do rect não é a do campo.

A cadeia passou a viver num único método, `applyFaceWarpChain`, usado tanto pelo
preview (`_renderTexture`) como pelo export (`TiledExportEngine`), de modo a não
haver duas ordens possíveis. As seis funções `applyXWarp` continuam públicas e
inalteradas, para uso isolado e nos testes.

Resíduo medido `|q − D(q) − p|` sob a crista, com `jaw = 1`: **0,032 a 0,065 px**
nas três faces, contra os 4–10 px de desalinhamento anteriores.

### Cache

Os Fields memoizam o peso unitário por `identical(face, ...)`. Uma advecção que
devolvesse sempre um objecto novo invalidaria esse cache a cada frame e o slider
passaria a recalcular as máscaras de todos os efeitos a jusante.

Por isso a advecção é memoizada por etapa e devolve o **mesmo objecto** enquanto
a origem e os sliders das etapas anteriores não mudarem. Etapa com slider em
identidade é saltada por inteiro — sem remap e sem advecção —, o que preserva a
identidade naturalmente.

## Porque não se somam os campos

Somar os seis `DisplacementField` e aplicar um único remap alinharia a geometria
com uma só reamostragem, e seria mais rápido. Para o caso dos prints é até mais
estável que encadear: `minDetJ` 0,13 contra 0,08.

Mas varrendo as 32 combinações de sinal com os seis efeitos no máximo, o campo
somado **inverte**:

| Face | `minDetJ` da soma | Deslocamento máximo |
|---|---|---|
| p01 | −0,78 | 30,8 px |
| p05 | −0,68 | 23,4 px |
| p12 | −0,64 | 26,4 px |

Inversão é a imagem a cruzar sobre si mesma: artefacto pior que o original.
Encadear remaps individualmente injectivos preserva a garantia, porque a
composição de injectivos é injectiva. A soma só serviria com um limitador de
dobra por cima, que atenuaria o efeito justamente no extremo do slider.

## Defeito herdado: dobra no queixo (corrigido)

Os testes de composição revelaram que **dois efeitos dobravam sozinhos**, sem
cadeia alguma, apenas no extremo positivo. `minDetJ` do campo isolado, sobre os
landmarks da detecção:

| t | chin (p01) | v_chin (p01) | v_chin (p05) | v_chin (p12) |
|---|---|---|---|---|
| 0,50 | 0,477 | 0,298 | 0,475 | 0,427 |
| 0,75 | 0,216 | **−0,053** | 0,213 | 0,140 |
| 1,00 | **−0,046** | **−0,404** | **−0,050** | **−0,146** |

Era anterior à advecção e independente dela: o Chin dobrava igual sobre os
landmarks de origem (−0,046) e sobre os advectados (−0,042). No V Chin, que já
estava no limite, a geometria mais estreita agravava de −0,45 para −0,74.

Leonardo autorizou a correcção em 2026-09-02, reabrindo os dois **só** para
eliminar a dobra, sem tocar na amplitude nem no aspecto.

### Causa

O V Chin só escreve `dx` e deixa `dy = 0`, logo `detJ = 1 + ∂dx/∂x`: a inversão
é exactamente o gradiente horizontal a passar de −1. O perfil mostrou que não
era um gradiente acumulado, mas um degrau isolado de 1,4 px onde a vizinhança
variava 0,4 px por pixel, e com a distância à fronteira já saturada (62 px para
um falloff de 46), o que excluía a rampa de bordo.

O degrau estava no peso da crista. `_ridgeWeight` resolvia a distância pela
polilinha, que é contínua, mas tomava o peso interpolado **só do segmento
vencedor**:

```
x=390 seg=1 bestW=0.8224 bestD=39.44
x=391 seg=2 bestW=0.7420 bestD=38.96
```

Na medial axis da crista dois segmentos ficam à mesma distância e as respectivas
projecções caem em pontos de peso diferente, pelo que o peso salta ao trocar de
vencedor — aqui 0,080, que a amplitude de 30 px converte em 1,4 px de `dx`. É o
mesmo defeito de argmin discreto que tirou o `max(gaussianas)` da silhueta, um
nível abaixo.

Só se manifesta quando o raio de curvatura da crista é da ordem do sopro, porque
é isso que põe a medial axis dentro do alcance do peso. No queixo as duas escalas
coincidem: `sigmaAcross` 0,11 × faceWidth contra uma crista que dobra a curva do
maxilar.

### Correcção

`warp/v2/ridge_weight.dart`, um só sítio, como a transformada de distância. O
peso passa a ser a média dos segmentos ponderada por proximidade,
`exp(−½((d−dMin)/τ)²)`, com o decaimento a continuar a usar a distância mínima,
que já era contínua. Longe da medial axis o segmento mais próximo domina e o
resultado é o de sempre; sobre ela a troca distribui-se por alguns pixels.

`ridgeBlendFaceWidth = 0,012` (τ ≈ 4,5 px em p01) nos dois efeitos.

Comparação directa contra o cálculo anterior, varrendo a crista em p01/p05/p06:

| Medida | Antes | Depois |
|---|---|---|
| Pico do peso | 1,0000 | 0,9994 |
| Desvio médio | — | 0,006 |
| Desvio máximo | — | 0,038 |
| Degrau horizontal máximo | 0,046 | 0,015 |

O pico mantém-se, ou seja a amplitude não mexeu, e o degrau cai a um terço.
A largura da transição quase não altera o resultado (τ de 1,5 px já dá
`minDetJ` +0,42), o que confirma que o ganho vem de remover o argmin e não de
suavizar o perfil.

`minDetJ` isolado depois da correcção, pior caso sobre cinco faces e t = ±1 e
±0,75:

| Efeito | Pior `minDetJ` | Maior salto | Cálculo da crista |
|---|---|---|---|
| jaw | 0,341 | 0,659 | anterior |
| chin | 0,312 | 0,688 | **novo** |
| v_chin | 0,297 | 0,703 | **novo** |
| jaw_angle | **0,142** | **0,858** | anterior |
| v_shape | 0,485 | 0,515 | anterior |
| cheekbone | 0,488 | 0,512 | anterior |

Nenhum efeito dobra, em nenhuma face, em nenhum extremo.

### Pendência: os outros quatro

Jaw, Jaw Angle, V Shape e Cheekbones continuam com o peso do segmento vencedor.
Não dobram, mas têm o mesmo degrau latente, e o **Jaw Angle é o que tem menos
margem**: `minDetJ` 0,142 e salto de 0,858, isto é a 14% de inverter. É o
candidato seguinte, e convém tratá-lo antes de fechar a calibração dele.

## Testes

`test/beauty_engine/warp/v2/facial_warp_v2_chain_composition_test.dart`. Antes
disto não existia um único teste que aplicasse dois efeitos ao mesmo tempo —
toda a cobertura era efeito a efeito, e foi por isso que o desalinhamento e a
dobra do queixo passaram despercebidos.

Cobre:

- advecção reproduz uma translação uniforme, e preserva `index`, `z`,
  `visibility` e `confidence`;
- campo com tamanho diferente da imagem é recusado;
- resíduo sub-pixel sob a crista, exigindo que a fixture continue a exercer um
  desalinhamento maior que 3 px — se deixar de exercer, o teste denuncia-o em vez
  de passar vazio;
- `jaw + jaw_angle + v_shape` nos dois sinais, em três faces, sem dobra em
  nenhuma etapa: é o caso dos prints;
- seis efeitos no extremo, 32 combinações de sinal, sem dobra em nenhuma etapa,
  nem isolada nem em cadeia;
- os seis efeitos isolados nos dois extremos, nas cinco faces do banco: é a
  regressão que trava o regresso da dobra do queixo;
- cadeia é identidade com todos os sliders em zero, e devolve a origem sem face;
- **cada um dos seis efeitos, activo sozinho, dá resultado byte a byte idêntico
  ao `applyXWarp` isolado** — é a garantia de que nada do que já funcionava
  mudou;
- repetir uma combinação devolve exactamente o mesmo resultado, para que a
  memoização por etapa não contamine o estado.

`test/beauty_engine/warp/v2/facial_warp_v2_ridge_weight_test.dart` cobre a crista
contínua: densificação, peso sobre a âncora, decaimento perpendicular, saturação,
e duas comparações contra o cálculo anterior — numa crista fechada (raio igual ao
sopro) para exigir que o degrau caia a menos de metade, e numa crista realista
para exigir que o pico e o corpo do perfil não mudem. A primeira fixture falha de
propósito se deixar de exercer o degrau, em vez de passar vazia.

Suite completa: 492 casos verdes, sem skips. `flutter analyze` sem novos avisos.

## Pendente

- Assinatura visual do Leonardo nos dois prints que motivaram o trabalho, e no
  queixo aos 100%.
- Migrar Jaw, Jaw Angle, V Shape e Cheekbones para a crista contínua, a começar
  pelo Jaw Angle, que é o de menos margem.
