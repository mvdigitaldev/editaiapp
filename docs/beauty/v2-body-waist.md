# Body V2 — Cintura (`waist`)

Estado: **no editor para inspecção visual** (2026-10-01). Primeiro menu do corpo depois do menu zerado.

Pedido do Leonardo: «vamos comecar com o primeiro menu, waist ele emagrece um pouco a linha da cintura, pesquise como aplciativos fazem isso de forma excepcional, se temos q fazer as mascaras do corpo igual fizemos do rosto etc». Referência: Meitu → Magro → Waist. Slider bipolar: à direita afina a cintura, à esquerda alarga.

## Como os apps fazem

Os apps (Meitu, BeautyPlus, Facetune, e as demos de BodyPix/MediaPipe) usam o mesmo esquema:

1. **Segmentação da pessoa.** Dá a silhueta: onde está a borda da cintura em cada altura.
2. **Pose.** Dá o eixo do tronco (meio dos ombros → meio do quadril) e a altura da faixa da cintura.
3. **Warp horizontal em direcção ao eixo** dentro da faixa, com queda suave para cima e para baixo e para o fundo. O fundo junto à borda estica para fechar o espaço. O Meitu tem um toggle «Bloqueio de fundo» que protege linhas rectas do fundo; não é o comportamento padrão.

## Precisamos de máscaras como no rosto?

**Não no mesmo sentido.** No rosto há 478 landmarks: os polígonos (oval, crista, hull) saem directamente dos pontos. A pose tem 33 pontos, e só 4 interessam à cintura (11/12 ombros, 23/24 quadril). Não dá para desenhar a silhueta com eles.

Por isso, no corpo:

| Papel | Fonte |
|---|---|
| Eixo, faixa, estimativa de largura | pose (11/12/23/24) |
| Borda real da cintura | `PersonMask` (já existe no pipeline) |
| Protecção de braços/mãos | por fazer (segmentação de partes) |

Sem máscara, a borda vem da estimativa da pose e o efeito continua a funcionar, só que menos preciso.

## Field

`lib/features/editor/beauty_engine/warp/v2/body_waist/body_waist_field.dart`

- `e` é o eixo ombro-médio → quadril-médio. `n` é a perpendicular, virada para a direita da foto. `t` é a posição ao longo do eixo e `u` a distância com sinal a partir dele.
- Faixa: `band = (1 − z²)²`, com `z = (t − 0.66) / 0.30`. Cobre `t ∈ (0.36, 0.96)`, ou seja, não mexe nos ombros nem nas coxas.
- Bordas: para cada uma de 48 amostras de `t`, procura-se a primeira saída da máscara a partir do eixo em cada lado, com o raio limitado a `[0.45, 1.35] ×` a estimativa da pose `lerp(0.9 · meiaOmbro, 1.75 · meiaQuadril, t)`. Depois alisa-se com mediana de 5 e caixa de raio 4 duas vezes.
- Perfil: dentro da silhueta, `|u|` (compressão uniforme, a textura da roupa encolhe por igual). Fora, o valor da borda decai por smoothstep numa banda de `0.55 × meia-largura`.
- Deslocamento: `D = −α · band · perfil · sign(u) · n`, com `α = 0.10 · t`. A borda anda cerca de 10% da meia-largura no extremo.
- Injectividade: `det = 1 + α · band · perfil'`. O pior caso é a descida do smoothstep, com inclinação 1,5/0,55, o que dá folga de 0,73 no extremo. Os testes medem `minDetJ > 0.5` nos dois extremos.
- O slider não reconstrói nada: `BodyWaistFieldRuntime` guarda o campo unitário (chave `identical(pose) && identical(mask) && tamanho`) e o acerto só reescala os pixels activos.

## Cadeia

```
RGBA → applyFaceWarpChain → applyBodyWarpChain (waist) → GPU (Body legado = identidade) → Skin → Color
```

`applyBodyWarpChain` vive no `BeautyEngineController` e é chamada pelo preview (`_renderTexture`) e pelo export (`TiledExportEngine`). Um remap `BackwardBilinearWarp` por efeito; não se somam campos. As chaves de corpo vivem em `BodyWarpChain` (`filters/body/body_warp_chain.dart`).

A person mask é detectada quando `BodyWarpChain.hasActive` for verdadeiro, tanto no preview como no export.

## UI

Ajustar corpo → **Cintura**. Slider bipolar −1…1: direita afina, esquerda alarga.

## Testes

`test/beauty_engine/body_reshape/body_waist_field_test.dart`, com tronco e máscara sintéticos:

- borda medida na máscara (±1,5 px);
- `t = +1` estreita a linha da cintura em pelo menos 4 px; `t = −1` alarga-a em pelo menos 4 px;
- ombros, coxas e cabeça com deslocamento zero;
- `minDetJ > 0.5` em `t = ±1`;
- o campo em cache reescalado é igual ao construído do zero;
- sem pose fiável ou com `t = 0`, devolve `null`; sem máscara, usa a estimativa da pose.

## Limites conhecidos

- **Braço colado ao tronco** (`body-p02`, mãos na cintura): a máscara continua pelo braço, a procura pára no tecto de 1,35× e o braço ou a mão é parcialmente puxado. Pede segmentação de partes; fica para depois.
- **Fundo estica** na banda de queda, como nos apps sem «Bloqueio de fundo». Linhas rectas do fundo junto à cintura podem curvar.
- Sem pose JSON nos fixtures de corpo: não há ainda teste nas fotos reais. A inspecção é visual, no editor.
