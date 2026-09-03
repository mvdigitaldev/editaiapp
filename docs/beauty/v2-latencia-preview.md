# Latência do preview facial — porque o slider atrasa

Relatório de diagnóstico. Amostra `real-p01`, preview a 695×1024 (711 680 px),
medido em `flutter test` no Mac. Os números absolutos num telemóvel são
maiores; as **proporções** entre fases é que interessam.

---

## Sintoma

Arrastar um slider facial não acompanha o dedo. No Meitu a imagem muda em
tempo real; aqui há atraso visível.

## Onde estava o tempo

O que corre por cada movimento do slider, antes da correcção:

| Fase | Custo |
| --- | --- |
| `JawField.build` | **196 ms** |
| `BackwardBilinearWarp.apply` | 18 ms |
| `LandmarkAdvection.advance` | 0,2 ms |
| Cadeia com três efeitos activos | **437 ms** (2,3 fps) |

O remap não é o problema, e a advecção é irrelevante. O custo está em
**construir o campo**, e dentro dele:

| Componente do `JawField.build` | Custo |
| --- | --- |
| `RidgeWeight.at`, os dois lados | ~50 ms |
| `BoundaryFeather`, duas rampas | 53 ms (EDT 9,5 + borrão 17, cada) |
| Máscaras + `FieldMetrics.compute` | 61 ms |

Nada disto depende do valor do slider. As máscaras, as transformadas de
distância, as rampas e o peso de crista dependem só dos landmarks e do tamanho
da imagem. O slider entra no fim, num produto:

```
dx = amplitude(t) · pesoUnitário
```

Cinco dos seis efeitos já exploravam isso: guardam o peso unitário num
`*FieldRuntime` e, quando os landmarks e o tamanho não mudam, só reescalam os
pixels activos. **O `jaw` era o único sem essa separação** — e é o primeiro da
cadeia, portanto o mais arrastado.

Além disso o `jaw` calculava `FieldMetrics.compute` sempre, mesmo chamado pela
cadeia de preview, que não lê métrica nenhuma. Percorrer a imagem inteira a
medir dez regiões custava mais do que produzir o campo.

## Correcção

1. `JawFieldRuntime`, com a mesma chave dos outros cinco
   (`identical(face) && width && height`). `_applyNarrowing` passou a
   `_packUnitWeights` + `_scaleActive`.
2. `computeMetrics: false` na chamada da cadeia, com `FieldMetrics.skipped`
   como marcador. O device lab e o gate continuam a receber métricas reais.
3. No empacotamento, testar `boundaryRamp · earRamp` **antes** de calcular a
   crista: a rampa custa uma leitura, a crista custa vinte projecções com
   exponencial, e onde a fronteira já anula o peso a crista é trabalho perdido.

### Resultado

| Cenário | Antes | Depois |
| --- | --- | --- |
| `JawField.build` reaproveitado | 196 ms | **0,1 ms** |
| Arrastar só a Mandíbula (com remap) | ~215 ms | **14 ms** (71 fps) |
| Arrastar a Mandíbula com dois efeitos a jusante | 437 ms | 258 ms |

O resultado é idêntico ao construído de novo: fixado em
`runtime cache scales the same unit weights` (diferença máxima < 1e-4 em `dx` e
`dy`, para quatro valores de `t` seguidos no mesmo cache) e em
`um único efeito activo (jaw) preserva o resultado isolado`.

---

## O que continua lento, e porquê

Arrastar um efeito que tem outros **a jusante** na cadeia. A advecção move os
landmarks, portanto os efeitos seguintes recebem geometria nova a cada frame e
o seu cache falha por construção — não é um defeito do cache, é a semântica da
cadeia: cada efeito mede a imagem que recebe.

Custo medido a arrastar a Mandíbula com Queixo e Formato V activos:

```
jaw (cache)      0,1 ms
remap           18 ms
advecção         0,2 ms
chin (rebuild)  90 ms
remap           18 ms
advecção         0,2 ms
v_shape (reb.)  90 ms
remap           18 ms
                ------
                258 ms  →  3,9 fps
```

Arrastar o **último** efeito activo da cadeia não tem este problema: o cache de
advecção do controller devolve o mesmo objecto de landmarks e todos os efeitos
a montante acertam no cache.

---

# Segunda ronda — cortar o trabalho desperdiçado

