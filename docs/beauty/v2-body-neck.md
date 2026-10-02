# Pescoço (Linhas do pescoço → Width) — corpo V2

Key `neck`, ferramenta «Pescoço». Aba **Pescoço** (Meitu «Linhas do pescoço»), depois dos Ombros. Livre, sem cadeado, como o segundo Width do Meitu.

## Pedido

Leonardo, 2026-10-02, com três prints do Meitu Linhas do pescoço → Width (o do pescoço: original, direita, esquerda): «para lado direito afina e esquerdo aumenta».

## Deformação

`BodyNeckField` (`warp/v2/body_neck/body_neck_field.dart`): Field V2 em CPU, só Δ perpendicular ao eixo ombros→boca.

- **Eixo:** do meio dos ombros (11, 12) ao meio da boca (9, 10), ou ao nariz (0) sem boca. A boca tem de estar na foto e acima dos ombros, a pelo menos `0,3 ×` a largura deles.
- **Largura:** a `PersonMask` não serve, porque o cabelo cai ao lado do pescoço e faz parte da pessoa. A meia-largura estima-se em `H = 0,17 ×` a largura dos ombros.
- **Lateral:** dentro do pescoço, `D = −α · u` comprime para o eixo, como a Cintura, e a textura encolhe por igual. Fora, a borda decai por smoothstep em `0,8 H`.
- **Vertical**, em fracções `v` da distância ombros→boca: sobe de 0 a 0,18, fica cheio até 0,50 e acaba em 0,72, antes do queixo. A cara (rosto congelado) e a linha dos ombros não mexem.
- **Ganho `0,15`:** cada borda anda `α · H`, cerca de 6 px num ombro de 250 px no extremo. `det J ≥ 0,6`.
- **Sentido:** direita afina, esquerda engrossa.
- **Disponibilidade:** sem ombros ou sem cara na pose, o chip fica cinzento e o toque mostra «Falha ao reconhecer o pescoço, não foi possível ajustar.».

## Cadeia

`… → chest → shoulders → neck`, cada um com o seu remap e medido na pose original. A trava de fundo cobre o Pescoço pelo `maxEdgeShift` (`gain · H`).

## Testes

`test/beauty_engine/body_reshape/body_neck_field_test.dart`:

- eixo e meia-largura;
- direita afina e esquerda engrossa (mais de 4 px na largura);
- cara, linha dos ombros e o que fica ao lado parados;
- `minDetJ > 0,6`;
- sem cara, indisponível;
- o slider só reescala o cache.

## Limites conhecidos

- O cabelo encostado ao pescoço, dentro de `1,8 H` do eixo, anda com ele.
- Num pescoço muito largo ou estreito face aos ombros, a borda real não coincide com `H`.
- Com a cabeça muito virada, o eixo vai da base do pescoço à boca e não ao meio da garganta.
