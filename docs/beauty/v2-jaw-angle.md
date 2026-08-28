# Jaw Angle — ângulo de mandíbula

Efeito novo. **Não** é o Jaw (`jaw`, estreitar em Δx). **Não** é Chin Length. **Não** é Sprint C assinada.

Data: 2026-08-27.  
Aprovação: Leonardo pediu o Ângulo da mandíbula (inclinação dos gônios, L/R, sangria leve no final do queixo). Jaw, Chin, V Chin, V Shape e Cheekbones H não se mexem.

Módulo: `lib/features/editor/beauty_engine/warp/v2/jaw_angle/`.  
Memória: [`PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md).

---

## 1. Papel

Meitu Jaw angle: canto sob a orelha (setas no gônio). O `jaw` continua a ser a **largura** (Δx). O 152 continua a ser Chin Length.

| Peça | Vigente |
|---|---|
| Key | `jaw_angle` |
| Label | **Ângulo da mandíbula** |
| Slider | Bipolar Meitu: centro = 0, sem %. Flag Geral / Esquerda / Direita = lados da **foto** |
| Convenção | **Direita = sobe** (`dy < 0`). **Esquerda = desce** (`dy > 0`) |
| Field | Só Δy. `dx = 0`. Cunha oval **58→172→136**. Ponta 152 com sangria (não trava dura). Maçã 123/352 hard-zero |
| Amplitude | `0.052 × faceWidth` |
| Params | `jaw_angle`, `jaw_angle_left`, `jaw_angle_right`, `jaw_angle_side` |

Inspecção no editor. C/D/E **não** assinadas.

---

## 2. Equação

```
t ∈ [-1, 1] por lado da foto
identidade se |tPhotoLeft| e |tPhotoRight| ≤ 1e-6

dx = 0
dy = −t_lado · 0.052 · faceWidth · w
```

Foto esquerda = cadeia MediaPipe direita (288). Foto direita = cadeia MediaPipe esquerda (58).

- `t > 0` → gônio sobe
- `t < 0` → gônio desce
- `t = 0` → campo nulo

`w` = distância à polilinha **58→172→136** / **288→397→365** (com pontos médios) × rampa de bordo × rampa midline estreita × sangria na ponta (chão 0.22, não hard-zero). A crista **não** é `max` de gaussianas.

---

## 3. Crista

| Lado (MediaPipe) | IDs | Pesos |
|---|---|---|
| Esquerdo | 58 → 172 → 136 | 1.00 → 0.72 → 0.48 |
| Direito | 288 → 397 → 365 | idem |

Pico no gônio. A cunha desce aos **lados do queixo** (riscas Meitu). A ponta 152 segue pouco (sangria), não é trava. A maçã (123/352) fica parada.

| Constante | Valor |
|---|---|
| Amplitude | `0.052 × faceWidth` |
| σ transversal | `0.14 × faceWidth` |
| Rampa de bordo | `0.15 × faceWidth` |
| Hull pad | `0.16 × faceWidth` |
| Midline | rampa `0.045 × faceWidth` (estreita: 0.10 matava os lados do queixo) |
| 152 | sangria (chão 0.22), não hard-zero |
| 123 / 352 | hard-zero (maçã) |
| 172 / 136 | sopro / cauda da cunha |

---

## 4. Pipeline e menu

Ordem no preview e no export:

```
applyJawWarp → applyJawAngleWarp → applyChinWarp → applyVChinWarp → applyVShapeWarp → applyCheekbonesWarp
```

Painel Rosto: `['jaw', 'jaw_angle', 'chin', 'v_chin', 'v_shape', 'cheekbone']`.  
Field no disco; inspecção no editor. C **não** assinada.

Calibração 2026-08-28: pad/σ grandes + 152 a zero faziam gônio inchado e **trava no queixo**. Meitu (riscas) é cunha até aos lados do queixo. Amplitude `0.052`, crista 58→172→136 (1.00→0.72→0.48), midline `0.045`, sangria no 152 (chão 0.22).

---

## 5. O que não entra

- Alterar Jaw / Chin Length / V Chin / V Shape / Cheekbones H
- Δx no gônio (é o Jaw)
- Rodar o 152 como Chin Length (a ponta não é o pico; os lados do queixo seguem)
- Assinar Sprint C