O rebuild dos efeitos a jusante é inevitável, mas era feito na imagem inteira
quando o efeito ocupa uma fracção dela. Cinco correcções, todas com o mesmo
critério: **o resultado não muda**. Cada uma tem um teste que o fixa contra a
definição que substitui, e a suíte inteira (535 testes, incluindo `minDetJ`,
degrau de entrada, curvatura de núcleo, bico na silhueta e antialiasing) passa
sem alterar um único limite.

### 1. O remap só visita o suporte do campo

Onde o campo e os oito vizinhos são nulos, a jacobiana é a identidade, o remap
devolve `src = p` e a bilinear em posição inteira lê um só tap: o destino é o
pixel de origem, que já está copiado. Um campo facial é nulo em mais de três
quartos da imagem.

A caixa é dilatada de um pixel porque a decisão de filtrar por área lê os
vizinhos — sem essa dilatação, um pixel nulo com vizinho activo mudaria de
caminho.

Fixado em `campo de suporte compacto não toca o resto da imagem`.

**18,3 ms → 9,4 ms.**

### 2. A rampa de fronteira corre numa janela

`BoundaryFeather` recorta a máscara para a caixa da região de interesse,
calcula lá a distância e os dois borrões, e devolve. A distância nem sabe que
existe janela.

Isto é exacto e não uma aproximação: todo o pixel fora da caixa da região de
interesse é semente, logo qualquer pixel de interesse tem a sua semente mais
próxima dentro dessa caixa dilatada de um — ou é uma semente interior, ou é a
moldura imediata. A janela leva ainda o suporte dos dois borrões, para que a
replicação de borda replique zeros, que é o que a imagem inteira teria lá.

Fixado em `não depende do tamanho da moldura vazia em volta`: a mesma máscara
numa imagem de 120×100 e numa de 400×320 dá diferença máxima **0**.

**25,8 ms → 5,7 ms.**

### 3. A rasterização de polígonos passou a ser por linha

`fillPolygon` testava cada pixel da caixa contra todos os vértices. O oval da
cara tem 36 e a sua caixa cobre meia imagem. As arestas que o raio horizontal
atravessa, e a abscissa de cada travessia, são as mesmas para toda a linha.

A regra é a de sempre — um ponto está dentro quando o número de travessias à
sua direita é ímpar — com a mesma aritmética, logo o conjunto de pixels
marcados é idêntico, casos degenerados incluídos. `pointInPolygon` ficou
público para os testes poderem comparar contra ela.

Fixado em `coincide com a definição ponto a ponto` (triângulo, vértice em cima
da linha de amostragem, côncavo, auto-intersectante, aresta horizontal,
polígono fora da imagem) e `coincide no oval de uma cara real`.

**14,2 ms → 1,3 ms.**

### 4. A dilatação é local

`dilate` media a distância na imagem inteira para depois só olhar a caixa do
que está marcado. Nada a mais de `radius` de um pixel marcado pode mudar.

Fixado em `coincide com a distância medida na imagem inteira`, para raios 1, 7
e 30, com uma semente encostada à borda.

**12,5 ms → 3,8 ms.**

### 5. O peso de crista: vectores planos e um corte por caixa

Duas mudanças em `RidgeWeight`:

- `Ridge.of` prepara os segmentos em `Float64List` uma vez por efeito. Antes,
  cada pixel pagava a indirecção de dois objectos `Offset` por segmento e o
  cálculo do comprimento. A ordem das operações é a mesma da versão anterior,
  de propósito, para o resultado não mudar nem no último bit.
- `RidgeWeight.stronger` devolve a mais forte de duas cristas sem avaliar a que
  não pode ganhar. A distância a qualquer ponto de uma crista nunca é menor que
  a distância à sua caixa, e a média ponderada nunca passa o maior peso dos
  nós, logo `maxWeight · exp(−dCaixa² / 2σ²)` limita-a por cima. Na bochecha
  esquerda a crista direita está a meia cara e o seu peso é indistinguível de
  zero: o limite custa duas subtracções e dispensa percorrer aquele lado.
  `aWins` segue a convenção `pesoA >= pesoB`, e é por isso que o corte de `b`
  admite igualdade e o de `a` não — descartar `a` por empate podia trocar o
  vencedor.

