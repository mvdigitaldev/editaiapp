# Ombros (Linhas do pescoço → Width) — corpo V2

Key `shoulders`, ferramenta «Ombros». Aba **Pescoço** (Meitu «Linhas do pescoço»; o nome longo cortava na barra), depois do Busto (`corpo, pernas, curvas, bracos, busto, pescoco`). Livre, sem cadeado, como o Width do Meitu.

## Pedido

Leonardo, 2026-10-01, com três prints do Meitu Linhas do pescoço → Width (original, esquerda, direita): «acredito que esse primeiro é ombro.. para o lado direito aumenta e esquerdo diminui, observe os prints e faça idêntico».

## Deformação

`BodyShouldersField` (`warp/v2/body_shoulders/body_shoulders_field.dart`): Field V2 em CPU, só Δ ao longo da linha dos ombros (11→12), para fora do eixo do corpo.

- **Lateral**, com `S` a largura dos ombros e `u` a distância ao eixo:
  - o pescoço e a cabeça (`|u| < 0,15 S`) ficam parados;
  - o campo sobe por smoothstep até ao ponto do ombro (`0,5 S`);
  - mantém-se até à borda da silhueta, medida na `PersonMask` em cinco linhas de `0` a `0,20 S` abaixo dos ombros (mediana, até `0,85 S`; sem máscara, `0,62 S`);
  - depois da borda cai em `0,35 S`, e é o fundo que fecha o espaço.
- **Vertical:** cheio de `−0,10 S` a `0,22 S` em volta da linha dos ombros. Sobe desde `−0,35 S`, a base do pescoço e o trapézio, e cai até `0,60 S`, antes do busto.
- **Ganho `0,07`:** cada ponta anda `α · S / 2`, cerca de 9 px num ombro de 250 px no extremo. Os declives ficam em cerca de `2 α`, e `det J ≥ 0,85`.
- **Sentido:** direita alarga, esquerda estreita.
- **Disponibilidade:** ombros visíveis, dentro da foto e de frente (`S ≥ 0,35 ×` o tronco). Senão o chip fica cinzento e o toque mostra «Falha ao reconhecer os ombros, não foi possível ajustar.».

## Cadeia

`waist → hips → legs → thighs → calves → arms → chest → shoulders`, cada um com o seu remap e medido na pose e na máscara originais. A trava de fundo cobre os Ombros pelo `maxEdgeShift` (`α · S / 2`). O slider só reescala o `BodyShouldersFieldRuntime`.

## Testes

`test/beauty_engine/body_reshape/body_shoulders_field_test.dart`:

- borda medida na máscara (±1,5 px);
- direita alarga e esquerda estreita, mais de 5 px na linha dos ombros, com as duas pontas por igual;
- pescoço, cabeça e busto parados;
- `minDetJ > 0,75` nos dois extremos;
- sem ombros ou de perfil, indisponível;
- o slider só reescala o cache.

## Limites conhecidos

- O cabelo solto sobre os ombros anda com eles.
- Com os braços levantados, como na `body-p04`, é o topo do braço que anda para fora.
