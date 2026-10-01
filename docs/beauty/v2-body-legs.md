# Body V2 — Pernas (`legs`)

Estado: **no editor para inspecção visual** (2026-10-01). Segundo menu do corpo, depois da Cintura.

Pedido do Leonardo: «agora vamos para outro menu, seguindo o mesmo padrao de travar o fundo vamos fazer a parte de pernas, veja como é configurado o menu para nao se perder .. para o lado direito, as penas afinam e para o esquerdo, aumentam.. , note que aumentam de forma natural, e simetricamente seguindo o que ja estava ali.. precisamos fazer exatamente isso..». Referência: Meitu → Pernas → Legs, slider bipolar, com «Bloqueio de fundo».

## Menu

O Ajustar corpo passou a ter duas abas, como no Meitu:

| Aba | Ferramentas | Categoria |
|---|---|---|
| Magro | Cintura (`waist`) | `BeautyAdjustmentCategory.corpo` |
| Pernas | Pernas (`legs`) | `BeautyAdjustmentCategory.pernas` |

As chaves vivem em `BodyWarpChain` (`slimParameterKeys`, `legParameterKeys`). A cadeia é `waist → legs`. «Travar fundo» aparece nas duas abas e cobre as duas ferramentas.

O Meitu tem ainda Thighs, Calves e Straight legs na aba Pernas, e um selector Geral / esquerda / direita. Ficam para depois: hoje o slider actua nas duas pernas por igual.

## Field

`lib/features/editor/beauty_engine/warp/v2/body_legs/body_legs_field.dart`

- **Eixo por perna:** anca → tornozelo (landmarks 23→27 e 24→28). Sem tornozelo visível, prolonga-se anca→joelho ×2. Sem anca visível, ou com o joelho fora da foto, não há campo. Como o MediaPipe também põe o joelho dentro do quadro, colado à borda, exige-se ainda o tornozelo dentro da foto ou canela à vista (`joelho + 0,6 · coxa` dentro da foto; era 0,2 e deixava passar a `body-p02`, que o Meitu não reconhece) e, com ombros visíveis, coxa ≥ 0,5 × tronco (ombros→ancas): o MediaPipe extrapola o joelho para fora do quadro com visibilidade alta, e numa foto cortada acima do joelho (`body-p02`) a faixa caía na anca, onde estão as mãos, e apertava mãos e pulseiras. `n` é a perpendicular de cada perna, virada para a direita da foto.
- **Bordas** (64 amostras ao longo do eixo, alisadas com mediana de 5 e caixa ×2):
  - De fora: primeira saída da máscara entre `0.3×` e `1.8×` a estimativa `distânciaEntreAncas · lerp(0.50, 0.18, s)`.
  - De dentro: primeira saída até a meio caminho da outra perna. Se não sair, as coxas estão encostadas e o vão é 0. Se sair, o vão é a distância até a máscara voltar (a outra perna).
- **Simetria:** cada perna escala por igual em volta do **seu** centro, medido na máscara, por isso as duas bordas andam o mesmo e a forma da perna fica: `D = −α · band · (u − âncora) · n`.
- **Coxas encostadas:** a âncora é a linha de contacto, que fica parada; a perna afina ou engrossa só para fora. A âncora passa ao centro à medida que o vão abre, com `abertura = smoothstep(vão / (0.8 · meia-largura))`. Assim não se inventa um vão onde as coxas se tocam, que é o que o Meitu faz.
- **Fora da perna:** o valor da borda decai por smoothstep. Para fora, em `0.55 × meia-largura`. Para dentro, em `min(0.55 × meia, 0.45 × vão)`, ou seja, a cauda acaba antes do meio do vão e as duas pernas não se tocam no campo.
- **Faixa ao longo do eixo:** sobe de `s = 0.08` a `0.28` (anca e virilha) e desce de `0.80` a `0.95` (tornozelo). A bacia e os pés ficam parados.
- **Força:** `α = 0.12 · t`. Cada borda livre anda cerca de 12% da meia-largura no extremo.
- **Injectividade:** a cauda de dentro é a mais apertada. Com `0.8` no vão de abertura, a razão `1.5 · V / F` não passa de 0,56, ou seja `det ≥ 0.44`. Com `0.5` ficava em 0,9 e dobrava. Fora, com âncora na borda de dentro, a razão é no máximo `1.5 · 2α / 0.55 ≈ 0.65`. Os testes medem `minDetJ > 0.3` nos dois extremos.
- **Cache:** `BodyLegsFieldRuntime` (chave `identical(pose) && identical(mask) && tamanho`). O slider só reescala os pixels activos.

## Cadeia e trava

`applyBodyWarpChain` constrói os campos activos (`waist`, `legs`) a partir da pose e da máscara originais, e encadeia um remap por campo. Não se somam campos. As duas zonas quase não se tocam: a Cintura acaba acima da anca e as Pernas começam abaixo dela. Com a trava, o fundo limpo cobre o suporte dos dois campos e `bandPx = ceil(maior deslocamento das ferramentas activas) + 6`.

## Testes

`test/beauty_engine/body_reshape/body_legs_field_test.dart`, com bacia, coxas encostadas e duas pernas de 40 px com um vão de 20 px:

- mede largura 40 ± 2 e vão 20 ± 2 nas duas pernas;
- `t = +1` afina e `t = −1` engrossa, com as duas bordas de cada perna a andar o mesmo (diferença < 0,75 px);
- nas coxas encostadas, a linha de contacto continua a ser pessoa e as bordas de fora andam;
- anca e pés com deslocamento zero;
- `minDetJ > 0.3` em `t = ±1`;
- o campo em cache reescalado é igual ao construído do zero;
- sem ancas visíveis ou com `t = 0`, devolve `null`;
- com trava, o fundo entre as pernas fica igual à origem (tolerância de 2 níveis); sem trava, estica.

## Limites conhecidos

- **Mão ou braço junto à coxa** (`body-p01`, mão com os óculos; `body-p02`, mãos na cintura): a procura da borda de fora continua pela mão até ao tecto de 1,8×, e a mão é puxada.
- **Perna de perfil ou cruzada:** o eixo anca→tornozelo é recto. Com o joelho muito dobrado, a normal deixa de ser perpendicular à canela. Num corpo de pé está bem.
- **Vão estreito** (menos de 0,8 meias-larguras): a perna afina mais para fora do que para dentro, por injectividade.
- **Sem selector L/R** nem Thighs, Calves ou Straight legs.


## Ferramenta indisponível (2026-10-01)

Sem pernas reconhecidas (regra do joelho acima), o chip «Pernas» fica cinzento e não selecciona; o toque mostra sobre a foto «Falha ao reconhecer as linhas das pernas, não foi possível ajustar.» (`BodyWarpChain.unavailableKeys` → `BeautyAdjustmentsPanel.unavailableToolKeys`). Igual ao Meitu. As Coxas têm regra própria (`v2-body-thighs.md`).