Também se passou a testar a fronteira **antes** da crista nos cinco efeitos que
faltavam: a rampa custa uma leitura, a crista custa vinte projecções com
exponencial.

Fixado em `dá o mesmo que avaliar as duas cristas`: valor e vencedor idênticos
em toda uma grelha de 480×360, com diferença **0** e zero trocas de vencedor.

**32,8 ms → 20,8 ms** (dos quais 12 ms vieram do reuso das projecções entre os
dois laços, que antes se calculavam duas vezes).

### 6. O envelope malar tem caixa de suporte

O `cheekbone` marcava a região da bochecha percorrendo os 711 680 pixels e
avaliando os dois envelopes malares em cada um — cada avaliação com projecções,
raiz e exponencial. O envelope é o peso do ponto da crista mais próximo
amortecido por uma gaussiana, logo `maxW · exp(−dCaixa² / 2σ²)` limita-o, e
além do raio onde esse limite cai abaixo do limiar de 0,04 não há nada a
marcar. `max(esquerdo, direito) > limiar` é o mesmo que marcar o que cada um
passa, dentro da sua caixa.

Fixado em `supportBox contém todo o envelope acima do limiar`.

**Rebuild do `cheekbone`: 234 ms → 75 ms.**

## Onde ficámos

| Cenário | Início | Depois da 1.ª ronda | Agora |
| --- | --- | --- | --- |
| Arrastar só a Mandíbula | ~215 ms | 14 ms | **3,9 ms** (256 fps) |
| Arrastar a Mandíbula com dois efeitos a jusante | 437 ms | 258 ms | **91 ms** (11 fps) |
| Rebuild dos seis efeitos, somado | — | ~437 ms | **291 ms** |

Rebuild por efeito, agora: `v_chin` 19 ms, `jaw_angle` 30, `chin` 25–37,
`v_shape` 52, `jaw` 75, `cheekbone` 78.

## O que continua a faltar para tempo real com vários efeitos

O caso de um efeito está resolvido com folga. Com três efeitos activos, a
arrastar o primeiro, restam ~91 ms, repartidos entre dois rebuilds (~77 ms) e
três remaps (~28 ms). Limando mais CPU o tecto desta arquitectura fica na casa
dos 60–80 ms, porque cada efeito tem de remedir a geometria que recebe.

Três vias, por ordem de risco:

1. **Warp facial fora da thread da UI.** Não reduz a latência, mas o slider
   deixa de engasgar e o gesto passa a acompanhar o dedo. Já existe `compute()`
   no retoque de pele. Exige mover os `*FieldRuntime` para o isolate, senão o
   cache deixa de acertar.
2. **Campo na GPU.** É o que dá tempo real com qualquer número de efeitos, e já
   existe infra (`runPipeline`, `warpRemapShader` usado no warp de corpo). É a
   opção mais pesada.
3. **Não readvectar durante o arrasto**, refinando ao largar. Torna o arrasto
   fluido com um desalinhamento transitório dos efeitos a jusante. É mudança de
   semântica e precisa de decisão de produto.

### Uma via que foi medida e descartada

Baixar a resolução do preview durante o arrasto: a 50% do lado a cadeia de três
efeitos corre em **31 ms (32 fps)**, porque o custo escala com a área. Mas a
resolução é a chave de quase todos os caches do pipeline —
`ParsingMaskCache` (`width`/`height` na chave), `RenderStageCache`
(`sourceWidth`/`sourceHeight`), os `*FieldRuntime` e o pool de texturas, que
não reutiliza por tamanho. Com retoque de pele activo, alternar resolução por
frame forçaria re-inferir o parsing semântico e reconstruir as máscaras R8 a
cada frame, e ficaria mais lento do que está. Acresce que os sliders faciais
não têm `onChangeStart`/`onChangeEnd`, portanto não há sítio limpo para ligar e
desligar o modo. Descartada por agora.

---

## Notas de medição

- `flutter test` corre JIT no desktop. Num telemóvel em release espera-se o
  mesmo perfil relativo com números absolutos maiores.
- O preview desenha a 720–1080 px no lado maior (540 px em gama baixa) e o
  export até 4096 px. O custo escala com a área, logo o export paga mais.
- O slider facial não tem debounce: dispara logo e coalesce um frame. Com
  frames de 250 ms isso põe a imagem dois frames atrás do dedo, que é o atraso
  sentido.
