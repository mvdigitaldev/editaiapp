# Body V2 — Coxas (`thighs`)

Estado: **no editor para inspecção visual** (2026-10-01). Ferramenta **só do plano pago**, na aba Pernas, depois de Pernas.

Pedido do Leonardo: «agora vamos para Things (nao sei oq é parece coxas.. mas n fica travado apenas na coxa, tem um pequeno movimento para nao ficar tao robotico e travado proximo ao joelo um pouco pra baixo.. repare nas imagens.. oq pode ser feito? tbm esse efeito deve ser liberado somente se a pessoa tiver o plano pro... fica um cadeadinho rosa ali em cima do novo icone.. faca isso sem errar nada..». Referência: Meitu → Pernas → Thighs, slider bipolar: direita afina as coxas, esquerda engrossa.

## O que é

O mesmo Field das Pernas ([`v2-body-legs.md`](./v2-body-legs.md)), com outra **faixa ao longo da perna**. As regras são as mesmas:

- cada perna escala em volta do seu centro medido na máscara;
- onde as coxas se tocam, a linha de contacto fica parada;
- `α = 0.12 t`;
- com a trava ligada, o fundo fica parado.

Não há código de deformação novo.

## Faixa

`BodyLegBand.thighs`, relativa ao joelho de cada perna (`kneeS` é o joelho projectado no eixo anca→tornozelo, entre 0,25 e 0,75). Sem joelho fiável (fora da foto, sem perna abaixo dele ou coxa curta para o tronco), as Coxas não desligam como as Pernas: estima-se o joelho a `0,95 × tronco` (ombros→ancas) abaixo das ancas, na perpendicular à linha das ancas, e exige-se que se veja pelo menos `0,3` dessa coxa. Sem ombros nem isso, não há campo:

| Zona | Em fracção do joelho | Com joelho a 0,5 |
|---|---|---|
| Sobe (virilha) | 0,16 → 0,52 | `s` 0,08 → 0,26 |
| Coxa no máximo | 0,52 → 0,75 | `s` 0,26 → 0,375 |
| Desce (smoothstep) | 0,75 → 1,20 | `s` 0,375 → 0,60 |

No joelho o peso ainda vale cerca de 0,41, e o efeito acaba em 1,2× o joelho, ou seja, um pouco abaixo dele. É o «pequeno movimento para não ficar robótico» das capturas do Meitu: a coxa afina e a transição continua um pouco pela perna, sem degrau no joelho. A canela e o pé ficam parados.

As Pernas passaram a usar `BodyLegBand.legs`, com os mesmos números absolutos de antes (`s` 0,08→0,28 e 0,80→0,95). O comportamento delas não mudou.

## Plano pago

- `BodyWarpChain.proParameterKeys = {thighs}`.
- `BodyWarpChain.gatePaidFeatures` (antes `gateBackgroundLock`) tira a trava de fundo **e** as ferramentas pagas quando o utilizador não tem plano pago activo. Chama-se em `_gatedParams`, o mesmo ponto para o preview e o export.
- Painel (`proToolsAllowed`, `onProToolLocked`):
  - o chip «Coxas» leva sempre um **cadeado rosa** pequeno em cima (`_ProLockBadge`, 15 px, `#FF4D8D` com contorno branco), como o Meitu marca as ferramentas pagas;
  - sem plano, tocar no chip não selecciona a ferramenta e abre a folha «Ver planos» → `/subscription`;
  - se o plano vencer com as Coxas seleccionadas, o painel volta a Pernas.
- A folha de planos é a mesma da trava (`_showPaidFeaturePaywall`), com o título da ferramenta.

## Cadeia

`waist → legs → thighs`. Cada uma tem o seu runtime (`_bodyThighsRuntime`), e o runtime guarda também a faixa, para o cache de uma nunca servir a outra. Pernas e Coxas juntas encadeiam dois remaps sobre a mesma geometria medida na origem. Não se somam campos.

## Testes

Em `test/beauty_engine/body_reshape/body_legs_field_test.dart`, grupo Coxas:

- joelho medido em `s = 0,5`;
- `t = +1` afina a coxa com as duas bordas a andar o mesmo (diferença < 0,75 px); `t = −1` engrossa;
- no joelho mexe ainda, mas menos de 75% do que na coxa; canela, pé e bacia com deslocamento zero;
- `minDetJ > 0.3` em `t = ±1`;
- o cache reescala e não se mistura com o das Pernas.

Em `test/beauty_engine/body_reshape/body_background_lock_gate_test.dart`:

- `gatePaidFeatures` tira `thighs` e a trava sem plano e mantém-nos com plano;
- o chip das Coxas leva o cadeado;
- sem plano, o toque abre o aviso e o slider continua em Pernas; com plano, abre o slider das Coxas.

## Limites

Os mesmos das Pernas: a mão junto à coxa é puxada, e com o vão estreito a coxa afina mais para fora.


## Ganho e foto sem pernas à vista (2026-10-01)

Leonardo, com a `body-p02` (saia, mãos na anca, cortada acima do joelho) e o Meitu ao lado: «as coxas são muito mais suaves do que o movimento que você fez.. aí não distorce nada.. é um movimento mais seguro… e as pernas nem deveriam mexer, pois não aparecem».

- `BodyLegBand.gain`: Pernas `0,12`, Coxas **`0,06`**. Cada borda da coxa anda `≈ 0,06 × meia-largura` no extremo.
- Coxas com `requiresKnee: false`: joelho estimado pelo tronco quando o da pose não serve (acima).
- Pernas com `requiresKnee: true`: sem pernas reconhecidas o chip fica cinzento (`BodyWarpChain.unavailableKeys`, `BodyLegsField.isAvailable`, só pela pose) e o toque mostra sobre a foto «Falha ao reconhecer as linhas das pernas, não foi possível ajustar.», como o Meitu. O slider abre na primeira ferramenta que dá para usar.
