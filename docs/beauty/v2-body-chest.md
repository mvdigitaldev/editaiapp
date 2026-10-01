# Busto (Chest) — corpo V2

Key `chest`. Aba **Busto**, depois dos Braços (`corpo, pernas, curvas, bracos, busto`). Ferramenta «Peito». Livre, sem cadeado, como o Chest do Meitu.

## Pedido

Leonardo, 2026-10-01, com o Meitu Busto → Chest na `body-p04`: «vamos para o busto agora.. são na parte dos seios.. não quebre o código.. para o lado direito aumenta e para o esquerdo diminui».

## Deformação

`BodyChestField` (`warp/v2/body_chest/body_chest_field.dart`): Field V2 em CPU, escala radial em volta de cada seio.

- **Centros pela pose:** o MediaPipe não marca o peito. A linha dos centros fica abaixo da linha dos ombros a `0,27 ×` o tronco (ombros→anca), limitada a `0,35`–`0,55 ×` a largura dos ombros. Sem anca, o tronco estima-se em `1,6 ×` os ombros. Cada centro fica a `±0,27 ×` a largura dos ombros do eixo. Na `body-p04` os centros caem em (292, 497) e (407, 497), com raio de 64 px, que é o meio de cada taça do top.
- **Campo:** `D = α · w(ρ) · (q − c)`, com `w = (1 − ρ²)²`, `ρ = |q − c| / R` e `R = 0,30 ×` a largura dos ombros. É liso e zero na borda do disco. A derivada radial fica em `[1 − α, 1 + 0,8 α]` e o mínimo de `det J` é `(1 − α)²`, no centro, logo nunca dobra. Os dois discos somam-se no esterno, onde quase não se tocam.
- **Ganho `0,18`:** no centro a escala é `1/(1 − α)`, cerca de 1,22× no extremo. O maior deslocamento é `0,29 · R · α`, cerca de 3,3 px na `body-p04`.
- **Sentido:** direita aumenta, esquerda diminui.
- **Disponibilidade:** ombros visíveis, de frente (ombros ≥ `0,35 ×` o tronco) e os dois centros dentro da foto. Senão o chip fica cinzento e o toque mostra «Falha ao reconhecer o busto, não foi possível ajustar.».
- **Máscara:** o Field não usa a `PersonMask`. O fundo à volta do busto fica protegido pela trava de fundo, que cobre o Peito pelo `maxEdgeShift`.

## Cadeia

`waist → hips → legs → thighs → calves → arms → chest`, cada um com o seu remap e medido na pose original. O slider só reescala o `BodyChestFieldRuntime`, cuja chave é `identical(pose) && size`.

## Testes

`test/beauty_engine/body_reshape/body_chest_field_test.dart`:

- centros e raio onde a spec diz;
- direita aumenta (área do busto > 1,15×) e esquerda diminui (< 0,88×);
- deslocamento máximo ≤ `maxEdgeShift`;
- ombros, esterno acima, cintura e braços ficam parados;
- `minDetJ > 0,6` nos dois extremos (o teórico é 0,67);
- sem ombros ou de perfil, indisponível;
- o slider só reescala o cache.

## Limites conhecidos

- O centro vem da pose, não do corpo: num busto muito alto ou muito baixo face aos ombros, o disco fica um pouco ao lado.
- Um braço cruzado à frente do peito, dentro do disco, escala com o busto.
