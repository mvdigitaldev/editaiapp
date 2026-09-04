# Head — tamanho da cabeça

Efeito novo. **Não** é zoom de câmara da foto. **Não** é `head_size` (key morta). **Não** é Hairline, Width nem Lift.

Data: 2026-09-04.  
Estado: D no editor. Sem E escrita. Jaw, Chin, V Chin, V Shape, Cheekbones H, Jaw Angle e Hairline **não se mexem**. Lab: [`v2-head-b-report.md`](./v2-head-b-report.md). C: [`v2-head-c-report.md`](./v2-head-c-report.md). D: [`v2-head-d-report.md`](./v2-head-d-report.md).

Módulo: `lib/features/editor/beauty_engine/warp/v2/head/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).  
Plano: [`v2-head-plan.md`](./v2-head-plan.md).

---

## 1. Papel

A **cabeça inteira** (cabelo + cara + queixo) cresce ou encolhe no sítio. O fundo longe não anda. Depois, Rosto (queixo, mandíbula, linha do cabelo) mede a geometria **já escalada**, porque os landmarks avançam com o campo.

| Peça | Vigente (Sprint A) |
|---|---|
| Key | `head` (nunca `head_size`) |
| Label | **Cabeça** (menu Proporção, só na D) |
| Slider | Bipolar: centro = 0. **Sem** L/R. Vivo no tab Proporção |
| Convenção | **Esquerda = cresce** (`t < 0`, `s > 1`). **Direita = encolhe** (`t > 0`, `s < 1`) |
| Field | `D = w · (q − c) · (1 − 1/s)`, `s = 1 − k t` |
| Escala | `k = 0.12` (0,22 invertia na rampa: `|∇w| · |q−c| · α > 1`) |
| Centro | bbox do `faceOval` |
| Têmporas / fundo | rampa a zero. Sem disco. Sem Temple |

Não é Bloqueio de fundo. Não é Top / Testa / Middle / Philtrum.

---

## 2. Equação

```
t ∈ [-1, 1]
identidade se |t| ≤ 1e-6

s = 1 − 0.12 · t
α = 1 − 1/s

w = máscara da cabeça × rampa de bordo
    (sem crista, sem decaimento transversal)

D = w · (q − c) · α · min(1, R₊ / |q − c|)
    R₊ = (1 + k) · raio da cabeça original
    (satura na rampa para |∇w| · |q−c| não inverter)
```

`src = dest − D`. No núcleo (`w = 1`) é uma semelhança: os landmarks afastam-se ou aproximam-se de `c` pelo mesmo `s`. Na rampa, `∇w` entra no jacobiano — `minDetJ > 0` não basta; medir vinco e degrau de entrada.

- `t < 0` → cresce. Silhueta **sai** do oval original.
- `t > 0` → encolhe. O anel entre a cara nova e a antiga **não** é identidade (senão fica fantasma).
- `t = 0` → campo nulo

`c` calcula-se no Field (bbox do oval). Não se importa `FaceWarpUtils`.  
`w` é [`BoundaryFeather`](../../lib/features/editor/beauty_engine/warp/v2/boundary_feather.dart). **Não** é `RidgeWeight`. **Não** é `max` de gaussianas.

O runtime cacheia `unitDx` / `unitDy` (`w · (q − c) · min(1, R₊ / |q − c|)`). O slider só multiplica por `α(t)`, que **não** é linear em `t`. `w` **não** depende de `t`. Sem buraco em `c`.

---

## 3. Domínio

O remap é backward: quem precisa de `w > 0` é o píxel de **destino**.

Suporte = cara original ∪ cara no enlarge extremo (`s = 1 + k`). Hull = `faceOval` + cap levantado + orelhas + **asas laterais** (cabelo fora do mesh), **mais** os mesmos pontos escalados `c + s_max (p − c)`, cortados à margem da imagem. Pad curto + rampa. Sem 9/151 como origem. Sem disco no queixo. Sem `PersonMask`.

| Constante | Valor |
|---|---|
| k | `0.12` |
| Rampa de bordo | `0.24 × faceWidth` |
| Hull pad | `0.28 × faceWidth` (rampa **fora** da silhueta aumentada) |
| Crown extend | `0.70 × faceWidth` (limitado pelo topo; só o cap) |
| Hair wing | `0.34 × faceWidth` (Δx nas têmporas/orelhas/gónio; o mesh não tem a silhueta do cabelo) |
| ridgeBlend | não aplica |
| 10 / 152 / 58 / 288 | **andam** com a cabeça |
| olhos / boca / nariz | **andam** (não são hard-zero) |
| fundo longe | ≈ 0 |

Dilatar em função do `t` do slider é proibido (parte o cache).

---

## 4. Pipeline e menu

Cadeia (primeiro):

```
head → hairline → jaw → jaw_angle → chin → v_chin → v_shape → cheekbone
```

Painel: tab **Proporção**, ícone Cabeça. Rosto não perde sliders. Preview e export usam o mesmo `applyFaceWarpChain`.

Pele, Cor e Body continuam a ler o `face` da detecção. Limitação conhecida: não se corrige nesta A.

---

## 5. O que não entra

- Alterar Jaw / Chin Length / V Chin / V Shape / Cheekbones H / Jaw Angle / Hairline
- Zoom da foto inteira, Telea, clamp à borda
- Face Rig, receitas, slider composto
- Reutilizar `head_size`
- Bloqueio de fundo, Top, Testa, Middle, Philtrum, Temple, Width, Lift
- Ligar slider ou cadeia sem C (C já assinada; D ligada)
- Hard-zero em olhos, boca ou queixo
- Compensar o Head “ajustando” outro Field

---

## 6. Lab B

15 `v2Raw` em `.cursor/facial-warp-v2/head/B/`. Relatório [`v2-head-b-report.md`](./v2-head-b-report.md).

Encolher (`t > 0`) pede origem mais longe de `c`. Em p01 e p05 o cap está contra o topo do crop: `invalidSource` no cap, **sem fill**. p12 tem margem e fica a 0. Crescer não fura o rect. Fundo longe parado. C assinada 2026-09-04.
