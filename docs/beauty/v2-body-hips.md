# Quadris (Hips) — corpo V2

Key `hips`. Aba **Curvas** do Ajustar corpo (`bodyOnly`), depois de Magro e Pernas, como no Meitu. Ferramenta livre (sem cadeado).

## Pedido

Leonardo, 2026-10-01, com a `body-p02` e o Meitu Curvas → Hips: «quando para lado esquerdo, diminui quadris sem distorcer a imagem.. fica perfeito, precisamos replicar exatamente isso e para lado direito aumenta».

## Deformação

Sem Field novo: é o `BodyWaistField` da Cintura com outra faixa, `BodyTorsoBand.hips`. Pela mesma regra das Coxas: nunca um Field por zona.

- **Eixo:** ombros → ancas (11/12 → 23/24), `t = 0` nos ombros e `t = 1` nas ancas.
- **Faixa:** `centerT = 1.02`, `halfSpanT = 0.32`, ou seja de `t = 0.70` (abaixo da cintura) a `1.34` (topo da coxa), com peso `(1 − z²)²`. A cintura (`t ≤ 0.5`) e a coxa abaixo de `1.34` ficam paradas.
- **Escala:** `D = −α · w(t) · u · n`, com `u` a distância ao eixo. Dentro da silhueta é uma escala proporcional à distância, por isso a textura da saia estica por igual. Fora dela decai por smoothstep em `0.55 × meia-largura`, igual à Cintura.
- **Sentido:** `gain = −0.14`. **Direita alarga, esquerda afina**, ao contrário da Cintura, como no Meitu.
- **Injectividade:** `1 − 0.14 · 1.5 / 0.55 = 0.62 > 0`. O teste exige `minDetJ > 0.5` nos dois extremos.
- **Borda:** vem da `PersonMask`, com tecto de `1.35 ×` a estimativa da pose (`1.75 ×` a meia-distância das ancas). Abaixo das ancas o eixo pode cair no vão entre as pernas. Com `skipCenterGap`, a busca anda até entrar na silhueta e mede a saída a partir daí, em vez de cair na estimativa (teste: 30 px medidos contra 26,3 px estimados).
- **Mãos na anca:** fazem parte da máscara e andam com o quadril, como no Meitu.

## Cadeia

`waist → hips → legs → thighs`, todos sobre a pose e a máscara de origem, sem advecção. A trava de fundo cobre os Quadris pelo mesmo caminho: o `maxEdgeShift` dos Quadris entra no `bandPx`.

## Testes

Grupo «Quadris» em `test/beauty_engine/body_reshape/body_waist_field_test.dart`:

- direita alarga e esquerda afina;
- as duas bordas andam o mesmo;
- borda de fora medida com o vão no eixo;
- cintura, coxa e ombros parados;
- `minDetJ > 0.5` nos dois extremos;
- cache separado por faixa, e o slider só reescala.
